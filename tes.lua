#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v5.2 (STABLE UI)
-- Auto Grid - Monitoring - Webhook
-- ==========================================
-- Update v5.2 (FIX CRITICAL UI):
-- [+] FIX: Menu berantakan (Staircase effect)
-- [+] FIX: Input macet/tidak muncul
-- [+] FIX: Kursor hilang saat kembali ke menu
-- [+] ADD: Terminal Reset saat start
-- ==========================================

-- KONFIGURASI SYSTEM
local WATCHDOG_INTERVAL = 5
local QUEUE_DELAY = 30
local STABLE_TIME = 60

-- KONFIGURASI DEFAULT
local STATUS_BAR_HEIGHT = 60
local DEFAULT_DELAY = 10
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 

-- File paths
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local CONFIG_FILE = "/data/data/com.termux/files/home/.zeen_config.txt"
local WEBHOOK_FILE = "/data/data/com.termux/files/home/.zeen_webhook.txt"
local VIP_FILE = "/data/data/com.termux/files/home/.zeen_vip.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

-- Data storage
local packages = {}
local app_states = {} 
local global_last_restart = 0 
local config = { delay = DEFAULT_DELAY }
local webhook_conf = { url = "", interval = 300 } 
local vip_link = ""
local device_name = "Android Device"

-- ==========================================
-- TERMINAL UTILS (FIX UI)
-- ==========================================

function resetTerminal()
    -- Munculkan kursor kembali & reset atribut warna
    io.write("\027[?25h") 
    io.write("\027[0m")
    io.stdout:flush()
end

function clearScreen()
    -- Bersihkan layar dengan aman
    io.write("\027[H\027[2J")
    io.stdout:flush()
end

-- Override print agar selalu flush dan rapi
local old_print = print
function print(str)
    str = str or ""
    io.write(str .. "\n")
    io.stdout:flush()
end

function exec(cmd)
    local f = io.open(TEMP_SCRIPT, "w")
    if not f then return "" end
    f:write("#!/system/bin/sh\n" .. cmd .. "\n")
    f:close()
    os.execute("chmod +x " .. TEMP_SCRIPT)
    
    local handle = io.popen("su -c " .. TEMP_SCRIPT)
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

-- ==========================================
-- LAYOUT LOGIC (LEFT 2:1)
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
    local out = exec("ps -A -o pid,state,rss,args | grep " .. package .. " | grep -v grep | head -n 1")
    local pid, state, rss = out:match("(%d+)%s+([%w])%s+(%d+)")
    return pid, state, tonumber(rss)
end

function killAndStart(package, isFirstTime)
    exec("am force-stop " .. package)
    
    if vip_link and vip_link ~= "" and vip_link:match("roblox.com") then
        local cmd = string.format("am start -a android.intent.action.VIEW -d \"%s\" -p %s", vip_link, package)
        exec(cmd)
    else
        exec("am start " .. package)
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
        local pid, proc_state, rss_kb = getProcessInfo(pkg.package)
        local is_online = (pid and proc_state ~= "Z")
        
        local status_icon = "🔴"
        local ram_usage = "0MB"
        local uptime = "0m"
        
        if is_online then
            total_online = total_online + 1
            status_icon = "🟢"
            if rss_kb then ram_usage = string.format("%dMB", math.floor(rss_kb/1024)) end
            local diff = os.time() - state.startTime
            uptime = string.format("%dm", math.floor(diff/60))
        else
            total_offline = total_offline + 1
        end

        local field_val = string.format("`⏱️ %s | 💾 %s | ⚙️ N/A`", uptime, ram_usage)
        if not is_online then field_val = "`🔻 OFFLINE`" end
        
        fields = fields .. string.format('{"name": "%s ||%s||", "value": "%s", "inline": false},', status_icon, pkg.name, field_val)
    end
    
    fields = fields:sub(1, -2)
    local color = 65280 -- Green
    if total_offline > 0 then color = 16711680 end -- Red
    
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

