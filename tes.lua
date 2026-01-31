#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v10.0 (EXECUTION FIX)
-- ==========================================
-- Update v10.0:
-- [+] FIX EXEC: Menggunakan direct su -c (Bypass Permission Error)
-- [+] FIX RAM: Membaca /proc/meminfo langsung (Native Lua)
-- [+] FIX KILL: Force stop lebih agresif
-- [+] STABLE UI: Dashboard & Input tetap aman
-- ==========================================

-- 1. SETUP TERMINAL
os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1") 
io.stdout:setvbuf("no")

-- ==========================================
-- KONFIGURASI PATH
-- ==========================================
local ROOT_DIR = "/sdcard/Zeen"
local CONFIG_DIR = ROOT_DIR .. "/Config"
local COOKIE_DIR = ROOT_DIR .. "/Cookies"

os.execute("mkdir -p " .. CONFIG_DIR)
os.execute("mkdir -p " .. COOKIE_DIR)

local PACKAGE_FILE = CONFIG_DIR .. "/packages.txt"
local CONFIG_FILE = CONFIG_DIR .. "/settings.txt"
local WEBHOOK_FILE = CONFIG_DIR .. "/webhook.txt"
local VIP_FILE = CONFIG_DIR .. "/vip_link.txt"

-- ==========================================
-- KONFIGURASI SYSTEM
-- ==========================================
local ZEEN_VERSION = "v10.0"
local WATCHDOG_INTERVAL = 2   
local GRACE_PERIOD = 90       
local QUEUE_DELAY = 30        
local STABLE_TIME = 60        
local TRAFFIC_THRESHOLD = 100 
local MAX_STRIKES = 5         

local STATUS_BAR_HEIGHT = 60
local DEFAULT_DELAY = 10
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 

local packages = {}
local app_states = {} 
local global_last_restart = 0 
local config = { delay = DEFAULT_DELAY }
local webhook_conf = { url = "", interval = 300 } 
local vip_link = ""
local device_name = "Android Device"

local launch_queue_index = 1    
local next_launch_time = 0 
local scan_pointer = 1 

-- ==========================================
-- FUNGSI UI & HELPER
-- ==========================================

function safe_print(str)
    str = tostring(str or "")
    io.write(str .. "\027[K\n") 
    io.stdout:flush()
end
print = safe_print

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

-- [CRITICAL FIX] FUNGSI EKSEKUSI LANGSUNG
-- Tidak lagi membuat file temp, langsung tembak ke su
function exec(cmd)
    -- Escape double quotes untuk keamanan di dalam string su -c "..."
    local safe_cmd = cmd:gsub('"', '\\"')
    local handle = io.popen('su -c "' .. safe_cmd .. '" 2>/dev/null')
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result or ""
end

function exec_root_mm(cmd)
    local safe_cmd = cmd:gsub('"', '\\"')
    local handle = io.popen('su -mm -c "' .. safe_cmd .. '" 2>/dev/null')
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

-- [CRITICAL FIX] BACA RAM LANGSUNG
function getFreeRAM()
    -- Metode 1: Baca file langsung via Lua (Paling Stabil)
    local f = io.open("/proc/meminfo", "r")
    if f then
        local content = f:read("*a")
        f:close()
        -- Cari 'MemAvailable:    123456 kB'
        local mem_kb = tonumber(content:match("MemAvailable:%s+(%d+)"))
        if mem_kb and mem_kb > 0 then
            local gb = mem_kb / 1024 / 1024
            return string.format("%.2f GB", gb)
        end
    end

    -- Metode 2: Fallback ke command line jika file tidak terbaca
    local output = exec("cat /proc/meminfo | grep MemAvailable")
    local kb = tonumber(output:match("(%d+)"))
    if kb and kb > 0 then
        local gb = kb / 1024 / 1024
        return string.format("%.2f GB", gb)
    end
    return "Unknown"
end

-- ==========================================
-- TRAFFIC MONITORING
-- ==========================================
function getAppUID(package)
    local cmd = "stat -c %u /data/data/" .. package
    local uid = exec(cmd):gsub("%s+", "")
    if uid and tonumber(uid) then return tonumber(uid) end
    return nil
