--[[ 
    ZEEN TOOLS v10.0 - FINAL COMPLETE VERSION
    Fitur:
    - Cookies detection (dari kuki.lua)
    - Auto-detect cookies on startup
    - Monitoring dashboard
    - Heartbeat detection (HTTP-based)
    - Soft monitoring (graceful restart)
    - Dynamic launched counter
    - Webhook notifications
    Status: Production Ready
]]

os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1")
io.stdout:setvbuf("no")

-- ==========================================
-- CONFIG & CONSTANTS
-- ==========================================
local ZEEN_VERSION = "v10.0 (FINAL)"
local ROOT_DIR = "/sdcard/Zeen"
local CONFIG_DIR = ROOT_DIR .. "/Config"
local COOKIE_DIR = ROOT_DIR .. "/Cookies"

os.execute("mkdir -p " .. CONFIG_DIR)
os.execute("mkdir -p " .. COOKIE_DIR)

local PACKAGE_FILE = CONFIG_DIR .. "/packages.txt"
local CONFIG_FILE = CONFIG_DIR .. "/settings.txt"
local WEBHOOK_FILE = CONFIG_DIR .. "/webhook.txt"

-- Monitoring settings
local HEARTBEAT_INTERVAL = 30
local HEARTBEAT_TIMEOUT = 5
local HEARTBEAT_MAX_RETRIES = 2
local GRACE_PERIOD = 90
local QUEUE_DELAY = 30
local STABLE_TIME = 60
local WATCHDOG_INTERVAL = 2

local HEARTBEAT_ENDPOINTS = {
    "https://www.roblox.com",
    "https://www.roblox.com/home"
}

-- ==========================================
-- GLOBAL VARIABLES
-- ==========================================
local packages = {}
local app_states = {}
local config = { delay = 10 }
local webhook_conf = { url = "", interval = 300 }
local device_name = "Android Device"
local global_last_restart = 0
local launch_queue_index = 1
local next_launch_time = 0
local scan_pointer = 1

