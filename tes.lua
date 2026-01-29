#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v4.5 (MONITOR EDITION)
-- Auto Grid Freeform - UG Cloner Edition
-- ==========================================
-- Update v4.5:
-- [+] FITUR MONITORING DASHBOARD
-- [+] Auto Restart jika Crash/FC (Tanpa Reset Grid)
-- [+] RAM Status Indicator
-- [+] Status: Launched > 60s -> Online
-- ==========================================

-- KONFIGURASI MONITOR
local WATCHDOG_INTERVAL = 20 -- Detik (Interval cek)
local STABLE_TIME = 60       -- Waktu (detik) dianggap "Online" stabil

-- KONFIGURASI UMUM
local STATUS_BAR_HEIGHT = 60
local DEFAULT_DELAY = 10

-- File paths
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local CONFIG_FILE = "/data/data/com.termux/files/home/.zeen_config.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

-- Data storage
local packages = {}
local app_states = {} -- Menyimpan status & waktu start
local config = { delay = DEFAULT_DELAY }
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 

-- ==========================================
-- SYSTEM FUNCTIONS
-- ==========================================

function exec(cmd)
    local f = io.open(TEMP_SCRIPT, "w")
    if not f then return "" end
    f:write("#!/system/bin/sh\n")
    f:write(cmd .. "\n")
    f:close()
    
    os.execute("chmod +x " .. TEMP_SCRIPT)
    local output_file = "/data/data/com.termux/files/home/.temp_output.txt"
    os.execute("su -c '" .. TEMP_SCRIPT .. " > " .. output_file .. " 2>&1'")
    
    local result = ""
    local rf = io.open(output_file, "r")
    if rf then
        result = rf:read("*a")
        rf:close()
    end
    
    os.remove(TEMP_SCRIPT)
    os.remove(output_file)
    return result
end

function getOrientation()
    local result = exec("dumpsys window | grep 'mCurrentRotation'")
    if result:match("ROTATION_90") or result:match("ROTATION_270") then return "landscape" else return "portrait" end
end

function updateScreenResolution()
    local result = exec("wm size")
    local w, h = result:match("Physical size: (%d+)x(%d+)")
    if w and h then
        w, h = tonumber(w), tonumber(h)
        local ori = getOrientation()
        if ori == "landscape" then
            if w < h then DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w else DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h end
        else
            if w > h then DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w else DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h end
        end
    end
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
-- MONITORING LOGIC
-- ==========================================

function getFreeRAM()
    -- Mengambil data MemAvailable dari /proc/meminfo
    local res = exec("cat /proc/meminfo | grep MemAvailable")
    local kb = res:match("(%d+)")
    if kb then
        local gb = tonumber(kb) / 1024 / 1024
        return string.format("%.1fGB Free", gb)
    end
    return "Unknown"
end

function isAppRunning(package)
    -- Cek PID, jika ada return true
    local pid = exec("pidof " .. package):gsub("%s+", "")
    return pid ~= ""
end

