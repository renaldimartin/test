#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v10.0 (HEARTBEAT)
-- ==========================================
-- Update v10.0:
-- [+] HEARTBEAT: Deteksi Disconnect via Network Bytes
-- [+] UID TRACKER: Mapping otomatis Package -> UID
-- [+] STRIKE SYSTEM: 6x Data Macet = Kill & Restart
-- [+] DASHBOARD: Menampilkan status koneksi real-time
-- ==========================================

-- 1. SETUP TERMINAL TOTAL
os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1") 
io.stdout:setvbuf("no")

-- ==========================================
-- KONFIGURASI PATH (SDCARD)
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
local TEMP_SCRIPT = CONFIG_DIR .. "/temp_cmd.sh"

-- ==========================================
-- KONFIGURASI SYSTEM
-- ==========================================
local ZEEN_VERSION = "v10.0"
local WATCHDOG_INTERVAL = 3   -- Cek setiap 3 detik
local GRACE_PERIOD = 60       -- Waktu kebal awal (loading game)
local QUEUE_DELAY = 30        -- Jeda antar restart
local STABLE_TIME = 60        
local TRAFFIC_THRESHOLD = 2000 -- Batas data (2KB) sesuai request
local MAX_STRIKES = 6         -- 6x gagal = KILL

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

-- Eksekutor Root
function exec(cmd)
    local f = io.open(TEMP_SCRIPT, "w")
    if not f then return "" end
    f:write("#!/system/bin/sh\n" .. cmd .. "\n")
    f:close()
    os.execute("chmod +x " .. TEMP_SCRIPT .. " >/dev/null 2>&1")
    local handle = io.popen("su -c '" .. TEMP_SCRIPT .. "' 2>/dev/null")
    local result = handle:read("*a")
    handle:close()
    os.remove(TEMP_SCRIPT)
    return result or ""
end

function exec_root_mm(cmd)
    local f = io.open(TEMP_SCRIPT, "w")
    if not f then return "" end
    f:write("#!/system/bin/sh\n" .. cmd .. "\n")
    f:close()
    os.execute("chmod +x " .. TEMP_SCRIPT .. " >/dev/null 2>&1")
    local handle = io.popen("su -mm -c '" .. TEMP_SCRIPT .. "' 2>/dev/null")
    local result = handle:read("*a")
    handle:close()
    os.remove(TEMP_SCRIPT)
    return result or ""
end

function getDeviceName()
    local model = exec("getprop ro.product.model"):gsub("\n", "")
    if model == "" then model = "Termux Device" end
    device_name = model
end

function getFreeRAM()
    local output = exec("cat /proc/meminfo | grep MemAvailable")
    local kb = output:match("(%d+)")
    if kb then
        local gb = tonumber(kb) / 1024 / 1024
        return string.format("%.2f GB", gb)
    end
    return "0.00 GB"
end

-- ==========================================
-- HEARTBEAT LOGIC (NETWORK)
-- ==========================================

-- Mendapatkan UID Android dari nama paket
function getAppUID(package)
    -- Menggunakan perintah stat pada folder data aplikasi
    local cmd = "stat -c %u /data/data/" .. package
    local uid = exec(cmd):gsub("%s+", "")
    if uid and tonumber(uid) then 
        return tonumber(uid) 
    end
    return nil
end

-- Membaca total bytes yang diterima (TCP RCV)
function getNetworkBytes(uid)
    if not uid then return 0 end
    -- Membaca langsung dari kernel stat
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
    local cmd = string.format("curl -s -L --max-time 10 -A 'Mozilla/5.0' -H 'Cookie: .ROBLOSECURITY=%s' \"%s\"", safe_cookie, url)
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
    local handle = io.popen(sqlite_cmd)
    local raw_cookie = handle:read("*a")
    handle:close()
    os.remove(temp_db)
    if raw_cookie and #raw_cookie > 20 then return raw_cookie:gsub("[\r\n]", "") end
    return nil
end

function menuCookieManager()
    while true do
        clearScreen()
        print("══ COOKIE MANAGER ══")
        print("1. Scan Identity")
        print("2. Export Cookies")
        print("3. Kembali")
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
            -- Export logic (simplified)
            safe_input("Fitur export belum diaktifkan di versi ini. Enter...")
        elseif c == "3" then break end
    end
end

-- ==========================================
-- LAYOUT & APP CONTROL
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

