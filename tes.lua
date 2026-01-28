#!/data/data/com.termux/files/usr/bin/lua

-- ==================================================
-- PROJECT ZEEN TOOLS v1.0.1 (HOTFIX)
-- Auto Grid Freeform - Monitoring Edition
-- ==================================================
-- Changelog:
-- [FIX] Error bad argument #3 on Dashboard
-- [+] UI: Solid Table (Box Drawing)
-- [+] Optimization: Anti-Flicker Display
-- [+] Logic: Cyclic Monitoring (15s per App Loop)
-- ==================================================

-- KONFIGURASI
local STATUS_BAR_HEIGHT = 60
local MONITOR_SWITCH_TIME = 15 -- Detik (Waktu ganti fokus monitoring)
local REFRESH_RATE = 0.2       -- Detik (Update UI lebih cepat & smooth)
local RAM_UPDATE_INTERVAL = 20 -- Update RAM tiap 20 refresh

-- File paths
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

-- Data storage
local packages = {} 
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 

-- Monitoring Variables
local current_monitoring_index = 1
local monitor_timer = 0        -- Timer hitung mundur pindah app
local loop_counter = 0

-- Warna ANSI
local C_RESET  = "\27[0m"
local C_RED    = "\27[31m"
local C_GREEN  = "\27[32m"
local C_YELLOW = "\27[33m"
local C_BLUE   = "\27[34m"
local C_CYAN   = "\27[36m"
local C_WHITE  = "\27[37m"
local C_BOLD   = "\27[1m"
local C_DIM    = "\27[2m"

-- ================= HELPER FUNCTIONS =================

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
    if rf then result = rf:read("*a"); rf:close() end
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
        if getOrientation() == "landscape" then
            if w < h then DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w else DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h end
        else
            if w > h then DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w else DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h end
        end
    end
end

-- ================= CORE LOGIC v1.0.1 =================

-- [IMPROVED] Deep Search Username
function getRobloxUsername(pkgName)
    local cmd = "grep -r \"DisplayName\" /data/data/" .. pkgName .. "/shared_prefs/ | head -n 1"
    local raw = exec(cmd)
    
    local user = raw:match("DisplayName\"[^>]*>([^<]+)<") 
    if not user then user = raw:match("value=\"([^\"]+)\"") end

    if not user or user == "" then
        cmd = "grep -r \"UserName\" /data/data/" .. pkgName .. "/shared_prefs/ | head -n 1"
        raw = exec(cmd)
        user = raw:match("UserName\"[^>]*>([^<]+)<")
        if not user then user = raw:match("value=\"([^\"]+)\"") end
    end
    
    return (user and user ~= "") and user or "Unknown"
end

function getRamUsage(pkgName)
    local raw = exec("dumpsys meminfo " .. pkgName .. " | grep 'TOTAL'")
    local kb = raw:match("%s*(%d+)%s*")
    return kb and (math.floor(tonumber(kb) / 1024) .. " MB") or "0 MB"
end

function optimizeSystem()
    exec("pm trim-caches 100M")
end

-- LAYOUT 1:2
function getGridPositions(numApps)
    local usable_height = DISPLAY_HEIGHT - STATUS_BAR_HEIGHT
    local h_slot = math.floor(usable_height / 3)
    local grid_width = math.floor(DISPLAY_WIDTH * (2/3))
    local start_x = DISPLAY_WIDTH - grid_width
    local w_slot = math.floor(grid_width / 2)
    local y1, y2, y3 = STATUS_BAR_HEIGHT, STATUS_BAR_HEIGHT + h_slot, STATUS_BAR_HEIGHT + (h_slot*2)
    local b1, b2, b3 = y1 + h_slot, y2 + h_slot, DISPLAY_HEIGHT 
    
    return {
        {name="R1 L", left=start_x, top=y1, right=start_x+w_slot, bottom=b1},
        {name="R1 R", left=start_x+w_slot, top=y1, right=DISPLAY_WIDTH, bottom=b1},
        {name="R2 L", left=start_x, top=y2, right=start_x+w_slot, bottom=b2},
        {name="R2 R", left=start_x+w_slot, top=y2, right=DISPLAY_WIDTH, bottom=b2},
        {name="R3 L", left=start_x, top=y3, right=start_x+w_slot, bottom=b3},
        {name="R3 R", left=start_x+w_slot, top=y3, right=DISPLAY_WIDTH, bottom=b3},
    }
end

