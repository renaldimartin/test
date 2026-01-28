#!/data/data/com.termux/files/usr/bin/lua

-- ==================================================
-- PROJECT ZEEN TOOLS v1.0.1 (MINOR UPDATE)
-- Auto Grid Freeform - Monitoring Edition
-- ==================================================
-- Changelog v1.0.1:
-- [✓] Tabel solid lines (tidak putus-putus) menggunakan box drawing chars
-- [✓] Monitoring cycling: 20 detik per app, lalu pindah ke app berikutnya (loop infinit)
-- [✓] UI smooth (no flicker) dengan double buffering
-- [✓] Username detection dengan cookie/session files
-- [✓] Display format: "Package Name (Username)"
-- ==================================================

-- KONFIGURASI
local STATUS_BAR_HEIGHT = 60
local REFRESH_RATE = 0.5 -- Detik (Kecepatan refresh UI)
local RAM_UPDATE_INTERVAL = 5 -- Update RAM tiap 5 detik
local MONITORING_DURATION = 20 -- Durasi monitoring per app (detik)

-- File paths
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

-- Data storage
local packages = {} -- Structure: {name, package, status, ram, real_user, state_step}
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 
local current_monitoring_index = 1
local loop_counter = 0
local monitoring_timer = 0

-- Warna ANSI
local C_RESET  = "\27[0m"
local C_RED    = "\27[31m"
local C_GREEN  = "\27[32m"
local C_YELLOW = "\27[33m"
local C_BLUE   = "\27[34m"
local C_CYAN   = "\27[36m"
local C_WHITE  = "\27[37m"
local C_BOLD   = "\27[1m"

-- Box Drawing Characters (Unicode untuk garis solid)
local BOX_H = "─"     -- Horizontal
local BOX_V = "│"     -- Vertical
local BOX_TL = "┌"    -- Top Left
local BOX_TR = "┐"    -- Top Right
local BOX_BL = "└"    -- Bottom Left
local BOX_BR = "┘"    -- Bottom Right
local BOX_T = "┬"     -- Top T
local BOX_B = "┴"     -- Bottom T
local BOX_L = "├"     -- Left T
local BOX_R = "┤"     -- Right T
local BOX_X = "┼"     -- Cross

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

-- [UPDATE v1.0.1] Detect Username dengan Cookie/Session Files
function getRobloxUsername(pkgName)
    -- Metode 1: Cek file cookies atau session
    local cookieCmd = "find /data/data/" .. pkgName .. " -type f \\( -name '*cookie*' -o -name '*session*' -o -name '*user*' -o -name '*.json' \\) 2>/dev/null | head -5"
    local cookieFiles = exec(cookieCmd)
    
    -- Parse cookie files untuk username/displayname
    if cookieFiles and cookieFiles ~= "" then
        for file in cookieFiles:gmatch("[^\r\n]+") do
            -- Cari username di dalam file
            local content = exec("cat '" .. file .. "' 2>/dev/null | head -100")
            
            -- Pattern matching untuk username di JSON atau format lain
            local username = content:match('"[Uu]sername":"([^"]+)"') or
                           content:match('"[Dd]isplayName":"([^"]+)"') or
                           content:match('"[Nn]ame":"([^"]+)"') or
                           content:match('"[Uu]ser":"([^"]+)"')
            
            if username and username ~= "" and not username:match("^%d+$") then
                return username
            end
        end
    end
    
    -- Metode 2: Cek shared_prefs XML (fallback dari v1.0.0)
    local cmd = "grep -r 'UserName\\|DisplayName\\|username\\|displayname' /data/data/" .. pkgName .. "/shared_prefs/ 2>/dev/null | head -3"
    local raw = exec(cmd)
    
    -- Parse XML value
    local user = raw:match('value="([^"]+)"') or 
                raw:match('>([^<]+)</string>') or
                raw:match('name="username">([^<]+)')
    
    if user and user ~= "" and not user:match("^%d+$") then
        return user
    end
    
    -- Metode 3: Cek database files
    local dbCmd = "find /data/data/" .. pkgName .. "/databases -type f -name '*.db' 2>/dev/null | head -1"
    local dbFile = exec(dbCmd)
    if dbFile and dbFile ~= "" then
        dbFile = dbFile:match("([^\r\n]+)")
        local dbQuery = "strings '" .. dbFile .. "' 2>/dev/null | grep -i 'username\\|displayname' | head -5"
        local dbResult = exec(dbQuery)
        
        for line in dbResult:gmatch("[^\r\n]+") do
            -- Ekstrak username dari hasil strings
            local name = line:match("([%w_]+)")
            if name and string.len(name) > 3 and string.len(name) < 25 and not name:match("^[0-9]+$") then
                return name
            end
        end
    end
    
    return "Unknown"