-- ==========================================
-- MONITORING LOOP
-- ==========================================
function startMonitoring()
    for i, pkg in ipairs(packages) do
        if not app_states[pkg.package] then
            app_states[pkg.package] = { startTime = os.time(), status = "Init" }
        end
    end
    
    local next_webhook_time = os.time() + 5 

    io.write("\027[?25l") -- Hide Cursor
    io.write("\027[2J")   -- Clear Screen

    while true do
        local current_time = os.time()
        io.write("\027[H") -- Reset Cursor (No Blink)
        
        print("========================================")
        print("     ZEEN TOOLS v5.2 (ULTIMATE)")
        print("========================================")
        print(string.format(" Monitor : %d Apps    |    Queue: 30s", #packages))
        if vip_link ~= "" then print(" VIP Link: ACTIVE (Direct Pkg)")
        else print(" VIP Link: -") end
        print("========================================")

        for i, pkg in ipairs(packages) do
            local state = app_states[pkg.package]
            local pid, proc_state, rss = getProcessInfo(pkg.package)
            local status_text = "Unknown"
            
            if pid then
                if proc_state == "Z" then
                    status_text = "Retrying (Zombie)"
                    exec("kill -9 " .. pid)
                    state.status = "DEAD"
                else
                    local duration = current_time - state.startTime
                    if duration < STABLE_TIME then status_text = "Launched"
                    else status_text = "Online" end
                    state.status = "ALIVE"
                end
            else
                state.status = "DEAD"
            end

            if state.status == "DEAD" then
                local time_since_last_restart = current_time - global_last_restart
                if time_since_last_restart >= QUEUE_DELAY then
                    status_text = "Retrying..."
                    killAndStart(pkg.package, false)
                    state.startTime = current_time
                    global_last_restart = current_time
                    state.status = "ALIVE"
                else
                    local wait_left = QUEUE_DELAY - time_since_last_restart
                    status_text = string.format("Ready (%ds)", wait_left)
                end
            end
            
            local shortName = pkg.name:sub(1, 15)
            io.write(string.format("[%d] %-16s : %-20s\027[K\n", i, shortName, status_text))
        end
        
        print("========================================")
        print(" CTRL+C to Stop & Exit to Shell ($)     \027[K")
        
        if webhook_conf.url ~= "" and current_time >= next_webhook_time then
            io.write(" [Sending Webhook...]\027[K\r")
            sendDiscordWebhook()
            next_webhook_time = current_time + webhook_conf.interval
        end
        
        -- FIX CTRL+C SAFE EXIT
        io.stdout:flush()
        local sleep_ok = os.execute("sleep " .. WATCHDOG_INTERVAL)
        if not sleep_ok then
            resetTerminal()
            os.exit()
        end
    end
end

-- ==========================================
-- MENU & CONFIG (UI FIX)
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
        print("══ SETTINGS & EXTRAS ══")
        print("1. Set Delay Launch (Currently: " .. config.delay .. "s)")
        print("2. Set Private Server Link (VIP)")
        print("3. Set Discord Webhook")
        print("4. Kembali")
        io.write("Pilih: ")
        io.stdout:flush() -- FIX INPUT MACET
        
        local c = io.read()
        if c == "1" then
            io.write("Delay (detik): "); io.stdout:flush()
            config.delay = tonumber(io.read()) or 10; saveAll()
        elseif c == "2" then
            print("Masukkan Link VIP (Kosongkan untuk hapus):")
            vip_link = io.read()
            saveAll()
        elseif c == "3" then
            print("1. Set URL")
            print("2. Set Interval (Detik)")
            io.write(">> "); io.stdout:flush()
            local wc = io.read()
            if wc == "1" then io.write("Webhook URL: "); io.stdout:flush(); webhook_conf.url = io.read()
            elseif wc == "2" then io.write("Interval (cth: 300): "); io.stdout:flush(); webhook_conf.interval = tonumber(io.read()) or 300 end
            saveAll()
        elseif c == "4" then break end
    end
end

function autoDetectRoblox()
    clearScreen()
    print("══ AUTO-DETECT ROBLOX ══")
    local result = exec("pm list packages | grep 'roblox'")
    local detected = {}
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then table.insert(detected, pkg) end
    end
    if #detected == 0 then print("✗ Tidak ada Roblox."); io.read(); return end
    print("✓ Ditemukan " .. #detected .. " packages. Ketik 'all' add.")
    io.write("Pilihan: "); io.stdout:flush()
    if io.read() == "all" then
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
    clearScreen()
    print("══ LAUNCHING SEQUENCE ══")
    if #packages == 0 then print("✗ No packages!"); io.read(); return end
    
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
    
    io.write("Start Farming? (y/n): ")
    io.stdout:flush()
    if io.read() ~= "y" then return end
    
    -- INITIAL LAUNCH
    app_states = {}
    local maxApps = #packages
    for i = 1, maxApps do
        local pkg = packages[i]
        print("[" .. i .. "] Launching " .. pkg.name .. "...")
        modifyUGClonerPrefs(pkg.package, i, maxApps)
        killAndStart(pkg.package, true)
        app_states[pkg.package] = { startTime = os.time(), status = "Launched" }
        if i < maxApps then os.execute("sleep " .. config.delay) end
    end
    
    startMonitoring()
end

function main()
    -- FIX BUFFERING ISSUE
    io.stdout:setvbuf("no")
    resetTerminal() -- RESET TERMINAL DI AWAL AGAR RAPI
    getDeviceName()
    loadData()
    while true do
        clearScreen()
        print("ZEEN TOOLS v5.2 (ULTIMATE)")
        print("1. Start Auto Grid & Monitor")
        print("2. Detect Roblox")
        print("3. List Packages")
        print("4. Settings (VIP/Webhook)")
        print("5. Clear Data")
        print("6. Exit")
        io.write("Pilih: ")
        io.stdout:flush() -- PENTING! Agar input muncul
        
        local choice = io.read()
        if choice == "1" then launchAutoGrid()
        elseif choice == "2" then autoDetectRoblox()
        elseif choice == "3" then 
            clearScreen()
            print("=== LIST PACKAGES ===")
            for i,p in ipairs(packages) do print(i..". "..p.name) end 
            print("\nTekan Enter kembali...")
            io.read()
        elseif choice == "4" then menuSettings()
        elseif choice == "5" then packages={}; saveAll(); print("Cleared."); io.read()
        elseif choice == "6" then 
            resetTerminal() -- KEMBALIKAN KURSOR SAAT KELUAR
            break 
        end
    end
end

main()