function modifyPrefs(package, position, numApps)
    local grid = getGridPositions(numApps)
    local pos = grid[position]
    if not pos then return end
    local cloneId = package:match("clien([%w]+)$") or "z1"
    local findCmd = "ls /data/data/" .. package .. "/shared_prefs/*.xml 2>/dev/null | grep -i pref"
    local foundFiles = exec(findCmd)
    local prefFile = foundFiles:match("([^\n]+_preferences%.xml)") or foundFiles:match("([^\n]+)")
    if not prefFile then prefFile = "/data/data/"..package.."/shared_prefs/com.roblox.clien"..cloneId.."_preferences.xml" end
    
    local cmds = {
        string.format("sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_left\\\" value=\\\"%d\\\"/' '%s'", pos.left, prefFile),
        string.format("sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_top\\\" value=\\\"%d\\\"/' '%s'", pos.top, prefFile),
        string.format("sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_right\\\" value=\\\"%d\\\"/' '%s'", pos.right, prefFile),
        string.format("sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_bottom\\\" value=\\\"%d\\\"/' '%s'", pos.bottom, prefFile),
    }
    for _, cmd in ipairs(cmds) do exec(cmd) end
end

-- ================= BUFFERED UI (ANTI-FLICKER) =================

function drawDashboard()
    -- Gunakan buffer string untuk menampung semua text
    local buffer = "\27[H" 
    
    buffer = buffer .. C_CYAN .. C_BOLD .. "\n"
    buffer = buffer .. "  ZEEN TOOLS v1.0.1 (Stable)     \n"
    buffer = buffer .. C_RESET .. "\n"
    
    -- Header Solid Table
    buffer = buffer .. C_WHITE .. "┌────┬──────────────────┬──────────┬──────────────┐\n" .. C_RESET
    buffer = buffer .. string.format("│ %s%-2s%s │ %-16s │ %-8s │ %-12s │\n", C_BOLD, "No", C_RESET, "Nama Akun", "RAM", "Status")
    buffer = buffer .. C_WHITE .. "├────┼──────────────────┼──────────┼──────────────┤\n" .. C_RESET
    
    -- Rows
    for i, pkg in ipairs(packages) do
        local statusColor = C_WHITE
        if pkg.status == "Online" or pkg.status == "Ready" then statusColor = C_GREEN
        elseif pkg.status == "Retrying" then statusColor = C_RED end
        
        -- Indikator Panah
        local indicator = (i == current_monitoring_index) and (C_CYAN .. ">" .. C_RESET) or " "
        
        local displayName = pkg.real_user
        if string.len(displayName) > 14 then displayName = string.sub(displayName, 1, 13) .. "." end
        
        -- [FIXED LINE] Memisahkan indicator (string) dan i (number)
        buffer = buffer .. string.format("│ %s%-2d │ %-16s │ %-8s │ %s%-12s%s │\n", 
            indicator, i, displayName, pkg.ram, statusColor, pkg.status, C_RESET
        )
    end
    
    -- Footer Solid Table
    buffer = buffer .. C_WHITE .. "└────┴──────────────────┴──────────┴──────────────┘\n" .. C_RESET
    
    -- Info Bar Realtime
    local activePkg = packages[current_monitoring_index] or {}
    local progressText = activePkg.status or "Idle"
    local timeLeft = math.ceil(MONITOR_SWITCH_TIME - monitor_timer)
    
    buffer = buffer .. string.format("\n%sMonitoring: %d/%d (%s) %s| %sNext Switch: %ds   %s\n", 
        C_BOLD, current_monitoring_index, #packages, progressText, C_RESET, 
        C_YELLOW, timeLeft, C_RESET
    )
    
    buffer = buffer .. C_DIM .. "\n[CTRL+C] Stop Script    " .. C_RESET 
    
    -- Print Buffer Sekaligus
    io.write(buffer)
end

-- ================= STATE MACHINE & LOGIC =================

function processAppLogic(index, totalApps)
    local pkg = packages[index]
    
    if pkg.state_step == 0 then
        pkg.status = "Reseting"
        pkg.state_step = 1
        
    elseif pkg.state_step == 1 then
        pkg.status = "Reseting"
        exec("am force-stop " .. pkg.package)
        if pkg.real_user == "Scanning..." or pkg.real_user == "Unknown" then 
            pkg.real_user = getRobloxUsername(pkg.package) 
        end
        pkg.state_step = 2
        
    elseif pkg.state_step == 2 then
        pkg.status = "Boosting"
        exec("pm trim-caches 50M") 
        pkg.state_step = 3
        
    elseif pkg.state_step == 3 then
        pkg.status = "Optimized"
        optimizeSystem() 
        pkg.state_step = 4
        
    elseif pkg.state_step == 4 then
        pkg.status = "Ready"
        modifyPrefs(pkg.package, index, totalApps)
        pkg.state_step = 5
        pkg.wait_timer = 1
        
    elseif pkg.state_step == 5 then
        if pkg.wait_timer > 0 then
            pkg.wait_timer = pkg.wait_timer - REFRESH_RATE
        else
            pkg.status = "Launched"
            exec("am start " .. pkg.package)
            pkg.state_step = 6
            pkg.wait_timer = 6 -- Waktu tunggu loading
        end
        
    elseif pkg.state_step == 6 then
        if pkg.wait_timer > 0 then
            pkg.wait_timer = pkg.wait_timer - REFRESH_RATE
        else
            local check = exec("pidof " .. pkg.package)
            if check and check ~= "" then
                pkg.status = "Online"
            else
                pkg.status = "Retrying"
                pkg.state_step = 1 
            end
        end
        
    elseif pkg.state_step == 7 or pkg.status == "Online" then
        -- Maintenance Mode
        local check = exec("pidof " .. pkg.package)
        if not check or check == "" then
            pkg.status = "Retrying"
            pkg.state_step = 1 
        else
            pkg.status = "Online"
        end
    end