end

function getNetworkBytes(uid)
    if not uid then return 0 end
    -- Baca langsung file jika bisa, fallback ke exec
    local f = io.open("/proc/uid_stat/" .. uid .. "/tcp_rcv", "r")
    if f then
        local bytes = f:read("*n")
        f:close()
        return bytes or 0
    end
    
    local cmd = "cat /proc/uid_stat/" .. uid .. "/tcp_rcv"
    local bytes = exec(cmd):gsub("%s+", "")
    return tonumber(bytes) or 0
end

-- ==========================================
-- COOKIE MANAGER
-- ==========================================
local function get_json_val(json, key)
    if not json then return nil end
    local val = json:match('"' .. key .. '":%s-["%d]*(.-)["%d]*[,}]')
    if val then return val:gsub('"', '') else return nil end
end

function fetch_roblox_identity(cookie)
    if not cookie or #cookie < 20 then return nil, nil end
    local url = "https://users.roblox.com/v1/users/authenticated"
    local safe_cookie = cookie:gsub("'", ""):gsub("[\r\n]", "")
    local cmd = string.format("curl -s -L --max-time 10 -A 'Mozilla/5.0 (Android 10; Mobile)' -H 'Cookie: .ROBLOSECURITY=%s' \"%s\"", safe_cookie, url)
    
    -- Curl dijalankan biasa (user) atau root jika perlu
    local handle = io.popen(cmd)
    local json = handle:read("*a")
    handle:close()
    
    local id = get_json_val(json, "id")
    local name = get_json_val(json, "name")
    return name, id
end

function extract_package_cookie(package)
    local find_cmd = "find /data/data/" .. package .. " -name 'Cookies' 2>/dev/null | head -n 1"
    local db_path = exec_root_mm(find_cmd):gsub("%s+", "")
    if db_path == "" then return nil end
    local temp_db = CONFIG_DIR .. "/temp_cookie.db"
    exec_root_mm("cp \"" .. db_path .. "\" " .. temp_db)
    exec_root_mm("chmod 777 " .. temp_db)
    local query = "SELECT value FROM cookies WHERE name = '.ROBLOSECURITY';"
    local sqlite_cmd = "sqlite3 " .. temp_db .. " \"" .. query .. "\""
    local handle = io.popen("su -c '" .. sqlite_cmd .. "'")
    local raw_cookie = handle:read("*a")
    handle:close()
    os.remove(temp_db)
    if raw_cookie and #raw_cookie > 20 then return raw_cookie:gsub("[\r\n]", "") end
    return nil
end

function inject_cookie_to_app(package, cookie_value)
    local find_cmd = "find /data/data/" .. package .. " -name 'Cookies' 2>/dev/null | head -n 1"
    local db_path = exec_root_mm(find_cmd):gsub("%s+", "")
    if db_path == "" then return false, "DB Not Found" end
    local update_sql = string.format("UPDATE cookies SET value='%s' WHERE name='.ROBLOSECURITY';", cookie_value)
    local cmd = string.format("sqlite3 \"%s\" \"%s\"", db_path, update_sql)
    exec_root_mm(cmd)
    return true, "Injected"
end

function menuCookieManager()
    while true do
        clearScreen()
        print("══ COOKIE MANAGER ══")
        print("1. Scan Identity")
        print("2. Export Cookies")
        print("3. Import Cookies")
        print("4. Kembali")
        io.write("Pilih: ")
        local c = safe_input("")
        if c == "1" then
            print("\n[!] Scanning Identity...")
            for i, pkg in ipairs(packages) do
                io.write(string.format(" -> %s... ", pkg.name))
                io.stdout:flush()
                local cookie = extract_package_cookie(pkg.package)
                if cookie then
                    local username, id = fetch_roblox_identity(cookie)
                    if username then
                        pkg.username = username
                        print("\027[1;32mFOUND: " .. username .. "\027[0m")
                    else
                        print("\027[1;31mINVALID\027[0m")
                    end
                else
                    print("\027[1;30mNO COOKIE\027[0m")
                end
            end
            saveAll() 
            safe_input("\n[Enter] Selesai.")
        elseif c == "2" then
            print("\n[!] Exporting...")
            local count = 0
            for i, pkg in ipairs(packages) do
                local cookie = extract_package_cookie(pkg.package)
                if cookie then
                    local uname = pkg.username or "Unknown"
                    local filename = string.format("%s/%s_%s.txt", COOKIE_DIR, pkg.name:gsub(" ", "_"), uname)
                    local f = io.open(filename, "w")
                    if f then f:write(cookie); f:close(); print(" + Saved: " .. filename); count = count + 1 end
                end
            end
            safe_input(string.format("\n[Enter] %d exported.", count))
        elseif c == "4" then break end
    end