end

-- Get RAM Usage (MB)
function getRamUsage(pkgName)
    local cmd = "dumpsys meminfo " .. pkgName .. " | grep 'TOTAL PSS:'"
    local raw = exec(cmd)
    
    -- Try different patterns
    local kb = raw:match("TOTAL PSS:%s*(%d+)") or raw:match("TOTAL:%s*(%d+)")
    
    if not kb or kb == "" then
        -- Fallback: coba ambil baris TOTAL biasa
        cmd = "dumpsys meminfo " .. pkgName .. " | grep 'TOTAL' | head -1"
        raw = exec(cmd)
        kb = raw:match("%s*(%d+)%s*")
    end
    
    if kb then
        local mb = math.floor(tonumber(kb) / 1024)
        return mb .. " MB"
    else
        return "- MB"
    end
end

-- Optimize System
function optimizeSystem()
    exec("pm trim-caches 100M")
end

-- [LAYOUT] 1:2 Ratio Calculation
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
    
    if not prefFile then 
        prefFile = "/data/data/"..package.."/shared_prefs/com.roblox.clien"..cloneId.."_preferences.xml"
    end
    
    local cmds = {
        string.format("sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_left\\\" value=\\\"%d\\\"/' '%s'", pos.left, prefFile),
        string.format("sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_top\\\" value=\\\"%d\\\"/' '%s'", pos.top, prefFile),
        string.format("sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_right\\\" value=\\\"%d\\\"/' '%s'", pos.right, prefFile),
        string.format("sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_bottom\\\" value=\\\"%d\\\"/' '%s'", pos.bottom, prefFile),
    }
    for _, cmd in ipairs(cmds) do exec(cmd) end
end

-- ================= DASHBOARD UI v1.0.1 =================

-- [UPDATE v1.0.1] Double Buffer untuk menghindari flicker
local screen_buffer = {}

function clearBuffer()
    screen_buffer = {}
end

function addToBuffer(text)
    table.insert(screen_buffer, text)
end

function flushBuffer()
    -- Move cursor to home, lalu print semua sekaligus
    io.write("\27[H")
    io.write(table.concat(screen_buffer, "\n"))
    io.flush()
end

