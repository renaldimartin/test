#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v7.3 (FINAL)
-- ==========================================
-- Update v7.3:
-- [+] CLEANUP: Menghapus potensi syntax error
-- [+] CTRL+C FIX: Sinyal Stop berfungsi 100%
-- [+] ANTI-DOUBLE: Tampilan Dashboard stabil
-- ==========================================

-- 1. SETUP TERMINAL
os.execute("stty sane >/dev/null 2>&1") 
io.stdout:setvbuf("no")

-- ==========================================
-- FUNGSI DISPLAY & UI (BUFFERED)
-- ==========================================

function trim(s)
   return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function safe_input(prompt)
    io.stdout:flush()
    io.write(prompt)
    io.stdout:flush()
    local result = io.read()
    if not result then return "" end
    return trim(result)
end

function clearScreen()
    io.write("\027[H\027[2J") -- Clear Total + Home
    io.stdout:flush()
end

-- ==========================================
-- KONFIGURASI SYSTEM
-- ==========================================
local WATCHDOG_INTERVAL = 2   
local GRACE_PERIOD = 35       
local QUEUE_DELAY = 30        
local STABLE_TIME = 60
local STATUS_BAR_HEIGHT = 60
local DEFAULT_DELAY = 10
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 

local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local CONFIG_FILE = "/data/data/com.termux/files/home/.zeen_config.txt"
local WEBHOOK_FILE = "/data/data/com.termux/files/home/.zeen_webhook.txt"
local VIP_FILE = "/data/data/com.termux/files/home/.zeen_vip.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

local packages = {}
local app_states = {} 
local global_last_restart = 0 
local config = { delay = DEFAULT_DELAY }
local webhook_conf = { url = "", interval = 300 } 
local vip_link = ""
local device_name = "Android Device"

-- Variabel Kontrol Launching
local launch_queue_index = 1    
local next_launch_time = 0      

-- ==========================================
-- SYSTEM HELPERS (SILENT)
-- ==========================================

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
        return string.format("%.1f GB", gb)
    end
    return "Unknown"
end