function startMonitoring()
    -- Setup awal state
    for i, pkg in ipairs(packages) do
        -- Jika belum ada di state, masukkan
        if not app_states[pkg.package] then
            app_states[pkg.package] = {
                startTime = os.time(),
                status = "Launched"
            }
        end
    end

    while true do
        -- 1. Bersihkan Layar (Clear Screen ANSI code)
        print("\027[H\027[2J")
        
        -- 2. Cek Status Tiap App
        local active_count = 0
        local ram_info = getFreeRAM()
        
        -- Header Dashboard
        print("========================================")
        print("     ZEEN MONITOR - LIVE DASHBOARD")
        print("========================================")
        print("")
        print(string.format("Monitoring : %d/%d       |  RAM: %s", #packages, #packages, ram_info))
        print("========================================")

        for i, pkg in ipairs(packages) do
            local state = app_states[pkg.package]
            local is_running = isAppRunning(pkg.package)
            local display_status = "Unknown"
            
            if is_running then
                active_count = active_count + 1
                -- Hitung durasi hidup
                local duration = os.time() - state.startTime
                
                if duration < STABLE_TIME then
                    display_status = "Launched"
                else
                    display_status = "Online"
                end
                
                -- Update state internal
                state.status = display_status
            else
                -- APP MATI / CRASH
                display_status = "Retrying"
                state.status = "Retrying"
                
                -- Aksi Restart (Tanpa Modify Grid)
                exec("am force-stop " .. pkg.package)
                exec("am start " .. pkg.package)
                
                -- Reset timer
                state.startTime = os.time()
            end
            
            -- Format Print Dashboard: [1] Nama : Status
            -- Memotong nama paket agar tidak kepanjangan di dashboard
            local shortName = pkg.name:sub(1, 15)
            print(string.format("[%d] %-16s : %s", i, shortName, display_status))
        end
        
        print("========================================")
        print("Tekan CTRL+C untuk stop monitoring.")
        
        -- Delay Refresh
        os.execute("sleep " .. WATCHDOG_INTERVAL)
    end
end

-- ==========================================
-- CORE FUNCTIONS
-- ==========================================

function loadConfig()
    local f = io.open(CONFIG_FILE, "r")
    if f then
        for line in f:lines() do
            local key, val = line:match("(%w+)=(%d+)")
            if key and val then config[key] = tonumber(val) end
        end
        f:close()
    end
end

function saveConfig()
    local f = io.open(CONFIG_FILE, "w")
    if f then f:write("delay=" .. config.delay .. "\n"); f:close(); return true end; return false
end

function savePackages()
    local file = io.open(PACKAGE_FILE, "w")
    if file then
        for _, pkg in ipairs(packages) do file:write(pkg.name .. "|" .. pkg.package .. "\n") end
        file:close()
        return true
    end
    return false
end

function loadPackages()
    local file = io.open(PACKAGE_FILE, "r")
    if file then
        packages = {}
        for line in file:lines() do
            local name, package = line:match("(.+)|(.+)")
            if name and package then table.insert(packages, {name = name, package = package}) end
        end
        file:close()
    end
end

function showSettings()
    while true do
        print("\n══ SETTINGS ══")
        print("Current Delay: " .. config.delay .. " seconds")
        print("1. Ubah Delay Launch")
        print("2. Kembali")
        io.write("Pilih: ")
        local choice = io.read()
        if choice == "1" then
            io.write("Delay baru (detik): ")
            local newDelay = tonumber(io.read())
            if newDelay and newDelay > 0 then config.delay = newDelay; saveConfig() end
        elseif choice == "2" then break end
    end
end

function autoDetectRoblox()
    print("\n══ AUTO-DETECT ROBLOX ══")
    local result = exec("pm list packages | grep 'roblox'")
    local detected = {}
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then table.insert(detected, pkg) end
    end
    if #detected == 0 then print("✗ Tidak ada Roblox."); io.read(); return end
    print("✓ Ditemukan " .. #detected .. " packages. Ketik 'all' add.")
    io.write("Pilihan: ")
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
        savePackages()
    end
end

function launchAutoGrid()
    print("\n══ AUTO GRID LAUNCH (MONITOR) ══")
    if #packages == 0 then print("✗ No packages!"); return end
    updateScreenResolution()
    
    print("ℹ Mode: Left Side 2:1 | Monitor: ON")
    io.write("Lanjutkan? (y/n): ")
    if io.read() ~= "y" then return end
    
    -- Inisialisasi state untuk monitoring
    app_states = {}
    
    local maxApps = #packages
    for i = 1, maxApps do
        local pkg = packages[i]
        print("\n[" .. i .. "/" .. maxApps .. "] " .. pkg.name)
        
        exec("am force-stop " .. pkg.package)
        os.execute("sleep 0.5") 
        
        -- Modify Grid HANYA saat Launch awal
        modifyUGClonerPrefs(pkg.package, i, maxApps)
        
        exec("am start " .. pkg.package)
        
        -- Simpan waktu start
        app_states[pkg.package] = {
            startTime = os.time(),
            status = "Launched"
        }
        
        if i < maxApps then
            print("⏳ Waiting " .. config.delay .. "s...")
            os.execute("sleep " .. config.delay)
        end
    end
    
    print("\n✓ Launch selesai. Memulai Monitoring Dashboard...")
    os.execute("sleep 2")
    startMonitoring() -- Masuk ke Loop Dashboard
end

function showMenu()
    print("\nZEEN TOOLS v4.5 (MONITOR)")
    print("1. Auto Grid & Monitor")
    print("2. Detect Roblox")
    print("3. List Packages")
    print("4. Settings")
    print("5. Clear Data")
    print("6. Exit")
    io.write("Pilih: ")
    return io.read()
end

function main()
    io.stdout:setvbuf("no")
    loadPackages()
    loadConfig() 
    updateScreenResolution()
    while true do
        local choice = showMenu()
        if choice == "1" then launchAutoGrid()
        elseif choice == "2" then autoDetectRoblox()
        elseif choice == "3" then for i,p in ipairs(packages) do print(i..". "..p.name) end 
        elseif choice == "4" then showSettings()
        elseif choice == "5" then packages={}; savePackages(); print("Cleared.")
        elseif choice == "6" then break 
        end
    end
end

main()