end

-- ==========================================
-- LAYOUT & CLONER
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
        {name="Ex 1", left=0, top=y1, right=w_slot, bottom=b1},
        {name="Ex 2", left=w_slot, top=y1, right=active_width_limit, bottom=b1},
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
    local prefFile = foundFiles:match("([^\n]+_preferences%.xml)") or foundFiles:match("([^\n]+)") or string.format("/data/data/%s/shared_prefs/com.roblox.clien%s_preferences.xml", package, cloneId)
    local commands = {
        string.format("sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_left\\\" value=\\\"%d\\\"/' '%s'", pos.left, prefFile),
        string.format("sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_top\\\" value=\\\"%d\\\"/' '%s'", pos.top, prefFile),
        string.format("sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_right\\\" value=\\\"%d\\\"/' '%s'", pos.right, prefFile),
        string.format("sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_bottom\\\" value=\\\"%d\\\"/' '%s'", pos.bottom, prefFile),
    }
    for _, cmd in ipairs(commands) do exec(cmd) end
    return true
end

-- ==========================================
-- APP CONTROL
-- ==========================================
function getProcessInfo(package)
    -- Pastikan pidof dijalankan dengan exec baru (su -c)
    local pid_out = exec("pidof " .. package)
    local pid = pid_out:match("(%d+)")
    local rss = 0
    if pid then
        local rss_out = exec("ps -p " .. pid .. " -o rss | tail -n 1")
        rss = tonumber(rss_out:match("(%d+)")) or 0
    end
    return pid, "S", rss 
end

function killAndStart(package)
    -- STEP 1: Force stop dengan root
    exec("su -c 'am force-stop " .. package .. "' 2>/dev/null")
    os.execute("sleep 0.5")
    
    -- STEP 2: Verifikasi dan double-kill jika masih berjalan
    local pid_check = exec("pidof " .. package)
    if pid_check and pid_check:gsub("%s+", "") ~= "" then
        local uid = getAppUID(package)
        if uid then
            exec("su -c 'kill -9 -f $(pgrep -U " .. uid .. ")' 2>/dev/null")
        end
        os.execute("sleep 0.3")
    end
    
    -- STEP 3: Launch app
    if vip_link and vip_link ~= "" and vip_link:match("roblox.com") then
        local cmd = string.format("su -c 'am start -a android.intent.action.VIEW -d \"%s\" -p %s' 2>/dev/null", vip_link, package)
        exec(cmd)
    else
        exec("su -c 'am start " .. package .. "' 2>/dev/null")
    end
end