end

-- ================= MAIN LOOP =================

function startMonitoring()
    if #packages == 0 then print("✗ No packages!"); return end
    
    io.write("\27[2J") 
    
    -- Init Data
    for i, p in ipairs(packages) do
        p.status = "Waiting"
        p.ram = "0 MB"
        p.real_user = "Scanning..."
        p.state_step = 0
        p.wait_timer = 0
    end
    
    current_monitoring_index = 1
    monitor_timer = 0
    updateScreenResolution()
    
    while true do
        loop_counter = loop_counter + 1
        
        -- 1. PROSES MONITORING
        if current_monitoring_index <= #packages then
            processAppLogic(current_monitoring_index, #packages)
        end
        
        -- 2. BACKGROUND CHECK
        local random_idx = math.random(1, #packages)
        if random_idx ~= current_monitoring_index then
             local pkg = packages[random_idx]
             if pkg.status == "Online" then
                 local check = exec("pidof " .. pkg.package)
                 if not check or check == "" then pkg.status = "Retrying"; pkg.state_step = 1 end
             end
        end
        
        -- 3. CYCLIC LOGIC
        monitor_timer = monitor_timer + REFRESH_RATE
        if monitor_timer >= MONITOR_SWITCH_TIME then
            monitor_timer = 0
            current_monitoring_index = current_monitoring_index + 1
            if current_monitoring_index > #packages then
                current_monitoring_index = 1 -- Loop kembali ke 1
            end
        end
        
        -- 4. UPDATE RAM
        if loop_counter % RAM_UPDATE_INTERVAL == 0 then
            for i, p in ipairs(packages) do
                if p.state_step >= 5 then p.ram = getRamUsage(p.package) end
            end
        end
        
        -- 5. DRAW UI
        drawDashboard()
        
        -- 6. DELAY
        local start = os.clock()
        while os.clock() - start < REFRESH_RATE do end
    end
end

-- ================= MENU =================

function loadPackages()
    local file = io.open(PACKAGE_FILE, "r")
    if file then
        packages = {}
        for line in file:lines() do
            local name, package = line:match("(.+)|(.+)")
            if name and package then 
                table.insert(packages, {
                    name = name, 
                    package = package,
                    status = "Waiting",
                    ram = "-",
                    real_user = "Unknown",
                    state_step = 0
                }) 
            end
        end
        file:close()
    end
end

function savePackages()
    local file = io.open(PACKAGE_FILE, "w")
    if file then
        for _, pkg in ipairs(packages) do file:write(pkg.name .. "|" .. pkg.package .. "\n") end
        file:close()
    end
end

function autoDetectRoblox()
    io.write("\27[2J\27[H")
    print("Scanning Packages...")
    local res = exec("pm list packages | grep 'roblox'")
    local detected = {}
    for line in res:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then table.insert(detected, pkg) end
    end
    if #detected > 0 then
        print("Found " .. #detected .. ". Add all? (y/n)")
        if io.read() == "y" then
            for _, pkg in ipairs(detected) do
                local exists = false
                for _, p in ipairs(packages) do if p.package == pkg then exists = true end end
                if not exists then
                    local name = pkg:match("com%.roblox%.(.+)") or pkg
                    name = name:gsub("%.", " "):gsub("^%l", string.upper)
                    table.insert(packages, {name = "Roblox "..name, package = pkg})
                end
            end
            savePackages()
            print("Saved.")
        end
    else
        print("No Roblox found.")
    end
end

function main()
    io.stdout:setvbuf("no")
    loadPackages()
    while true do
        io.write("\27[2J\27[H")
        print("ZEEN TOOLS v1.0.1")
        print("1. START MONITORING (Cyclic Mode)")
        print("2. Detect Packages")
        print("3. Reset Data")
        print("4. Exit")
        io.write("Select: ")
        local c = io.read()
        if c == "1" then startMonitoring()
        elseif c == "2" then autoDetectRoblox(); io.read()
        elseif c == "3" then packages={}; savePackages(); print("Reset!"); io.read()
        elseif c == "4" then break 
        end
    end
end

main()

