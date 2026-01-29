#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v5.4 (FIX DISPLAY)
-- ==========================================
-- Update v5.4:
-- [+] OBAT TAMPILAN TANGGA (stty sane)
-- [+] FIX INPUT TIDAK BISA DIPILIH
-- [+] Custom Print function (\r\n)
-- ==========================================

-- [PENTING] PERINTAH SAKTI PERBAIKAN TERMINAL
-- Ini akan memaksa Termux kembali normal (mode cooked)
os.execute("stty sane") 

-- Paksa output keluar seketika (mencegah macet)
io.stdout:setvbuf("no")

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
-- FUNGSI DISPLAY AMAN (ANTI-TANGGA)
-- ==========================================

-- Fungsi print khusus yang memaksa baris baru + geser ke kiri
function cprint(str)
    str = str or ""
    io.write(str .. "\r\n")
    io.stdout:flush()
end

-- Fungsi input yang aman
function cinput(prompt)
    io.write(prompt)
    io.stdout:flush()
    return io.read()
end

function clearScreen()
    -- Gunakan perintah clear native linux, lebih aman daripada ANSI code
    os.execute("clear")
end

-- Override fungsi print bawaan lua agar aman
print = cprint

-- ==========================================
-- SYSTEM HELPERS
-- ==========================================

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
-- MONITORING LOOP (FIXED DISPLAY)
-- ==========================================
function startMonitoring()
    for i, pkg in ipairs(packages) do
        if not app_states[pkg.package] then
            app_states[pkg.package] = { startTime = os.time(), status = "Init" }
        end
    end
    
    local next_webhook_time = os.time() + 5 
    clearScreen()

    while true do
        local current_time = os.time()
        
        -- Reset Kursor ke pojok kiri atas
        io.write("\027[H") 
        
        cprint("========================================")
        cprint("     ZEEN TOOLS v5.4 (ULTIMATE)")
        cprint("========================================")
        cprint(string.format(" Monitor : %d Apps    |    Queue: 30s", #packages))
        if vip_link ~= "" then cprint(" VIP Link: ACTIVE (Direct Pkg)")
        else cprint(" VIP Link: -") end
        cprint("========================================")

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
            -- Print baris tabel dengan carriage return (\r)
            io.write(string.format("[%d] %-16s : %-20s\027[K\r\n", i, shortName, status_text))
            io.stdout:flush()
        end
        
        cprint("========================================")
        io.write(" CTRL+C to Stop & Exit to Shell ($)     \027[K\r\n")
        io.stdout:flush()
        
        if webhook_conf.url ~= "" and current_time >= next_webhook_time then
            io.write(" [Sending Webhook...]\027[K\r")
            io.stdout:flush()
            sendDiscordWebhook()
            next_webhook_time = current_time + webhook_conf.interval
        end
        
        local sleep_ok = os.execute("sleep " .. WATCHDOG_INTERVAL)
        if not sleep_ok then
            os.execute("stty sane") 
            os.exit()
        end
    end
end

-- ==========================================
-- MENU & CONFIG (FIXED INPUT)
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
        cprint("══ SETTINGS & EXTRAS ══")
        cprint("1. Set Delay Launch (Currently: " .. config.delay .. "s)")
        cprint("2. Set Private Server Link (VIP)")
        cprint("3. Set Discord Webhook")
        cprint("4. Kembali")
        
        local c = cinput("Pilih: ")
        
        if c == "1" then
            config.delay = tonumber(cinput("Delay (detik): ")) or 10
            saveAll()
        elseif c == "2" then
            cprint("Masukkan Link VIP (Kosongkan untuk hapus):")
            vip_link = cinput(">> ")
            saveAll()
        elseif c == "3" then
            cprint("1. Set URL")
            cprint("2. Set Interval (Detik)")
            local wc = cinput(">> ")
            if wc == "1" then 
                webhook_conf.url = cinput("Webhook URL: ")
            elseif wc == "2" then 
                webhook_conf.interval = tonumber(cinput("Interval (cth: 300): ")) or 300 
            end
            saveAll()
        elseif c == "4" then break end
    end
end

function autoDetectRoblox()
    clearScreen()
    cprint("══ AUTO-DETECT ROBLOX ══")
    local result = exec("pm list packages | grep 'roblox'")
    local detected = {}
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then table.insert(detected, pkg) end
    end
    if #detected == 0 then cprint("✗ Tidak ada Roblox."); cinput("Tekan Enter..."); return end
    
    cprint("✓ Ditemukan " .. #detected .. " packages. Ketik 'all' add.")
    if cinput("Pilihan: ") == "all" then
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
    cprint("══ LAUNCHING SEQUENCE ══")
    if #packages == 0 then cprint("✗ No packages!"); cinput("Enter..."); return end
    
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
    
    if cinput("Start Farming? (y/n): ") ~= "y" then return end
    
    app_states = {}
    local maxApps = #packages
    for i = 1, maxApps do
        local pkg = packages[i]
        cprint("[" .. i .. "] Launching " .. pkg.name .. "...")
        modifyUGClonerPrefs(pkg.package, i, maxApps)
        killAndStart(pkg.package, true)
        app_states[pkg.package] = { startTime = os.time(), status = "Launched" }
        if i < maxApps then os.execute("sleep " .. config.delay) end
    end
    
    startMonitoring()
end

function main()
    -- PENTING: Perintah ini memperbaiki input terminal yang rusak
    os.execute("stty sane") 
    
    getDeviceName()
    loadData()
    while true do
        clearScreen()
        cprint("ZEEN TOOLS v5.4 (ANTI-TANGGA FIX)")
        cprint("1. Start Auto Grid & Monitor")
        cprint("2. Detect Roblox")
        cprint("3. List Packages")
        cprint("4. Settings (VIP/Webhook)")
        cprint("5. Clear Data")
        cprint("6. Exit")
        
        local choice = cinput("Pilih: ")
        
        if choice == "1" then launchAutoGrid()
        elseif choice == "2" then autoDetectRoblox()
        elseif choice == "3" then 
            clearScreen()
            cprint("=== LIST PACKAGES ===")
            for i,p in ipairs(packages) do cprint(i..". "..p.name) end 
            cinput("\nTekan Enter kembali...")
        elseif choice == "4" then menuSettings()
        elseif choice == "5" then packages={}; saveAll(); cprint("Cleared."); cinput("Enter...")
        elseif choice == "6" then 
            os.execute("stty sane")
            break 
        end
    end
end

main()