function killAndStart(package)
    exec("am force-stop " .. package .. " >/dev/null 2>&1")
    if vip_link and vip_link ~= "" and vip_link:match("roblox.com") then
        local cmd = string.format("am start -a android.intent.action.VIEW -d \"%s\" -p %s >/dev/null 2>&1", vip_link, package)
        exec(cmd)
    else
        exec("am start " .. package .. " >/dev/null 2>&1")
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
    local time_now = os.date("%H:%M")
    
    for _, pkg in ipairs(packages) do
        local state = app_states[pkg.package]
        local is_online = (state.status == "ALIVE" or state.status == "Launched")
        
        if is_online then total_online = total_online + 1 else total_offline = total_offline + 1 end
        
        local status_icon = is_online and "🟢" or "🔴"
        local ram_val = state.lastBytes and string.format("Ping: OK") or "Ping: -" -- Simplified
        local uname_display = pkg.username and string.format("(%s)", pkg.username) or ""
        local field_val = is_online and "`ONLINE`" or "`OFFLINE`"
        
        fields = fields .. string.format('{"name": "%s %s ||%s||", "value": "%s", "inline": false},', status_icon, pkg.name, uname_display, field_val)
    end
    
    fields = fields:sub(1, -2)
    local color = 65280 
    if total_offline > 0 then color = 16711680 end 
    local json_payload = string.format([[ {"content": null, "embeds": [ { "title": "ZEEN TOOLS | MONITOR", "description": "Update: **%s**\n🟢 Online: %d | 🔴 Offline: %d", "color": %d, "fields": [%s], "footer": { "text": "Heartbeat Edition" } } ] } ]], time_now, total_online, total_offline, color, fields)
    local curl_cmd = string.format("curl -H \"Content-Type: application/json\" -X POST -d '%s' %s", json_payload:gsub("\n", " "), webhook_conf.url)
    os.execute(curl_cmd .. " > /dev/null 2>&1 &") 
end

function hardExit()
    io.write("\027[H\027[2J")
    print("STOPPING PROCESSES...")
    os.execute("pkill -9 sleep >/dev/null 2>&1")
    os.execute("pkill -9 curl >/dev/null 2>&1")
    os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1")
    print("\n✓ Stopped. Bye!")
    os.exit()
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
        print("══ SETTINGS ══")
        print("1. Set Delay")
        print("2. Set VIP Link")
        print("3. Set Webhook")
        print("4. Kembali")
        io.write("Pilih: ")
        local c = safe_input("")
        if c == "1" then config.delay = tonumber(safe_input("Delay: ")) or 10; saveAll()
        elseif c == "2" then vip_link = safe_input("Link: "); saveAll()
        elseif c == "3" then webhook_conf.url = safe_input("URL: "); saveAll()
        elseif c == "4" then break end
    end
end

function autoDetectRoblox()
    clearScreen()
    print("══ AUTO-DETECT ══")
    print("Scanning...")
    local raw_output = exec("/system/bin/pm list packages")
    local candidates = {}
    for line in raw_output:gmatch("[^\r\n]+") do
        if line:lower():find("roblox") then
            local pkg = line:gsub("package:", ""):gsub("%s+", "")
            if pkg and pkg ~= "" then table.insert(candidates, pkg) end
        end
    end
    if #candidates == 0 then print("Not found."); safe_input("Enter..."); return end
    
    for i, pkg in ipairs(candidates) do print(string.format("[%d] %s", i, pkg)) end
    io.write("\nPilih (all/1,2): ")
    local choice = safe_input("")
    if choice == "all" then
        for _, pkg in ipairs(candidates) do
            table.insert(packages, {name = pkg, package = pkg})
        end
    else
        for num in choice:gmatch("%d+") do
            local idx = tonumber(num)
            if idx and candidates[idx] then
                table.insert(packages, {name = candidates[idx], package = candidates[idx]})
            end
        end
    end
    saveAll()
end

-- ==========================================
-- PRE-FLIGHT CHECK
-- ==========================================
function cleanupAndPrepare()
    local any_reset = false
    for i, pkg in ipairs(packages) do
        -- Reset State & Ambil UID
        app_states[pkg.package] = { 
            startTime = 0, status = "Ready", ignoreUntil = 0,
            uid = getAppUID(pkg.package), -- PENTING: Simpan UID di sini
            lastBytes = 0, strikes = 0
        }
        
        local pid_out = exec("pidof " .. pkg.package)
        if pid_out and pid_out ~= "" then
            any_reset = true
            exec("am force-stop " .. pkg.package .. " >/dev/null 2>&1")
        end
    end
    if any_reset then os.execute("sleep 2") else os.execute("sleep 1") end