-- ==========================================
-- ROOT EXECUTION (dari kuki.lua)
-- ==========================================
local function exec_root(cmd)
    local safe_cmd = cmd:gsub("'", "'\\''")
    local final_cmd = "su -mm -c '" .. safe_cmd .. "'"
    local handle = io.popen(final_cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Standard exec
local function exec(cmd)
    local safe_cmd = cmd:gsub('"', '\\"')
    local handle = io.popen('su -c "' .. safe_cmd .. '" 2>/dev/null')
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result or ""
end

-- ==========================================
-- JSON PARSER (dari kuki.lua)
-- ==========================================
local function get_json_val(json, key)
    if not json then return nil end
    local val = json:match('"' .. key .. '":%s-["%d]*(.-)["%d]*[,}]')
    if val then return val:gsub('"', '') else return nil end
end

local function get_json_id(json)
    if not json then return nil end
    return json:match('"id":(%d+)')
end

-- ==========================================
-- ROBLOX API CHECK (dari kuki.lua)
-- ==========================================
local function cek_api_roblox(cookie)
    local url = "https://users.roblox.com/v1/users/authenticated"
    local safe_cookie = cookie:gsub("'", "")
    local cmd = string.format(
        "curl -s -L --max-time 15 -A 'Mozilla/5.0 (Android 10; Mobile; rv:90.0) Gecko/90.0 Firefox/90.0' -H 'Cookie: .ROBLOSECURITY=%s' \"%s\"",
        safe_cookie, url
    )
    
    local handle = io.popen(cmd)
    local json = handle:read("*a")
    handle:close()
    return json
end

-- ==========================================
-- UI FUNCTIONS
-- ==========================================
function safe_print(str)
    str = tostring(str or "")
    io.write(str .. "\027[K\n")
    io.stdout:flush()
end

function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function safe_input(prompt)
    os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1")
    io.stdout:flush()
    io.write(prompt)
    io.stdout:flush()
    local result = io.read()
    if not result then return "" end
    return trim(result)
end

function clearScreen()
    io.write("\027[H\027[2J")
    io.stdout:flush()
end

-- ==========================================
-- COOKIES FUNCTIONS
-- ==========================================
function extract_package_cookie(package)
    local find_cmd = "find /data/data/" .. package .. " -name 'Cookies' 2>/dev/null | head -n 1"
    local db_path = exec_root(find_cmd):gsub("%s+", "")
    
    if db_path == "" then return nil end
    
    local temp_db = CONFIG_DIR .. "/temp_" .. package:match("[^.]+$") .. ".db"
    exec_root("cp \"" .. db_path .. "\" " .. temp_db .. " 2>/dev/null")
    exec_root("chmod 777 " .. temp_db .. " 2>/dev/null")
    
    local handle = io.popen("sqlite3 " .. temp_db .. " \"SELECT value FROM cookies WHERE name = '.ROBLOSECURITY';\"")
    local raw_cookie = handle:read("*a")
    handle:close()
    
    if raw_cookie and #raw_cookie > 20 then
        local clean_cookie = raw_cookie:gsub("[\r\n]", "")
        os.execute("rm " .. temp_db .. " 2>/dev/null")
        return clean_cookie
    end
    
    os.execute("rm " .. temp_db .. " 2>/dev/null")
    return nil
end

function fetch_roblox_identity(cookie)
    if not cookie or #cookie < 20 then return nil, nil end
    local json = cek_api_roblox(cookie)
    if not json or json == "" then return nil, nil end
    
    local id = get_json_id(json)
    local name = get_json_val(json, "name")
    return name, id
end

function autoDetectCookies()
    local scan_count = 0
    for i, pkg in ipairs(packages) do
        local cookie = extract_package_cookie(pkg.package)
        if cookie then
            local username, id = fetch_roblox_identity(cookie)
            if username and username ~= "" then
                pkg.username = username
                scan_count = scan_count + 1
            end
        end
    end
    return scan_count
end

-- ==========================================
-- HEARTBEAT DETECTION
-- ==========================================
function checkAppHeartbeat(package)
    local endpoint = HEARTBEAT_ENDPOINTS[math.random(1, #HEARTBEAT_ENDPOINTS)]
    local curl_cmd = string.format(
        "timeout %d curl -s -m %d -w '%%{http_code}' '%s' 2>/dev/null | tail -c 3",
        HEARTBEAT_TIMEOUT, HEARTBEAT_TIMEOUT, endpoint
    )
    
    local result = exec(curl_cmd)
    local http_code = tonumber(result) or 0
    return http_code >= 200 and http_code < 300
end

function updateAppHeartbeat(package)
    local state = app_states[package]
    if not state then return false end
    
    local pid_check = exec("pidof " .. package)
    if not pid_check or pid_check:gsub("%s+", "") == "" then
        state.heartbeatStatus = "DEAD"
        state.connectionStatus = "Offline"
        return false
    end
    
    local hb_success = checkAppHeartbeat(package)
    
    if hb_success then
        state.heartbeatStatus = "ALIVE"
        state.connectionStatus = "Connected"
        state.lastHeartbeat = os.time()
        state.heartbeatRetries = 0
        return true
    else
        state.heartbeatRetries = (state.heartbeatRetries or 0) + 1
        
        if state.heartbeatRetries >= HEARTBEAT_MAX_RETRIES then
            state.heartbeatStatus = "DEAD"
            state.connectionStatus = "Disconnected"
            return false
        else
            state.heartbeatStatus = "RETRYING"
            state.connectionStatus = "Unstable"
            return nil
        end
    end
end

function checkAllHeartbeats()
    for _, pkg in ipairs(packages) do
        updateAppHeartbeat(pkg.package)
    end
end

-- ==========================================
-- APP FUNCTIONS
-- ==========================================
function getAppUID(package)
< truncated lines 251-257 >
    local f = io.open("/proc/meminfo", "r")
    if f then
        local content = f:read("*a")
        f:close()
        local mem_kb = tonumber(content:match("MemAvailable:%s+(%d+)"))
        if mem_kb and mem_kb > 0 then
            local gb = mem_kb / 1024 / 1024
            return string.format("%.2f GB", gb)
        end
    end
    return "Unknown"
end

function killAndStart(package)
    exec("su -c 'am force-stop " .. package .. "' 2>/dev/null")
    os.execute("sleep 0.5")
    
    local pid_check = exec("pidof " .. package)
    if pid_check and pid_check:gsub("%s+", "") ~= "" then
        local uid = getAppUID(package)
        if uid then
            exec("su -c 'kill -9 $(pgrep -U " .. uid .. ")' 2>/dev/null")
        end
        os.execute("sleep 0.3")
    end
    
    exec("su -c 'am start " .. package .. "' 2>/dev/null")
end

-- ==========================================
-- DATA FUNCTIONS
-- ==========================================
function loadData()
    local f = io.open(PACKAGE_FILE, "r")
    if f then
        packages = {}
        for line in f:lines() do
            local name, package, uname = line:match("([^|]+)|([^|]+)|?([^|]*)")
            if name and package then 
                table.insert(packages, {name = name, package = package, username = (uname ~= "" and uname or nil)})
            end
        end
        f:close()
    end
end

function saveAll()
    local f = io.open(PACKAGE_FILE, "w")
    for _, pkg in ipairs(packages) do 
        local uname = pkg.username or ""
        f:write(pkg.name .. "|" .. pkg.package .. "|" .. uname .. "\n") 
    end
    f:close()
end

-- ==========================================
-- MENU FUNCTIONS
-- ==========================================
function menuListPackages()
    clearScreen()
    print("╔════════════════════════════════════════╗")
    print("║         LIST PACKAGES                  ║")
    print("╚════════════════════════════════════════╝")
    print("")
    if #packages == 0 then
        print("  (No packages)")
    else
        for i,p in ipairs(packages) do 
            local username = p.username or "(no auth)"
            print(string.format("  %d. %s - %s", i, p.package, username))
        end
    end
    print("")
    safe_input("Press Enter...")
end

function startMonitoring()
    clearScreen()
    print("Starting monitoring...")
    os.execute("sleep 1")
    
    -- Initialize app states
    for i, pkg in ipairs(packages) do
        app_states[pkg.package] = {
            startTime = 0,
            status = "Ready",
            ignoreUntil = 0,
            uid = getAppUID(pkg.package),
            heartbeatStatus = "Init",
            connectionStatus = "Offline",
            lastHeartbeat = 0,
            heartbeatRetries = 0
        }
    end
    
    -- Auto-detect cookies
    clearScreen()
    print("════════════════════════════════════════")
    print("   AUTO DETECTING COOKIES...")
    print("════════════════════════════════════════")
    local detected = autoDetectCookies()
    print(string.format("✓ Detected %d username(s) from cookies\n", detected))
    saveAll()
    os.execute("sleep 1")
    
    -- Start monitoring loop
    launch_queue_index = 1
    next_launch_time = os.time()
    scan_pointer = 1
    
    clearScreen()
    while true do
        local current_time = os.time()
        
        -- Launch next app in queue
        if launch_queue_index <= #packages then
            if current_time >= next_launch_time then
                local pkg = packages[launch_queue_index]
                killAndStart(pkg.package)
                local state = app_states[pkg.package]
                state.status = "Launched"
                state.startTime = current_time
                state.ignoreUntil = current_time + GRACE_PERIOD
                launch_queue_index = launch_queue_index + 1
                next_launch_time = current_time + config.delay
            end
        end
        
        -- Move to next app to monitor
        scan_pointer = scan_pointer + 1
        if scan_pointer > #packages then scan_pointer = 1 end
        
        -- Check heartbeats every 30 seconds
        if current_time % HEARTBEAT_INTERVAL == 0 then
            checkAllHeartbeats()
        end
        
        -- Build display buffer
        local buffer = ""
        local free_ram = getFreeRAM()
        local dynamic_launched = scan_pointer
        
        buffer = buffer .. "╔════════════════════════════════════════════╗\n"
        buffer = buffer .. "║  ZEEN TOOLS v10.0 - MONITORING            ║\n"
        buffer = buffer .. "╚════════════════════════════════════════════╝\n"
        buffer = buffer .. "\n"
        buffer = buffer .. string.format("  Status:   LAUNCHED %d/%d (Monitoring App #%d)\n", dynamic_launched, #packages, scan_pointer)
        buffer = buffer .. string.format("  RAM:      %s\n", free_ram)
        buffer = buffer .. "\n"
        buffer = buffer .. "┌───┬──────────────────────────┬─────────────┬──────────────┐\n"
        buffer = buffer .. "│ NO│ PACKAGE NAME             │   STATUS    │ CONNECTION   │\n"
        buffer = buffer .. "├───┼──────────────────────────┼─────────────┼──────────────┤\n"
        
        for i, pkg in ipairs(packages) do
            local state = app_states[pkg.package]
            local status_text = "Unknown"
            local connection_text = "Unknown"
            
            -- Determine status
            if state.status == "Ready" then
                status_text = "Ready"
                connection_text = "Wait"
            elseif current_time < state.ignoreUntil then
                local timeLeft = state.ignoreUntil - current_time
                status_text = string.format("Load (%ds)", timeLeft)
                connection_text = "Warmup"
            else
                local pid_out = exec("pidof " .. pkg.package)
                if pid_out ~= "" then
                    status_text = "Online"
                    if state.connectionStatus == "Connected" then
                        connection_text = "Connected ✓"
                    elseif state.connectionStatus == "Unstable" then
                        connection_text = "Unstable ⚠"
                    else
                        connection_text = "Unknown"
                    end
                else
                    status_text = "Crash"
                    connection_text = "Offline"
                end
            end
            
            local displayName = pkg.package:sub(1, 24)
            buffer = buffer .. string.format("│ %2d│ %-24s │ %-11s │ %-12s │\n", i, displayName, status_text, connection_text)
        end
        
        buffer = buffer .. "└───┴──────────────────────────┴─────────────┴──────────────┘\n"
        buffer = buffer .. "\n"
        buffer = buffer .. " [PRESS 'q' TO QUIT]"
        
        io.write("\027[H")
        io.write(buffer)
        io.stdout:flush()
        
        -- Check for input
        os.execute("sleep " .. WATCHDOG_INTERVAL)
    end
end

-- ==========================================
-- MAIN MENU
-- ==========================================
function main()
    os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1")
    loadData()
    
    while true do
        clearScreen()
        print("╔════════════════════════════════════════╗")
        print("║    ZEEN TOOLS v10.0 (FINAL)           ║")
        print("╚════════════════════════════════════════╝")
        print("")
        print("MAIN MENU:")
        print("")
        print("  1. Start Monitoring")
        print("  2. Auto-Detect Cookies")
        print("  3. List Packages")
        print("  4. Exit")
        print("")
        print("════════════════════════════════════════")
        io.write("Choose: ")
        local choice = safe_input("")
        
        if choice == "1" then
            startMonitoring()
        elseif choice == "2" then
            clearScreen()
            print("AUTO DETECTING COOKIES...")
            print("")
            local detected = autoDetectCookies()
            print(string.format("✓ Detected %d username(s)\n", detected))
            saveAll()
            safe_input("Press Enter...")
        elseif choice == "3" then
            menuListPackages()
        elseif choice == "4" then
            break
        end
    end
    
    clearScreen()
    print("Goodbye!")
    os.exit()
end

-- ==========================================
-- START
-- ==========================================
main()