-- [UPDATE v1.0.1] Solid Table dengan box drawing characters
function drawDashboard()
    clearBuffer()
    
    -- Logo (tetap sama)
    addToBuffer(C_CYAN .. C_BOLD)
    addToBuffer("███████╗███████╗███████╗███╗   ██╗")
    addToBuffer("╚══███╔╝██╔════╝██╔════╝████╗  ██║")
    addToBuffer("  ███╔╝ █████╗  █████╗  ██╔██╗ ██║")
    addToBuffer(" ███╔╝  ██╔══╝  ██╔══╝  ██║╚██╗██║")
    addToBuffer("███████╗███████╗███████╗██║ ╚████║")
    addToBuffer("╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝")
    addToBuffer("        ZEEN TOOLS v1.0.1         ")
    addToBuffer(C_RESET)
    
    -- Table dengan garis solid
    local colWidths = {3, 30, 8, 12} -- No, Nama, RAM, Status
    local totalWidth = colWidths[1] + colWidths[2] + colWidths[3] + colWidths[4] + 7 -- +7 untuk borders
    
    -- Top border
    local topBorder = BOX_TL
    for i, w in ipairs(colWidths) do
        topBorder = topBorder .. string.rep(BOX_H, w + 2)
        if i < #colWidths then topBorder = topBorder .. BOX_T end
    end
    topBorder = topBorder .. BOX_TR
    addToBuffer(C_WHITE .. topBorder .. C_RESET)
    
    -- Header
    local header = string.format("%s %s%-3s%s %s %s%-30s%s %s %s%-8s%s %s %s%-12s%s %s",
        BOX_V, C_BOLD, "No", C_RESET,
        BOX_V, C_BOLD, "Nama", C_RESET,
        BOX_V, C_BOLD, "RAM", C_RESET,
        BOX_V, C_BOLD, "Status", C_RESET,
        BOX_V
    )
    addToBuffer(header)
    
    -- Middle border
    local midBorder = BOX_L
    for i, w in ipairs(colWidths) do
        midBorder = midBorder .. string.rep(BOX_H, w + 2)
        if i < #colWidths then midBorder = midBorder .. BOX_X end
    end
    midBorder = midBorder .. BOX_R
    addToBuffer(C_WHITE .. midBorder .. C_RESET)
    
    -- Data rows
    for i, pkg in ipairs(packages) do
        local statusColor = C_WHITE
        if pkg.status == "Reseting" then statusColor = C_RED
        elseif pkg.status == "Boosting" then statusColor = C_YELLOW
        elseif pkg.status == "Optimized" then statusColor = C_BLUE
        elseif pkg.status == "Launched" then statusColor = C_CYAN
        elseif pkg.status == "Online" then statusColor = C_GREEN
        elseif pkg.status == "Retrying" then statusColor = C_RED
        end
        
        -- [UPDATE v1.0.1] Format: "Package Name (Username)"
        local displayName = pkg.name
        if pkg.real_user and pkg.real_user ~= "Unknown" and pkg.real_user ~= "Scanning..." then
            displayName = pkg.name .. " (" .. pkg.real_user .. ")"
        end
        
        -- Truncate jika terlalu panjang
        if string.len(displayName) > 28 then 
            displayName = string.sub(displayName, 1, 27) .. "…" 
        end
        
        local row = string.format("%s %-3d %s %-30s %s %-8s %s %s%-12s%s %s",
            BOX_V, i,
            BOX_V, displayName,
            BOX_V, pkg.ram,
            BOX_V, statusColor, pkg.status, C_RESET,
            BOX_V
        )
        addToBuffer(row)
    end
    
    -- Bottom border
    local botBorder = BOX_BL
    for i, w in ipairs(colWidths) do
        botBorder = botBorder .. string.rep(BOX_H, w + 2)
        if i < #colWidths then botBorder = botBorder .. BOX_B end
    end
    botBorder = botBorder .. BOX_BR
    addToBuffer(C_WHITE .. botBorder .. C_RESET)
    
    -- [UPDATE v1.0.1] Status monitoring dengan timer countdown
    local timeLeft = MONITORING_DURATION - monitoring_timer
    addToBuffer("")
    addToBuffer(string.format("%sMonitoring:%s %d/%d | %sApp:%s %s | %sTime:%s %ds", 
        C_CYAN, C_RESET, current_monitoring_index, #packages,
        C_YELLOW, C_RESET, packages[current_monitoring_index] and packages[current_monitoring_index].name or "N/A",
        C_GREEN, C_RESET, math.max(0, timeLeft)
    ))
    addToBuffer("")
    addToBuffer(C_WHITE .. "[CTRL+C] Stop Script" .. C_RESET)
    
    -- Flush ke screen
    flushBuffer()
end

-- ================= APP STATE MACHINE =================