-- ==========================================
-- LAYOUT LOGIC
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
-- APP MANAGEMENT
-- ==========================================

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
            if not is_launching then
                 pid, _, rss_kb = getProcessInfo(pkg.package)
            end
            
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
        
        local field_val = string.format("`⏱️ %s | 💾 %s`", uptime, ram_val)
        if not is_online then field_val = "`🔻 OFFLINE`" end
        if state.status == "Ready" then field_val = "`⏳ QUEUE`" end
        
        fields = fields .. string.format('{"name": "%s ||%s||", "value": "%s", "inline": false},', status_icon, pkg.name, field_val)
    end
    
    fields = fields:sub(1, -2)
    local color = 65280 
    if total_offline > 0 then color = 16711680 end 
    
    local json_payload = string.format([[
    {
      "content": null,
      "embeds": [
        {
          "title": "ZEEN TOOLS | MONITOR STATUS",
          "description": "Last Update: **%s**\nDevice: **%s**\n\n**Status:**\n🟢 Online: %d\n🔴 Offline: %d\n🤖 Total: %d",
          "color": %d,
          "fields": [%s],
          "footer": {
            "text": "ZEEN TOOLS | %s"
          }
        }
      ]
    }
    ]], time_now, device_name, total_online, total_offline, #packages, color, fields, time_now)

    local curl_cmd = string.format("curl -H \"Content-Type: application/json\" -X POST -d '%s' %s", json_payload:gsub("\n", " "), webhook_conf.url)
    os.execute(curl_cmd .. " > /dev/null 2>&1 &") 
end

function hardExit()
    -- Clear layar dan tampilkan pesan keluar
    io.write("\027[H\027[2J")
    io.write("================================\r\n")
    io.write("      STOPPING PROCESSES...     \r\n")
    io.write("================================\r\n")
    io.stdout:flush()
    
    -- Paksa kill semua proses terkait
    os.execute("pkill -9 sleep >/dev/null 2>&1")
    os.execute("pkill -9 curl >/dev/null 2>&1")
    os.execute("pkill -9 read >/dev/null 2>&1")
    
    io.write("\n✓ Stopped. Bye!\r\n")
    io.stdout:flush()
    os.exit()
end

-- ==========================================
-- PRE-FLIGHT CHECK (RESETTING)
-- ==========================================
function cleanupAndPrepare()
    local buffer = ""
    buffer = buffer .. "========================================\r\n"
    buffer = buffer .. "     PREPARING ENVIRONMENT...\r\n"
    buffer = buffer .. "========================================\r\n"
    
    local any_reset = false
    for i, pkg in ipairs(packages) do
        app_states[pkg.package] = { startTime = 0, status = "Ready", ignoreUntil = 0 }
        
        local pid_out = exec("pidof " .. pkg.package)
        if pid_out and pid_out ~= "" then
            any_reset = true
            buffer = buffer .. string.format(" [Resetting] %s...\r\n", pkg.name)
            exec("am force-stop " .. pkg.package .. " >/dev/null 2>&1")
        end
    end
    
    if not any_reset then buffer = buffer .. " [System] Clean. Starting...\r\n" end
    
    io.write("\027[H\027[2J" .. buffer)
    io.stdout:flush()
    
    if any_reset then os.execute("sleep 2") else os.execute("sleep 1") end
end

-- ==========================================
-- MAIN MONITOR LOOP (TRAP SIGNAL)
-- ==========================================
function startMonitoring()
    cleanupAndPrepare()
    
    launch_queue_index = 1    
    next_launch_time = os.time()
    local next_webhook_time = os.time() + 5 
    
    while true do
        local current_time = os.time()
        
        -- LOGIC UPDATE
        if launch_queue_index <= #packages then
            if current_time >= next_launch_time then
                local pkg = packages[launch_queue_index]
                modifyUGClonerPrefs(pkg.package, launch_queue_index, #packages)
                killAndStart(pkg.package)
                app_states[pkg.package].status = "Launched"
                app_states[pkg.package].startTime = current_time
                app_states[pkg.package].ignoreUntil = current_time + GRACE_PERIOD
                launch_queue_index = launch_queue_index + 1
                next_launch_time = current_time + config.delay
            end
        end

        -- RENDER BUFFER
        local buffer = ""
        local free_ram = getFreeRAM()
        local current_monitor_idx = math.min(launch_queue_index, #packages)
        if launch_queue_index > #packages then current_monitor_idx = #packages end

        buffer = buffer .. "========================================\r\n"
        buffer = buffer .. "     ZEEN TOOLS v7.3 (FINAL)\r\n"
        buffer = buffer .. "========================================\r\n"
        buffer = buffer .. string.format(" MONITORING    : %d/%d      |  FREE RAM : %s\r\n", current_monitor_idx, #packages, free_ram)
        buffer = buffer .. "========================================\r\n"

        for i, pkg in ipairs(packages) do
            local state = app_states[pkg.package]
            local status_text = "\027[1;30mUnknown\027[0m"
            
            if state.status == "Ready" then
                status_text = "\027[1;36mReady\027[0m" 
            elseif state.status == "Launched" or state.status == "ALIVE" or state.status == "DEAD" then
                if current_time < state.ignoreUntil then
                    local timeLeft = state.ignoreUntil - current_time
                    status_text = string.format("\027[1;33mLaunched (%ds)\027[0m", timeLeft) 
                    state.status = "ALIVE"
                else
                    local pid_out = exec("pidof " .. pkg.package)
                    if pid_out ~= "" then
                        local duration = current_time - state.startTime
                        if duration < STABLE_TIME then status_text = "\027[1;32mLaunched\027[0m"
                        else status_text = "\027[1;32mOnline\027[0m" end 
                        state.status = "ALIVE"
                    else
                        status_text = "\027[1;31mRetrying...\027[0m" 
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
                else
                    local wait_left = QUEUE_DELAY - time_since_last_restart
                    status_text = string.format("\027[1;31mRetrying (%ds)\027[0m", wait_left)
                end
            end
            
            local shortName = pkg.name:sub(1, 15)
            buffer = buffer .. string.format("[%d] %-16s : %-20s\027[K\r\n", i, shortName, status_text)
        end
        
        buffer = buffer .. "========================================\r\n"
        buffer = buffer .. " [TEKAN 'q' ATAU CTRL+C UNTUK KELUAR]   \027[K\r\n"
        
        if webhook_conf.url ~= "" and current_time >= next_webhook_time then
            buffer = buffer .. "[Sending Webhook...]\027[K\r"
            sendDiscordWebhook()
            next_webhook_time = current_time + webhook_conf.interval
        else
            buffer = buffer .. "\027[K\r" 
        end
        
        io.write("\027[H" .. buffer) 
        io.stdout:flush()
        
        -- INPUT CHECK DENGAN TRAP CTRL+C
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
            local name, package = line:match("(.+)|(.+)")
            if name and package then table.insert(packages, {name = name, package = package}) end
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
    for _, pkg in ipairs(packages) do f:write(pkg.name .. "|" .. pkg.package .. "\n") end
    f:close()
end

function menuSettings()
    while true do
        clearScreen()
        io.write("══ SETTINGS & EXTRAS ══\r\n")
        io.write("1. Set Delay Launch (Currently: " .. config.delay .. "s)\r\n")
        io.write("2. Set Private Server Link (VIP)\r\n")
        io.write("3. Set Discord Webhook\r\n")
        io.write("4. Kembali\r\n")
        
        local c = safe_input("Pilih: ")
        
        if c == "1" then
            config.delay = tonumber(safe_input("Delay (detik): ")) or 10
            saveAll()
        elseif c == "2" then
            io.write("Masukkan Link VIP (Kosongkan untuk hapus):\r\n")
            vip_link = safe_input(">> ")
            saveAll()
        elseif c == "3" then
            io.write("1. Set URL\r\n")
            io.write("2. Set Interval (Detik)\r\n")
            local wc = safe_input(">> ")
            if wc == "1" then 
                webhook_conf.url = safe_input("Webhook URL: ")
            elseif wc == "2" then 
                webhook_conf.interval = tonumber(safe_input("Interval (cth: 300): ")) or 300 
            end
            saveAll()
        elseif c == "4" then break end
    end
end

function autoDetectRoblox()
    clearScreen()
    io.write("══ AUTO-DETECT ROBLOX ══\r\n")
    local result = exec("pm list packages | grep 'roblox'")
    local detected = {}
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then table.insert(detected, pkg) end
    end
    if #detected == 0 then io.write("✗ Tidak ada Roblox.\r\n"); safe_input("Tekan Enter..."); return end
    
    io.write("✓ Ditemukan " .. #detected .. " packages. Ketik 'all' add.\r\n")
    if safe_input("Pilihan: ") == "all" then
        for _, pkg in ipairs(detected) do
            local exists = false
            for _, p in ipairs(packages) do if p.package == pkg then exists = true end end
            if not exists then
                local name = pkg:match("com%.roblox%.(.+)") or pkg
                name = name:gsub("%.", " "):gsub("^%l", string.upper)
                table.insert(packages, {name = "Roblox " .. name, package = pkg})
            end
        end
        saveAll()
    end
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
    io.write("══ DASHBOARD LAUNCH ══\r\n")
    if #packages == 0 then io.write("✗ No packages!\r\n"); safe_input("Enter..."); return end
    
    if safe_input("Start Monitoring? (y/n): ") ~= "y" then return end
    
    startMonitoring()
end

function main()
    os.execute("stty sane >/dev/null 2>&1") 
    getDeviceName()
    loadData()
    while true do
        clearScreen()
        io.write("ZEEN TOOLS v7.3 (FINAL)\r\n")
        io.write("1. Start Auto Grid & Monitor\r\n")
        io.write("2. Detect Roblox\r\n")
        io.write("3. List Packages\r\n")
        io.write("4. Settings (VIP/Webhook)\r\n")
        io.write("5. Clear Data\r\n")
        io.write("6. Exit\r\n")
        
        local choice = safe_input("Pilih: ")
        
        if choice == "1" then launchAutoGrid()
        elseif choice == "2" then autoDetectRoblox()
        elseif choice == "3" then 
            clearScreen()
            io.write("=== LIST PACKAGES ===\r\n")
            for i,p in ipairs(packages) do io.write(i..". "..p.name.."\r\n") end 
            safe_input("\nTekan Enter kembali...")
        elseif choice == "4" then menuSettings()
        elseif choice == "5" then packages={}; saveAll(); io.write("Cleared.\r\n"); safe_input("Enter...")
        elseif choice == "6" then 
            hardExit()
            break 
        end
    end
end

main()