-- ==========================================
-- WEBHOOK
-- ==========================================
function sendDiscordWebhook()
    if webhook_conf.url == "" then return end
    local total_online = 0
    local total_offline = 0
    local fields = ""
    local time_now = os.date("%H:%M %d-%b-%Y")
    for _, pkg in ipairs(packages) do
        local state = app_states[pkg.package]
        local is_online = false
        local rss_kb = 0
        local uptime = "0m"
        if state.status == "Ready" then
            total_offline = total_offline + 1
        else
            local is_launching = (os.time() < state.ignoreUntil)
            local pid = nil
            if not is_launching then pid, _, rss_kb = getProcessInfo(pkg.package) end
            if is_launching or pid then
                is_online = true
                total_online = total_online + 1
                if rss_kb then 
                    local mb = math.floor(rss_kb/1024)
                    if mb > 0 then rss_kb = mb else rss_kb = 0 end
                end
                local diff = os.time() - state.startTime
                uptime = string.format("%dm", math.floor(diff/60))
            else
                total_offline = total_offline + 1
            end
        end
        local status_icon = is_online and "🟢" or "🔴"
        local ram_val = (is_online and rss_kb) and string.format("%dMB", rss_kb) or "0MB"
        local uname_display = pkg.username and string.format("(%s)", pkg.username) or ""
        local field_val = string.format("`⏱️ %s | 💾 %s`", uptime, ram_val)
        if not is_online then field_val = "`🔻 OFFLINE`" end
        if state.status == "Ready" then field_val = "`⏳ QUEUE`" end
        fields = fields .. string.format('{"name": "%s %s ||%s||", "value": "%s", "inline": false},', status_icon, pkg.name, uname_display, field_val)
    end
    fields = fields:sub(1, -2)
    local color = 65280 
    if total_offline > 0 then color = 16711680 end 
    local json_payload = string.format([[ {"content": null, "embeds": [ { "title": "ZEEN TOOLS | MONITOR STATUS", "description": "Last Update: **%s**\nDevice: **%s**\n\n**Status:**\n🟢 Online: %d\n🔴 Offline: %d\n🤖 Total: %d", "color": %d, "fields": [%s], "footer": { "text": "ZEEN TOOLS | %s" } } ] } ]], time_now, device_name, total_online, total_offline, #packages, color, fields, time_now)
    local curl_cmd = string.format("curl -H \"Content-Type: application/json\" -X POST -d '%s' %s", json_payload:gsub("\n", " "), webhook_conf.url)
    os.execute(curl_cmd .. " > /dev/null 2>&1 &") 
end

function hardExit()
    io.write("\027[H\027[2J")
    print("================================")
    print("      STOPPING PROCESSES...     ")
    print("================================")
    os.execute("pkill -9 sleep >/dev/null 2>&1")
    os.execute("pkill -9 curl >/dev/null 2>&1")
    os.execute("pkill -9 read >/dev/null 2>&1")
    os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1")
    print("\n✓ Stopped. Bye!")
    os.exit()
end

-- ==========================================
-- PRE-FLIGHT CHECK
-- ==========================================
function cleanupAndPrepare()
    local buffer = ""
    buffer = buffer .. "========================================\r\n"
    buffer = buffer .. "     PREPARING ENVIRONMENT...\r\n"
    buffer = buffer .. "========================================\r\n"
    local any_reset = false
    for i, pkg in ipairs(packages) do
        app_states[pkg.package] = { 
            startTime = 0, status = "Ready", ignoreUntil = 0,
            uid = getAppUID(pkg.package), 
            lastBytes = 0, strikes = 0, netStatus = "Init"
        }
        -- Cek PID
        local pid_out = exec("pidof " .. pkg.package)
        if pid_out and pid_out ~= "" then
            any_reset = true
            buffer = buffer .. string.format(" [Resetting] %s...\r\n", pkg.name)
            exec("am force-stop " .. pkg.package) -- Direct exec, no null
        end
    end
    if not any_reset then buffer = buffer .. " [System] Clean. Starting...\r\n" end
    io.write("\027[H\027[2J" .. buffer)
    io.stdout:flush()
    if any_reset then os.execute("sleep 2") else os.execute("sleep 1") end
end

-- ==========================================
-- MONITOR LOOP
-- ==========================================
function startMonitoring()
    cleanupAndPrepare()
    launch_queue_index = 1    
    next_launch_time = os.time()
    scan_pointer = 1
    local initial_webhook_sent = false
    local next_webhook_time = 0
    clearScreen()
    while true do
        local current_time = os.time()
        local all_launched = false
        if launch_queue_index <= #packages then
            if current_time >= next_launch_time then
                local pkg = packages[launch_queue_index]
                modifyUGClonerPrefs(pkg.package, launch_queue_index, #packages)
                killAndStart(pkg.package)
                local state = app_states[pkg.package]
                state.status = "Launched"
                state.startTime = current_time
                state.ignoreUntil = current_time + GRACE_PERIOD
                state.strikes = 0
                state.netStatus = "Init"
                launch_queue_index = launch_queue_index + 1
                next_launch_time = current_time + config.delay
            end
        else
            all_launched = true
        end
        scan_pointer = scan_pointer + 1
        if scan_pointer > #packages then scan_pointer = 1 end
        local buffer = ""
        local free_ram = getFreeRAM()
        local launched_count = 0
        for _, pkg in ipairs(packages) do
            if app_states[pkg.package].status ~= "Ready" then launched_count = launched_count + 1 end
        end
        buffer = buffer .. "\027[1;36m" 
        buffer = buffer .. "███████╗███████╗███████╗███╗   ██╗\r\n"
        buffer = buffer .. "╚══███╔╝██╔════╝██╔════╝████╗  ██║\r\n"
        buffer = buffer .. "  ███╔╝ █████╗  █████╗  ██╔██╗ ██║\r\n"
        buffer = buffer .. " ███╔╝  ██╔══╝  ██╔══╝  ██║╚██╗██║\r\n"
        buffer = buffer .. "███████╗███████╗███████╗██║ ╚████║\r\n"
        buffer = buffer .. "╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝\r\n"
        buffer = buffer .. "        ZEEN TOOLS versi ("..ZEEN_VERSION..")\027[0m\r\n"
        buffer = buffer .. "==============================================\r\n"
        buffer = buffer .. string.format(" LAUNCHED   : %d/%d     \r\n", launched_count, #packages)
        buffer = buffer .. string.format(" FREE RAM   : %s\r\n", free_ram)
        buffer = buffer .. "==============================================\r\n"
        buffer = buffer .. string.format(" %-2s %-25s %-10s\r\n", "NO", "NAME (USER)", "STATUS")
        buffer = buffer .. "----------------------------------------------\r\n"
        for i, pkg in ipairs(packages) do
            local state = app_states[pkg.package]
            local status_text = "Unknown"
            local pointer_char = (i == scan_pointer) and ">" or " "
            if state.status == "Ready" then
                status_text = "\027[1;36mReady\027[0m     " 
            elseif state.status == "Launched" or state.status == "ALIVE" or state.status == "DEAD" then
                if current_time < state.ignoreUntil then
                    local timeLeft = state.ignoreUntil - current_time
                    local str = string.format("Load (%ds)", timeLeft)
                    status_text = string.format("\027[1;33m%-10s\027[0m", str) 
                    state.status = "ALIVE"
                else
                    local pid_out = exec("pidof " .. pkg.package)
                    if pid_out ~= "" then
                        local duration = current_time - state.startTime
                        if duration < STABLE_TIME then status_text = "\027[1;32mLaunch    \027[0m"
                        else status_text = "\027[1;32;1mOnline    \027[0m" end 
                        state.status = "ALIVE"
                    else
                        status_text = "\027[1;31mCrash     \027[0m" 
                        state.status = "DEAD"
                    end
                end
            end
            if state.status == "DEAD" then
                local time_since_last_restart = current_time - global_last_restart
                if time_since_last_restart >= QUEUE_DELAY then
                    killAndStart(pkg.package)
                    state.startTime = current_time
                    state.ignoreUntil = current_time + GRACE_PERIOD
                    state.status = "ALIVE"
                    global_last_restart = current_time 
                    
                    if webhook_conf.url ~= "" then
                        sendDiscordWebhook()
                    end
                else
                    local wait_left = QUEUE_DELAY - time_since_last_restart
                    local str = string.format("Queue(%ds)", wait_left)
                    status_text = string.format("\027[1;31m%-10s\027[0m", str)
                end
            end
            local displayName = pkg.name
            if pkg.username then
                local shortPkg = pkg.name:sub(1, 8)
                displayName = string.format("%s (%s)", shortPkg, pkg.username)
            end
            displayName = displayName:sub(1, 25)
            buffer = buffer .. string.format("%s[%d] %-25s %s\r\n", pointer_char, i, displayName, status_text)
        end
        buffer = buffer .. "==============================================\r\n"
        buffer = buffer .. " [TEKAN 'q' ATAU CTRL+C UNTUK KELUAR]         \027[K\r\n"
        if all_launched and not initial_webhook_sent and webhook_conf.url ~= "" then
            buffer = buffer .. "[Sending All Online Webhook...]\027[K\r"
            sendDiscordWebhook()
            initial_webhook_sent = true
            next_webhook_time = current_time + webhook_conf.interval
        elseif initial_webhook_sent and webhook_conf.url ~= "" and current_time >= next_webhook_time then
            buffer = buffer .. "[Sending Routine Webhook...]\027[K\r"
            sendDiscordWebhook()
            next_webhook_time = current_time + webhook_conf.interval
        else
            buffer = buffer .. "\027[K\r" 
        end
        io.write("\027[H" .. buffer) 
        io.stdout:flush()
        local cmd = "trap 'echo STOP_SIGNAL' INT; read -t " .. WATCHDOG_INTERVAL .. " input 2>/dev/null; echo $input"
        local handle = io.popen(cmd)
        local output = handle:read("*a")
        handle:close()
        if output then
            if output:match("STOP_SIGNAL") or output:match("^q") then
                hardExit()
                break
            end
        end
    end
end

-- ==========================================
-- MENU & CONFIG
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
    f = io.open(CONFIG_FILE, "r")
    if f then
        for line in f:lines() do
            local key, val = line:match("(%w+)=(%d+)")
            if key and val then config[key] = tonumber(val) end
        end
        f:close()
    end
    f = io.open(WEBHOOK_FILE, "r")
    if f then
        local url = f:read("*l")
        local interval = f:read("*l")
        if url then webhook_conf.url = url end
        if interval then webhook_conf.interval = tonumber(interval) end
        f:close()
    end
    f = io.open(VIP_FILE, "r")
    if f then vip_link = f:read("*a"):gsub("\n", ""); f:close() end
end

function saveAll()
    local f = io.open(CONFIG_FILE, "w"); f:write("delay=" .. config.delay .. "\n"); f:close()
    f = io.open(WEBHOOK_FILE, "w"); f:write(webhook_conf.url .. "\n" .. webhook_conf.interval .. "\n"); f:close()
    f = io.open(VIP_FILE, "w"); f:write(vip_link); f:close()
    f = io.open(PACKAGE_FILE, "w")
    for _, pkg in ipairs(packages) do 
        local uname = pkg.username or ""
        f:write(pkg.name .. "|" .. pkg.package .. "|" .. uname .. "\n") 
    end
    f:close()
end

function menuSettings()
    while true do
        clearScreen()
        print("══ SETTINGS & EXTRAS ══")
        print("1. Set Delay Launch (Currently: " .. config.delay .. "s)")
        print("2. Set Private Server Link (VIP)")
        print("3. Set Discord Webhook")
        print("4. Kembali")
        io.write("Pilih: ")
        local c = safe_input("")
        if c == "1" then
            io.write("Delay (detik): ")
            config.delay = tonumber(safe_input("")) or 10; saveAll()
        elseif c == "2" then
            print("Masukkan Link VIP (Kosongkan untuk hapus):")
            io.write(">> ")
            vip_link = safe_input(""); saveAll()
        elseif c == "3" then
            print("1. Set URL")
            print("2. Set Interval (Detik)")
            io.write(">> ")
            local wc = safe_input("")
            if wc == "1" then 
                io.write("Webhook URL: ")
                webhook_conf.url = safe_input("")
            elseif wc == "2" then 
                io.write("Interval (cth: 300): ")
                webhook_conf.interval = tonumber(safe_input("")) or 300 
            end
            saveAll()
        elseif c == "4" then break end
    end
end

function autoDetectRoblox()
    clearScreen()
    print("══ AUTO-DETECT PACKAGES ══")
    -- 1. Scan semua paket via Root (Lebih akurat)
    print("Scanning via Root (/system/bin/pm)...")
    local raw_output = exec("/system/bin/pm list packages")
    
    local candidates = {}
    -- Perbaikan: Membersihkan 'package:' di awal string
    for line in raw_output:gmatch("[^\r\n]+") do
        if line:lower():find("roblox") then
            -- Hapus prefix 'package:' dan spasi
            local pkg = line:gsub("package:", ""):gsub("%s+", "")
            if pkg and pkg ~= "" then 
                table.insert(candidates, pkg) 
            end
        end
    end

    if #candidates == 0 then
        print("✗ Tidak ada package 'roblox' ditemukan.")
        print("Tip: Pastikan Root sudah diberikan ke Termux.")
        safe_input("Enter kembali...")
        return
    end

    print("Ditemukan " .. #candidates .. " package:")
    for i, pkg in ipairs(candidates) do
        print(string.format("[%d] %s", i, pkg))
    end

    print("\nOpsi:")
    print("1. Ketik 'all' untuk tambah semua")
    print("2. Ketik nomor dipisah koma (contoh: 1,3,5)")
    io.write("Pilih: ")
    local choice = safe_input("")

    if choice == "all" then
        for _, pkg in ipairs(candidates) do
            local exists = false
            for _, p in ipairs(packages) do if p.package == pkg then exists = true end end
            if not exists then
                local name = pkg:match("com%.roblox%.(.+)") or pkg
                name = name:gsub("%.", " "):gsub("^%l", string.upper)
                table.insert(packages, {name = "Roblox " .. name, package = pkg})
                print(" + " .. name)
            end
        end
    else
        for num in choice:gmatch("%d+") do
            local idx = tonumber(num)
            if idx and candidates[idx] then
                local pkg = candidates[idx]
                local exists = false
                for _, p in ipairs(packages) do if p.package == pkg then exists = true end end
                if not exists then
                    local name = pkg:match("com%.roblox%.(.+)") or pkg
                    name = name:gsub("%.", " "):gsub("^%l", string.upper)
                    table.insert(packages, {name = "Roblox " .. name, package = pkg})
                    print(" + " .. name)
                end
            end
        end
    end
    saveAll()
    safe_input("\nSelesai. Enter kembali...")
end

function launchAutoGrid()
    local result = exec("wm size")
    local w, h = result:match("Physical size: (%d+)x(%d+)")
    if w then
        w, h = tonumber(w), tonumber(h)
        local ori = exec("dumpsys window | grep 'mCurrentRotation'")
        if ori:match("ROTATION_90") or ori:match("ROTATION_270") then
            if w < h then DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w else DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h end
        else
            if w > h then DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w else DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h end
        end
    end

    clearScreen()
    print("══ DASHBOARD LAUNCH ══")
    if #packages == 0 then print("✗ No packages!"); safe_input("Enter..."); return end
    
    io.write("Start Monitoring? (y/n): ")
    if safe_input("") ~= "y" then return end
    
    startMonitoring()
end

function main()
    os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1") 
    
    getDeviceName()
    loadData()
    while true do
        clearScreen()
        print("ZEEN TOOLS v10.0 (EXECUTION FIX)")
        print("1. Start Auto Grid & Monitor")
        print("2. Detect Roblox (New)")
        print("3. List Packages")
        print("4. Settings (VIP/Webhook)")
        print("5. Cookie Manager")
        print("6. Clear Data")
        print("7. Exit")
        
        io.write("Pilih: ")
        local choice = safe_input("")
        
        if choice == "1" then launchAutoGrid()
        elseif choice == "2" then autoDetectRoblox()
        elseif choice == "3" then 
            clearScreen()
            print("=== LIST PACKAGES ===")
            for i,p in ipairs(packages) do print(i..". "..p.name.."\r\n") end 
            safe_input("\nTekan Enter kembali...")
        elseif choice == "4" then menuSettings()
        elseif choice == "5" then menuCookieManager()
        elseif choice == "6" then packages={}; saveAll(); print("Cleared."); safe_input("Enter...")
        elseif choice == "7" then 
            hardExit()
            break 
        end
    end
end

main()


