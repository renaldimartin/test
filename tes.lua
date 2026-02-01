#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- ZEEN TOOLS v11.3 (LAUNCH ENGINE FIX)
-- ==========================================
-- [FIX] SMART LAUNCH: Deteksi Main Activity otomatis (Resolve Activity)
-- [FIX] MANAGE: Menu hapus package (All/Specific)
-- [FIX] SYNC: Monitoring sinkron dengan proses launch
-- ==========================================

-- 1. AUTO ROOT LOGIC
local function check_and_escalate()
    local handle = io.popen("id -u")
    local uid = handle:read("*a")
    handle:close()
    if uid and not uid:match("0") then
        print("\027[1;33m[!] Meminta akses Root (tsu)...\027[0m")
        local script_path = arg[0]
        local cmd = string.format("tsu -c 'lua53 \"%s\"'", script_path)
        os.execute(cmd)
        os.exit()
    end
end
check_and_escalate()

-- ==========================================
-- CONFIG & PATHS
-- ==========================================
os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1") 
io.stdout:setvbuf("no")

local ROOT_DIR = "/sdcard/Zeen"
local CONFIG_DIR = ROOT_DIR .. "/Config"
local COOKIE_DIR = ROOT_DIR .. "/Cookies"

os.execute("mkdir -p " .. CONFIG_DIR)
os.execute("mkdir -p " .. COOKIE_DIR)

local PACKAGE_FILE = CONFIG_DIR .. "/packages.txt"
local CONFIG_FILE = CONFIG_DIR .. "/settings.txt"
local WEBHOOK_FILE = CONFIG_DIR .. "/webhook.txt"
local VIP_FILE = CONFIG_DIR .. "/vip_link.txt"

-- GLOBAL VARS
local ZEEN_VERSION = "v11.3 (LAUNCH ENGINE)"
local WATCHDOG_INTERVAL = 1   
local GRACE_PERIOD = 90       
local QUEUE_DELAY = 30        
local STABLE_TIME = 60        
local HEARTBEAT_INTERVAL = 30      
local HEARTBEAT_TIMEOUT = 5        
local HEARTBEAT_MAX_RETRIES = 2    
local HEARTBEAT_ENDPOINTS = { "https://www.roblox.com", "https://www.roblox.com/home" }         

local STATUS_BAR_HEIGHT = 60
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 

local packages = {}
local app_states = {} 
local global_last_restart = 0 
local config = { delay = 15, low_gfx = true, auto_mute = true } 
local webhook_conf = { url = "", interval = 300 } 
local vip_link = ""
local device_name = "Android Device"

local launched_count = 0        
local launch_queue_index = 1    
local next_launch_time = 0      

-- ==========================================
-- HELPER FUNCTIONS
-- ==========================================
function safe_print(str)
    str = tostring(str or "")
    io.write(str .. "\027[K\n") 
    io.stdout:flush()
end
print = safe_print