function processAppLogic(index, totalApps)
    local pkg = packages[index]
    if not pkg then return end
    
    if pkg.state_step == 0 then
        -- Step 0: Initialize
        pkg.status = "Reseting"
        exec("am force-stop " .. pkg.package)
        pkg.state_step = 1
        
    elseif pkg.state_step == 1 then
        -- Step 1: Clear Data
        pkg.status = "Reseting"
        exec("pm clear " .. pkg.package)
        pkg.state_step = 2
        
    elseif pkg.state_step == 2 then
        -- Step 2: Boosting
        pkg.status = "Boosting"
        exec("pm trim-caches 50M")
        pkg.state_step = 3
        
    elseif pkg.state_step == 3 then
        -- Step 3: Optimized
        pkg.status = "Optimized"
        optimizeSystem()
        pkg.state_step = 4
        
    elseif pkg.state_step == 4 then
        -- Step 4: Ready & Config
        pkg.status = "Ready"
        modifyPrefs(pkg.package, index, totalApps)
        pkg.state_step = 5
        
    elseif pkg.state_step == 5 then
        -- Step 5: Launching
        pkg.status = "Launched"
        exec("am start " .. pkg.package)
        pkg.state_step = 6
        pkg.wait_timer = 5
        
    elseif pkg.state_step == 6 then
        -- Step 6: Checking Online Status
        if pkg.wait_timer > 0 then
            pkg.wait_timer = pkg.wait_timer - 1
        else
            local check = exec("pidof " .. pkg.package)
            if check and check ~= "" then
                pkg.status = "Online"
                pkg.state_step = 7
                
                -- [UPDATE v1.0.1] Detect username setelah online
                if pkg.real_user == "Scanning..." or pkg.real_user == "Unknown" then
                    pkg.real_user = getRobloxUsername(pkg.package)
                end
            else
                pkg.status = "Retrying"
                pkg.state_step = 1
            end
        end
        
    elseif pkg.state_step == 7 then
        -- Step 7: Maintenance - Sudah Online
        local check = exec("pidof " .. pkg.package)
        if not check or check == "" then
            pkg.status = "Retrying"
            pkg.state_step = 1
        else
            pkg.status = "Online"
        end
    end
end

-- ================= MAIN MONITORING LOOP v1.0.1 =================

function startMonitoring()
    if #packages == 0 then print("✗ No packages!"); return end
    
    -- Inisialisasi
    for i, p in ipairs(packages) do
        p.status = "Waiting"
        p.ram = "- MB"
        p.real_user = "Scanning..."
        p.state_step = 0
        p.wait_timer = 0
    end
    
    current_monitoring_index = 1
    monitoring_timer = 0
    updateScreenResolution()
    
    -- Clear screen sekali di awal (untuk menghindari flicker)
    io.write("\27[2J")
    
    -- LOOP UTAMA
    while true do
        loop_counter = loop_counter + 1
        monitoring_timer = monitoring_timer + 1
        
        -- [UPDATE v1.0.1] Sistem cycling: 20 detik per app
        if monitoring_timer >= (MONITORING_DURATION / REFRESH_RATE) then
            monitoring_timer = 0
            
            -- Pindah ke app berikutnya
            current_monitoring_index = current_monitoring_index + 1
            if current_monitoring_index > #packages then
                current_monitoring_index = 1 -- Loop kembali ke awal
            end
        end
        
        -- Proses app yang sedang di-monitor
        if current_monitoring_index <= #packages then
            processAppLogic(current_monitoring_index, #packages)
        end
        
        -- Maintenance check untuk app yang sudah Online (background check)
        if loop_counter % 10 == 0 then
            for i = 1, #packages do
                if i ~= current_monitoring_index and packages[i].state_step == 7 then
                    processAppLogic(i, #packages)
                end
            end
        end
        
        -- Update RAM (tidak setiap frame)
        if loop_counter % (RAM_UPDATE_INTERVAL * 2) == 0 then
            for i, p in ipairs(packages) do
                if p.state_step >= 5 then
                    p.ram = getRamUsage(p.package)
                end
            end
        end
        
        -- Update Username scanning (setiap 30 detik)
        if loop_counter % 60 == 0 then
            for i, p in ipairs(packages) do
                if (p.real_user == "Scanning..." or p.real_user == "Unknown") and p.state_step >= 6 then
                    p.real_user = getRobloxUsername(p.package)
                end
            end
        end
        
        -- Draw UI (smooth, no clear screen)
        drawDashboard()
        
        -- Sleep
        os.execute("sleep " .. REFRESH_RATE)
    end
end

-- ================= BOILERPLATE =================

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
                    status = "Idle",
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
    print("\nScanning...")
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
        print(C_CYAN .. C_BOLD .. "ZEEN TOOLS v1.0.1" .. C_RESET)
        print("1. START MONITORING & LAUNCH")
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