end

-- ==========================================
-- MAIN MONITOR LOOP (HEARTBEAT)
-- ==========================================
function startMonitoring()
    if #packages == 0 then print("No packages."); safe_input("Enter..."); return end
    
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
        
        -- A. LAUNCHER
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
                state.lastBytes = getNetworkBytes(state.uid) -- Ambil data awal
                
                launch_queue_index = launch_queue_index + 1
                next_launch_time = current_time + config.delay
            end
        else
            all_launched = true
        end

        scan_pointer = scan_pointer + 1
        if scan_pointer > #packages then scan_pointer = 1 end

        -- B. RENDER DASHBOARD
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
            local force_kill = false
            
            if state.status == "Ready" then
                status_text = "\027[1;36mReady\027[0m     " 
            
            elseif state.status == "Launched" or state.status == "ALIVE" or state.status == "DEAD" then
                if current_time < state.ignoreUntil then
                    local timeLeft = state.ignoreUntil - current_time
                    local str = string.format("Load (%ds)", timeLeft)
                    status_text = string.format("\027[1;33m%-10s\027[0m", str) 
                    state.status = "ALIVE"
                    -- Update bytes diam-diam saat loading
                    state.lastBytes = getNetworkBytes(state.uid)
                else
                    -- === HEARTBEAT CHECK ===
                    local pid_out = exec("pidof " .. pkg.package)
                    if pid_out ~= "" then
                        -- PID ADA, Cek Trafik
                        local currBytes = getNetworkBytes(state.uid)
                        local diff = currBytes - state.lastBytes
                        state.lastBytes = currBytes
                        
                        -- Logika Heartbeat (diff < 2000 bytes)
                        if diff < TRAFFIC_THRESHOLD then
                            state.strikes = state.strikes + 1
                            status_text = string.format("\027[1;31mLAG (%d)\027[0m", state.strikes)
                            if state.strikes >= MAX_STRIKES then force_kill = true end
                        else
                            state.strikes = 0
                            status_text = "\027[1;32;1mOnline    \027[0m"
                        end
                        state.status = "ALIVE"
                    else
                        status_text = "\027[1;31mCrash     \027[0m" 
                        state.status = "DEAD"
                    end
                end
            end

            if force_kill or state.status == "DEAD" then
                state.status = "DEAD"
                local time_since_last_restart = current_time - global_last_restart
                if time_since_last_restart >= QUEUE_DELAY then
                    if force_kill then status_text = "\027[1;31mKILLED\027[0m" end
                    killAndStart(pkg.package)
                    state.startTime = current_time
                    state.ignoreUntil = current_time + GRACE_PERIOD
                    state.status = "ALIVE"
                    state.strikes = 0
                    global_last_restart = current_time 
                else
                    local wait_left = QUEUE_DELAY - time_since_last_restart
                    local str = string.format("Queue(%ds)", wait_left)
                    status_text = string.format("\027[1;31m%-10s\027[0m", str)
                end
            end
            
            local displayName = pkg.name:sub(1, 20)
            if pkg.username then displayName = pkg.username:sub(1, 20) end
            buffer = buffer .. string.format("%s[%d] %-25s %s\r\n", pointer_char, i, displayName, status_text)
        end
        
        buffer = buffer .. "==============================================\r\n"
        buffer = buffer .. " [TEKAN 'q' UNTUK KELUAR]                     \027[K\r\n"
        
        -- Webhook logic
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

function main()
    os.execute("stty sane cooked icrnl echo onlcr >/dev/null 2>&1") 
    getDeviceName()
    loadData()
    while true do
        clearScreen()
        print("ZEEN TOOLS v10.0 (HEARTBEAT)")
        print("1. Start Auto Grid & Monitor")
        print("2. Detect Roblox")
        print("3. List Packages")
        print("4. Settings")
        print("5. Cookie Manager")
        print("6. Clear Data")
        print("7. Exit")
        io.write("Pilih: ")
        local c = safe_input("")
        if c == "1" then startMonitoring()
        elseif c == "2" then autoDetectRoblox()
        elseif c == "3" then 
            clearScreen()
            for i,p in ipairs(packages) do print(i..". "..p.name) end 
            safe_input("Enter...")
        elseif c == "4" then menuSettings()
        elseif c == "5" then menuCookieManager()
        elseif c == "6" then packages={}; saveAll(); safe_input("Cleared.")
        elseif c == "7" then hardExit() break end
    end
end

main()