function trim(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end

function safe_input(prompt)
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

-- [IMPORTANT] EXEC wrapper
function exec(cmd)
    local handle = io.popen(cmd .. ' 2>/dev/null')
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result or ""
end

function getDeviceName()
    local model = exec("getprop ro.product.model"):gsub("\n", "")
    if model == "" then model = "Termux Device" end
    device_name = model
end

function getFreeRAM()
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

function getAppUID(package)
    local cmd = "stat -c %u /data/data/" .. package
    local uid = exec(cmd):gsub("%s+", "")
    if uid and tonumber(uid) then return tonumber(uid) end
    return nil
end

function json_escape(str)
    if not str then return "" end
    str = str:gsub('\\', '\\\\')
    str = str:gsub('"', '\\"')
    str = str:gsub('\n', '\\n')
    str = str:gsub('\r', '\\r')
    return str
end

-- ==========================================
-- DEEPLINK CONVERTER
-- ==========================================
function convert_to_deeplink(url)
    if not url or url == "" then return "" end
    if url:match("^roblox://") then return url end
    
    local placeId = url:match("games/(%d+)")
    local linkCode = url:match("privateServerLinkCode=([%w%-]+)")
    
    if placeId and linkCode then
        return string.format("roblox://experiences/start?placeId=%s&linkCode=%s", placeId, linkCode)
    end
    return url 
end

-- ==========================================
-- CONFIG INJECTOR (GFX & COOKIE)
-- ==========================================
function inject_fast_flags(package)
    if not config.low_gfx then return end
    local settings_dir = "/data/data/" .. package .. "/files/ClientSettings"
    local settings_file = settings_dir .. "/ClientAppSettings.json"
    
    exec("mkdir -p " .. settings_dir)
    local json_content = [[
{
    "DFIntTaskSchedulerTargetFps": 30,
    "FFlagDebugGraphicsDisableDirect3D11": "True",
    "FFlagDebugGraphicsPreferOpenGL": "True",
    "FIntDebugTextureManagerSkipMips": 3,
    "FFlagGameBasicSettingsFramerateCap": "True",
    "DFIntTaskSchedulerLimitTargetFps": 30
}
]]
    local f = io.open(CONFIG_DIR .. "/temp_ff.json", "w")
    f:write(json_content)
    f:close()
    exec("cp " .. CONFIG_DIR .. "/temp_ff.json " .. settings_file)
    
    local uid = getAppUID(package)
    if uid then
        exec("chown " .. uid .. ":" .. uid .. " -R " .. settings_dir)
        exec("chmod 777 " .. settings_dir)
        exec("chmod 666 " .. settings_file)
    end
    os.remove(CONFIG_DIR .. "/temp_ff.json")
end

function fix_cookie_permission(package)
    local cookie_path = nil
    local paths = {
        "/data/data/" .. package .. "/app_webview/Default/Cookies",
        "/data/data/" .. package .. "/app_webview/Cookies",
        "/data/data/" .. package .. "/shared_prefs/Cookies",
        "/data/data/" .. package .. "/databases/Cookies"
    }
    for _, p in ipairs(paths) do
        local f = io.open(p, "r"); if f then f:close(); cookie_path = p; break end
    end
    if cookie_path then
        local uid = getAppUID(package)
        if uid then
            exec("chown " .. uid .. ":" .. uid .. " " .. cookie_path)
            exec("chmod 600 " .. cookie_path) 
        end
    end
end

-- ==========================================
-- [NEW] LAUNCH ENGINE 
-- ==========================================

-- Fungsi untuk mencari Main Activity secara spesifik
function get_main_activity(package)
    -- Menggunakan 'cmd package resolve-activity' untuk mencari pintu masuk utama
    local cmd = string.format("/system/bin/cmd package resolve-activity --brief %s | tail -n 1", package)
    local result = exec(cmd)
    
    -- Hasil biasanya: com.package/com.package.MainActivity
    if result and result:match("/") then
        return result:gsub("%s+", "") -- Hapus spasi/newline
    end
    return nil
end

function killAndStart(package)
    -- 1. Force Stop
    exec("/system/bin/am force-stop " .. package)
    os.execute("sleep 0.5")
    
    -- 2. Pastikan mati (Kill Zombie Process)
    local pid_check = exec("pidof " .. package)
    if pid_check and pid_check:gsub("%s+", "") ~= "" then
        local uid = getAppUID(package)
        if uid then exec("kill -9 -f $(pgrep -U " .. uid .. ")") end
        os.execute("sleep 0.3")
    end
    
    -- 3. Inject Settings
    inject_fast_flags(package)
    fix_cookie_permission(package)
    
    -- 4. LAUNCHING LOGIC
    if vip_link and vip_link ~= "" then
        -- Jika ada VIP Link, gunakan Deeplink
        local deeplink = convert_to_deeplink(vip_link)
        local cmd = string.format("/system/bin/am start -W -a android.intent.action.VIEW -d \"%s\" -p %s", deeplink, package)
        exec(cmd)
    else
        -- Jika tidak ada link, cari Activity Utama
        local main_activity = get_main_activity(package)
        
        if main_activity then
            -- METODE 1: Start via Activity (Paling Kuat)
            -- -W artinya Wait for launch (memastikan terload)
            local cmd = string.format("/system/bin/am start -W -n %s", main_activity)
            exec(cmd)
        else
            -- METODE 2: Fallback ke Monkey (Jika activity tidak ketemu)
            local cmd = string.format("/system/bin/monkey -p %s -c android.intent.category.LAUNCHER 1", package)
            exec(cmd)
        end
    end
end

-- ==========================================
-- UI & CLONER UTILS
-- ==========================================
function getGridPositions(numApps)
    local usable_height = DISPLAY_HEIGHT - STATUS_BAR_HEIGHT
    local h_slot = math.floor(usable_height / 3)
    local active_width_limit = math.floor(DISPLAY_WIDTH * (2 / 3))
    local w_slot = math.floor(active_width_limit / 2)
    local y1, y2, y3 = STATUS_BAR_HEIGHT, STATUS_BAR_HEIGHT + h_slot, STATUS_BAR_HEIGHT + (h_slot*2)
    local b1, b2, b3 = y1 + h_slot, y2 + h_slot, DISPLAY_HEIGHT 
    return {
        {name="R1 Left",  left=0, top=y1, right=w_slot, bottom=b1},
        {name="R1 Right", left=w_slot, top=y1, right=active_width_limit, bottom=b1},
        {name="R2 Left",  left=0, top=y2, right=w_slot, bottom=b2},
        {name="R2 Right", left=w_slot, top=y2, right=active_width_limit, bottom=b2},
        {name="R3 Left",  left=0, top=y3, right=w_slot, bottom=b3},
        {name="R3 Right", left=w_slot, top=y3, right=active_width_limit, bottom=b3},
    }
end

function modifyUGClonerPrefs(package, position, numApps)
    local grid_positions = getGridPositions(numApps)
    local pos_index = ((position - 1) % #grid_positions) + 1
    local pos = grid_positions[pos_index]
    if not pos then return false end
    
    local cloneId = package:match("clien([%w]+)$") or "z1"
    local findCmd = string.format("ls /data/data/%s/shared_prefs/*.xml 2>/dev/null | grep -i pref", package)
    local foundFiles = exec(findCmd)
    local prefFile = foundFiles:match("([^\n]+_preferences%.xml)") or foundFiles:match("([^\n]+)") 
    
    if not prefFile or prefFile == "" then
        prefFile = string.format("/data/data/%s/shared_prefs/com.roblox.clien%s_preferences.xml", package, cloneId)
    end
    
    local commands = {
        string.format("sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_left\\\" value=\\\"%d\\\"/' '%s'", pos.left, prefFile),
        string.format("sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_top\\\" value=\\\"%d\\\"/' '%s'", pos.top, prefFile),
        string.format("sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_right\\\" value=\\\"%d\\\"/' '%s'", pos.right, prefFile),
        string.format("sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_bottom\\\" value=\\\"%d\\\"/' '%s'", pos.bottom, prefFile),
    }
    for _, cmd in ipairs(commands) do exec(cmd) end
    local uid = getAppUID(package)
    if uid then exec("chown " .. uid .. ":" .. uid .. " " .. prefFile) end
    return true
end

-- ==========================================
-- MONITORING
-- ==========================================
function checkAppHeartbeat(package)
    local endpoint = HEARTBEAT_ENDPOINTS[math.random(1, #HEARTBEAT_ENDPOINTS)]
    local curl_cmd = string.format("timeout %d curl -s -m %d -w '%%{http_code}' '%s' 2>/dev/null | tail -c 3", HEARTBEAT_TIMEOUT, HEARTBEAT_TIMEOUT, endpoint)
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
    
    if checkAppHeartbeat(package) then
        state.heartbeatStatus = "ALIVE"
        state.connectionStatus = "Connected"
        state.lastHeartbeat = os.time(); state.heartbeatRetries = 0
        return true
    else
        state.heartbeatRetries = (state.heartbeatRetries or 0) + 1
        if state.heartbeatRetries >= HEARTBEAT_MAX_RETRIES then
            state.heartbeatStatus = "DEAD"; state.connectionStatus = "Disconnected"
            return false
        else
            state.heartbeatStatus = "RETRYING"; state.connectionStatus = "Unstable"
            return nil 
        end
    end
end

function getProcessInfo(package)
    local pid_out = exec("pidof " .. package)
    local pid = pid_out:match("(%d+)")
    local rss = 0
    if pid then
        local rss_out = exec("ps -p " .. pid .. " -o rss | tail -n 1")
        rss = tonumber(rss_out:match("(%d+)")) or 0
    end
    return pid, "S", rss 
end

function sendDiscordWebhook()
    if webhook_conf.url == "" then return end
    local total_online = 0; local total_offline = 0; local fields = ""
    local time_now = os.date("%H:%M")
    
    for i = 1, launched_count do 
        local pkg = packages[i]
        local state = app_states[pkg.package]
        local is_online = false; local rss_kb = 0; local uptime = "0m"
        local pid, _, r = getProcessInfo(pkg.package)
        if pid then 
            is_online = true; total_online = total_online + 1
            if r then rss_kb = math.floor(r/1024) end
            uptime = string.format("%dm", math.floor((os.time() - state.startTime)/60))
        else total_offline = total_offline + 1 end
        
        local status_icon = is_online and "🟢" or "🔴"
        local safe_user = pkg.username and json_escape(pkg.username) or ""
        local user_disp = safe_user ~= "" and "**||"..safe_user.."||**" or "Unknown"
        local val = is_online and string.format("`⏱️%s|💾%dMB`", uptime, rss_kb) or "`🔻OFFLINE`"
        fields = fields .. string.format('{"name": "%s %s", "value": "%s", "inline": false},', status_icon, user_disp, val)
    end
    
    if #fields > 0 then fields = fields:sub(1, -2) end
    local color = (total_offline > 0) and 16711680 or 65280
    local payload = string.format([[ {"embeds": [{"title": "ZEEN STATUS", "description": "Last: **%s**\nOnline: %d | Offline: %d", "color": %d, "fields": [%s]}]} ]], time_now, total_online, total_offline, color, fields)
    payload = payload:gsub("\n", " ")
    exec(string.format("curl -H \"Content-Type: application/json\" -X POST -d '%s' %s >/dev/null 2>&1 &", payload, webhook_conf.url))
end

-- ==========================================
-- MAIN MONITORING
-- ==========================================
function startMonitoring()
    for i, pkg in ipairs(packages) do
        app_states[pkg.package] = { 
            startTime = 0, status = "Ready", ignoreUntil = 0,
            heartbeatStatus = "Init", connectionStatus = "Offline", heartbeatRetries = 0
        }
        exec("/system/bin/am force-stop " .. pkg.package) 
    end
    if config.auto_mute then exec("media volume --set 0") end 

    launched_count = 0
    launch_queue_index = 1
    next_launch_time = os.time()
    local initial_webhook = false; local next_webhook = 0
    
    clearScreen()
    while true do
        local current_time = os.time()
        
        -- LAUNCHER
        if launch_queue_index <= #packages then
            if current_time >= next_launch_time then
                local pkg = packages[launch_queue_index]
                modifyUGClonerPrefs(pkg.package, launch_queue_index, #packages)
                killAndStart(pkg.package)
                app_states[pkg.package].status = "Launched"
                app_states[pkg.package].startTime = current_time
                app_states[pkg.package].ignoreUntil = current_time + GRACE_PERIOD
                launched_count = launched_count + 1
                launch_queue_index = launch_queue_index + 1
                next_launch_time = current_time + config.delay
            end
        end
        
        -- HEARTBEAT
        if current_time % HEARTBEAT_INTERVAL == 0 then
            for i = 1, launched_count do updateAppHeartbeat(packages[i].package) end
        end
        
        -- DISPLAY
        local buffer = ""
        buffer = buffer .. "\027[1;36m╔════ ZEEN TOOLS "..ZEEN_VERSION.." ════╗\027[0m\r\n"
        buffer = buffer .. string.format("  LAUNCHED: %d/%d  |  RAM: %s\r\n", launched_count, #packages, getFreeRAM())
        buffer = buffer .. "\027[1;33m┌───┬──────────────────┬───────────┬──────────────┐\027[0m\r\n"
        buffer = buffer .. "\027[1;33m│ NO│ PACKAGE NAME     │ STATUS    │ CONNECTION   │\027[0m\r\n"
        buffer = buffer .. "\027[1;33m├───┼──────────────────┼───────────┼──────────────┤\027[0m\r\n"
        
        for i = 1, #packages do
            local pkg = packages[i]
            local state = app_states[pkg.package]
            local status_text = "\027[1;30mWaiting...\027[0m"
            local conn_text = " - "
            
            if i <= launched_count then
                if current_time < state.ignoreUntil then
                    local left = state.ignoreUntil - current_time
                    status_text = string.format("\027[1;33mLoad(%ds)\027[0m", left)
                    conn_text = "\027[1;33mWarmup\027[0m"
                else
                    local pid = exec("pidof " .. pkg.package)
                    if pid ~= "" then
                        status_text = "\027[1;32;1mOnline\027[0m"
                        if state.connectionStatus == "Connected" then conn_text = "\027[1;32m✓Connect\027[0m"
                        elseif state.connectionStatus == "Disconnected" then conn_text = "\027[1;31m✗Discon\027[0m"
                        else conn_text = "\027[1;33m⚠Check\027[0m" end
                    else
                        status_text = "\027[1;31mCRASH\027[0m"
                        conn_text = "\027[1;31m✗Offline\027[0m"
                    end
                end
                
                if state.connectionStatus == "Disconnected" or status_text:match("CRASH") then
                    if current_time - global_last_restart >= QUEUE_DELAY then
                        killAndStart(pkg.package)
                        state.startTime = current_time; state.ignoreUntil = current_time + GRACE_PERIOD
                        global_last_restart = current_time
                        if webhook_conf.url ~= "" then sendDiscordWebhook() end
                    end
                end
            end
            local dname = pkg.package
            if pkg.username then dname = pkg.package.." ("..pkg.username:sub(1,3)..")" end
            buffer = buffer .. string.format("│ %2d│ %-17s│ %-18s│ %-22s│\r\n", i, dname:sub(1,16), status_text, conn_text)
        end
        buffer = buffer .. "\027[1;33m└───┴──────────────────┴───────────┴──────────────┘\027[0m\r\n"
        buffer = buffer .. " [Q] QUIT"
        
        if launched_count == #packages and not initial_webhook and webhook_conf.url ~= "" then
            sendDiscordWebhook(); initial_webhook = true; next_webhook = current_time + webhook_conf.interval
        elseif initial_webhook and webhook_conf.url ~= "" and current_time >= next_webhook then
            sendDiscordWebhook(); next_webhook = current_time + webhook_conf.interval
        end
        
        io.write("\027[H" .. buffer); io.stdout:flush()
        local cmd = "read -t " .. WATCHDOG_INTERVAL .. " input 2>/dev/null; echo $input"
        local handle = io.popen(cmd); local output = handle:read("*a"); handle:close()
        if output and output:match("^[qQ]") then break end
    end
end

-- ==========================================
-- MENU FUNCTIONS
-- ==========================================
function menuDeletePackages()
    while true do
        clearScreen()
        print("══ MANAGE PACKAGES ══")
        if #packages == 0 then print("  (Empty)")
        else
            for i, p in ipairs(packages) do
                local u = p.username or "-"
                print(string.format("  [%d] %s (%s)", i, p.package, u))
            end
        end
        print("═════════════════════")
        print("Type 'all' to delete ALL, numbers e.g '1,3', or 'back'")
        io.write("\n>> ")
        local input = safe_input("")
        
        if input == 'back' or input == '' then break
        elseif input == 'all' then
            io.write("Confirm? (y/n): ")
            if safe_input("") == "y" then packages = {}; saveAll(); print("✓ Deleted."); os.execute("sleep 1") end
        else
            local indices = {}
            for n in input:gmatch("%d+") do table.insert(indices, tonumber(n)) end
            table.sort(indices, function(a,b) return a > b end)
            for _, idx in ipairs(indices) do
                if packages[idx] then table.remove(packages, idx) end
            end
            if #indices > 0 then saveAll(); print("✓ Deleted."); os.execute("sleep 1") end
        end
    end
end

function autoDetectRoblox()
    clearScreen()
    print("Scanning packages via Root...")
    local candidates = {}; local seen = {}
    
    local function is_added(pkg)
        for _, p in ipairs(packages) do if p.package == pkg then return true end end
        return false
    end

    local raw = exec("pm list packages")
    for line in raw:gmatch("[^\r\n]+") do
        if line:lower():find("roblox") then
            local p = line:gsub("package:", ""):gsub("%s+", "")
            if not seen[p] then table.insert(candidates, p); seen[p]=true end
        end
    end
    if #candidates==0 then
        raw = exec("ls /data/data | grep roblox") 
        for line in raw:gmatch("[^\r\n]+") do
            local p = line:gsub("%s+", "")
            if not seen[p] then table.insert(candidates, p); seen[p]=true end
        end
    end
    
    if #candidates==0 then print("No Roblox found."); safe_input("Enter..."); return end
    
    print("\nFound:")
    for i,p in ipairs(candidates) do 
        local status = is_added(p) and "\027[1;32m[ADDED]\027[0m" or ""
        print(string.format("[%d] %s %s", i, p, status))
    end
    
    io.write("\nSelect (e.g., 1,3 or 'all'): "); local c = safe_input("")
    local cnt = 0
    local function add(p) if not is_added(p) then table.insert(packages, {name=p, package=p}); cnt=cnt+1 end end

    if c=="all" then for _,p in ipairs(candidates) do add(p) end
    else for n in c:gmatch("%d+") do if candidates[tonumber(n)] then add(candidates[tonumber(n)]) end end end
    
    if cnt > 0 then saveAll() end
    safe_input("\nDone. Enter...")
end

function menuSettings()
    while true do
        clearScreen()
        print("══ SETTINGS ══")
        print("1. Delay: " .. config.delay .. "s")
        print("2. VIP Link: " .. (vip_link == "" and "None" or "Set"))
        print("3. Webhook")
        print("4. Low GFX: " .. (config.low_gfx and "ON" or "OFF"))
        print("5. Auto Mute: " .. (config.auto_mute and "ON" or "OFF"))
        print("6. Back")
        io.write(">> "); local c = safe_input("")
        if c=="1" then io.write("Delay: "); config.delay = tonumber(safe_input("")) or 15
        elseif c=="2" then io.write("Link: "); vip_link = safe_input("")
        elseif c=="3" then io.write("URL: "); webhook_conf.url = safe_input("")
        elseif c=="4" then config.low_gfx = not config.low_gfx
        elseif c=="5" then config.auto_mute = not config.auto_mute
        elseif c=="6" then break end
        saveAll()
    end
end

function loadData()
    local f = io.open(PACKAGE_FILE, "r")
    if f then
        packages = {}
        for line in f:lines() do
            local n, p, u = line:match("([^|]+)|([^|]+)|?([^|]*)")
            if n then table.insert(packages, {name=n, package=p, username=(u~="" and u or nil)}) end
        end
        f:close()
    end
    f = io.open(CONFIG_FILE, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("(%w+)=(.+)")
            if k then 
                if v == "true" then config[k] = true
                elseif v == "false" then config[k] = false
                else config[k] = tonumber(v) end
            end
        end
        f:close()
    end
    f = io.open(VIP_FILE, "r"); if f then vip_link=f:read("*a"):gsub("\n",""); f:close() end
    f = io.open(WEBHOOK_FILE, "r"); if f then webhook_conf.url=f:read("*l") or ""; f:close() end
end

function saveAll()
    local f = io.open(CONFIG_FILE, "w"); for k,v in pairs(config) do f:write(k.."="..tostring(v).."\n") end; f:close()
    f = io.open(PACKAGE_FILE, "w"); for _,p in ipairs(packages) do f:write(p.name.."|"..p.package.."|"..(p.username or "").."\n") end; f:close()
    f = io.open(VIP_FILE, "w"); f:write(vip_link); f:close()
    f = io.open(WEBHOOK_FILE, "w"); f:write(webhook_conf.url); f:close()
end

function main()
    loadData()
    while true do
        clearScreen()
        print("╔════ ZEEN TOOLS "..ZEEN_VERSION.." ════╗")
        print("║ 1. Start Monitor (Sync Mode)   ║")
        print("║ 2. Detect Apps                 ║")
        print("║ 3. Settings (Mute/GFX/Link)    ║")
        print("║ 4. Manage Packages (Delete)    ║")
        print("║ 5. Exit                        ║")
        print("╚════════════════════════════════╝")
        io.write(">> ")
        local c = safe_input("")
        if c == "1" then startMonitoring()
        elseif c == "2" then autoDetectRoblox()
        elseif c == "3" then menuSettings()
        elseif c == "4" then menuDeletePackages()
        elseif c == "5" then break end
    end
end

main()

