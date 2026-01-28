#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v4.1 (WIDE EDITION)
-- Auto Grid Freeform - UG Cloner Edition
-- ==========================================
-- Update v4.1:
-- [+] Logic 1:3 Screen Split (Lebih Lebar)
--     (25% Kiri Kosong, 75% Kanan Isi App)
-- [+] Auto Detect Resolution
-- ==========================================

print("================================")
print("  ZEEN TOOLS v4.1 (WIDE)")
print("  Mode: 1:3 Split Ratio")
print("================================")
print()

-- File paths
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

-- Data storage
local packages = {}
local active_tasks = {}
local DISPLAY_WIDTH = 1280 -- Default fallback
local DISPLAY_HEIGHT = 720 -- Default fallback

-- Execute root command via temp script file
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

-- Detect orientation
function getOrientation()
    local result = exec("dumpsys window | grep 'mCurrentRotation'")
    if result:match("ROTATION_90") or result:match("ROTATION_270") then
        return "landscape"
    else
        return "portrait"
    end
end

-- Auto Detect Real Screen Resolution
function updateScreenResolution()
    local result = exec("wm size")
    local w, h = result:match("Physical size: (%d+)x(%d+)")
    
    if w and h then
        w = tonumber(w)
        h = tonumber(h)
        local ori = getOrientation()
        
        -- Adjust width/height based on orientation
        if ori == "landscape" then
            if w < h then 
                DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w
            else
                DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h
            end
        else
            if w > h then
                DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w
            else
                DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h
            end
        end
        print("✓ Screen Detected: " .. DISPLAY_WIDTH .. "x" .. DISPLAY_HEIGHT .. " (" .. ori:upper() .. ")")
    else
        print("⚠ Gagal deteksi layar, menggunakan default: 1280x720")
    end
end

-- Determine layout type based on number of apps
function getLayoutType(numApps)
    if numApps <= 4 then
        return "2x2 Full"
    elseif numApps <= 6 then
        return "Right Side Wide (1:3 Split)" -- Mode Baru 1:3
    else
        return "2x4 Full"
    end
end

-- Get grid positions
function getGridPositions(numApps)
    local layoutType = getLayoutType(numApps)
    
    if layoutType == "2x2 Full" then
        local w = math.floor(DISPLAY_WIDTH / 2)
        local h = math.floor(DISPLAY_HEIGHT / 2)
        return {
            {name="Top Left",     left=0, top=0,   right=w,             bottom=h},
            {name="Top Right",    left=w, top=0,   right=DISPLAY_WIDTH, bottom=h},
            {name="Bottom Left",  left=0, top=h,   right=w,             bottom=DISPLAY_HEIGHT},
            {name="Bottom Right", left=w, top=h,   right=DISPLAY_WIDTH, bottom=DISPLAY_HEIGHT},
        }

    elseif layoutType == "Right Side Wide (1:3 Split)" then
        -- LOGIKA 1:3 SPLIT (WIDE MODE)
        -- Layar dibagi 4 bagian secara vertikal (kolom imajiner)
        -- 1 Bagian Kiri = Kosong (25%)
        -- 3 Bagian Kanan = Area App (75%)
        
        local grid_width = math.floor(DISPLAY_WIDTH * 0.75) -- Ambil 75% lebar layar
        local start_x = DISPLAY_WIDTH - grid_width          -- Mulai dari titik 25%
        
        local w_slot = math.floor(grid_width / 2)           -- Lebar per window
        local h_slot = math.floor(DISPLAY_HEIGHT / 3)       -- Tinggi per window (tetap bagi 3)
        
        return {
            -- Baris 1
            {name="R1 Left",  left=start_x,        top=0,          right=start_x+w_slot,   bottom=h_slot},
            {name="R1 Right", left=start_x+w_slot, top=0,          right=DISPLAY_WIDTH,    bottom=h_slot},
            -- Baris 2
            {name="R2 Left",  left=start_x,        top=h_slot,     right=start_x+w_slot,   bottom=h_slot*2},
            {name="R2 Right", left=start_x+w_slot, top=h_slot,     right=DISPLAY_WIDTH,    bottom=h_slot*2},
            -- Baris 3
            {name="R3 Left",  left=start_x,        top=h_slot*2,   right=start_x+w_slot,   bottom=DISPLAY_HEIGHT},
            {name="R3 Right", left=start_x+w_slot, top=h_slot*2,   right=DISPLAY_WIDTH,    bottom=DISPLAY_HEIGHT},
        }

    else -- 2x4 Fallback
        local h = math.floor(DISPLAY_HEIGHT / 4)
        local w = h * 2  -- 1:2 ratio
        return {
            {name="Row 1 L", left=0, top=0,     right=w,             bottom=h},
            {name="Row 1 R", left=w, top=0,     right=DISPLAY_WIDTH, bottom=h},
            {name="Row 2 L", left=0, top=h,     right=w,             bottom=h*2},
            {name="Row 2 R", left=w, top=h,     right=DISPLAY_WIDTH, bottom=h*2},
            {name="Row 3 L", left=0, top=h*2,   right=w,             bottom=h*3},
            {name="Row 3 R", left=w, top=h*2,   right=DISPLAY_WIDTH, bottom=h*3},
            {name="Row 4 L", left=0, top=h*3,   right=w,             bottom=DISPLAY_HEIGHT},
            {name="Row 4 R", left=w, top=h*3,   right=DISPLAY_WIDTH, bottom=DISPLAY_HEIGHT},
        }
    end
end

-- Modify UG Cloner XML preferences
function modifyUGClonerPrefs(package, position, numApps)
    local grid_positions = getGridPositions(numApps)
    local pos = grid_positions[position]
    
    if not pos then
        print("✗ Invalid position!")
        return false
    end
    
    -- Detect clone identifier
    local cloneId = package:match("clien([%w]+)$") or "z1"
    
    -- Find File Logic
    local findCmd = string.format("ls /data/data/%s/shared_prefs/*.xml 2>/dev/null | grep -i pref", package)
    local foundFiles = exec(findCmd)
    local prefFile = ""
    
    if foundFiles and foundFiles ~= "" then
        prefFile = foundFiles:match("([^\n]+_preferences%.xml)")
        if not prefFile then prefFile = foundFiles:match("([^\n]+)") end
    else
        prefFile = string.format("/data/data/%s/shared_prefs/com.roblox.clien%s_preferences.xml", package, cloneId)
        if not exec("test -f " .. prefFile .. " && echo 'yes'"):match("yes") then
            print("✗ Prefs file not found for " .. package)
            return false
        end
    end

    print("→ Posisi " .. pos.name .. ": (" .. pos.left .. "," .. pos.top .. ")")
    
    -- Edit XML
    local commands = {
        string.format("sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_left\\\" value=\\\"%d\\\"/' '%s'", pos.left, prefFile),
        string.format("sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_top\\\" value=\\\"%d\\\"/' '%s'", pos.top, prefFile),
        string.format("sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_right\\\" value=\\\"%d\\\"/' '%s'", pos.right, prefFile),
        string.format("sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_bottom\\\" value=\\\"%d\\\"/' '%s'", pos.bottom, prefFile),
    }
    
    for _, cmd in ipairs(commands) do exec(cmd) end
    
    return true
end

-- Save packages
function savePackages()
    local file = io.open(PACKAGE_FILE, "w")
    if file then
        for _, pkg in ipairs(packages) do
            file:write(pkg.name .. "|" .. pkg.package .. "\n")
        end
        file:close()
        return true
    end
    return false
end

-- Load packages
function loadPackages()
    local file = io.open(PACKAGE_FILE, "r")
    if file then
        packages = {}
        for line in file:lines() do
            local name, package = line:match("(.+)|(.+)")
            if name and package then
                table.insert(packages, {name = name, package = package})
            end
        end
        file:close()
    end
end

-- Auto-detect Roblox
function autoDetectRoblox()
    print("\n══ AUTO-DETECT ROBLOX ══")
    print("→ Scanning packages...")
    local result = exec("pm list packages | grep 'roblox'")
    
    local detected = {}
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then table.insert(detected, pkg) end
    end
    
    if #detected == 0 then
        print("✗ Tidak ada Roblox ditemukan.")
        io.read()
        return
    end
    
    print("✓ Ditemukan " .. #detected .. " packages.")
    print("Ketik 'all' untuk add semua, atau '0' batal.")
    io.write("Pilihan: ")
    local choice = io.read()
    
    if choice == "all" then
        for _, pkg in ipairs(detected) do
            local exists = false
            for _, p in ipairs(packages) do if p.package == pkg then exists = true end end
            
            if not exists then
                local name = pkg:match("com%.roblox%.(.+)") or pkg
                name = name:gsub("%.", " "):gsub("^%l", string.upper)
                table.insert(packages, {name = "Roblox " .. name, package = pkg})
                print("  + " .. name)
            end
        end
        savePackages()
    end
end

-- Launch Loop
function launchAutoGrid()
    print("\n══ AUTO GRID LAUNCH ══")
    if #packages == 0 then print("✗ No packages!"); return end
    
    updateScreenResolution()
    
    local numApps = #packages
    local layoutType = getLayoutType(numApps)
    local maxApps = math.min(8, numApps)
    
    print("Screen: " .. DISPLAY_WIDTH .. "x" .. DISPLAY_HEIGHT)
    print("Layout Mode: " .. layoutType)
    
    if layoutType:match("1:3 Split") then
        print("ℹ Info: Menggunakan 75% lebar layar (Kanan)")
    end
    
    io.write("Lanjutkan? (y/n): ")
    if io.read() ~= "y" then return end
    
    for i = 1, maxApps do
        local pkg = packages[i]
        print("\n[" .. i .. "/" .. maxApps .. "] Processing " .. pkg.name .. "...")
        
        exec("am force-stop " .. pkg.package)
        os.execute("sleep 0.5")
        
        modifyUGClonerPrefs(pkg.package, i, numApps)
        
        exec("am start " .. pkg.package)
        
        if i == 1 then os.execute("sleep 3") else os.execute("sleep 2") end
    end
    print("\n✓ DONE!")
end

-- Main Menu
function showMenu()
    print("\nZEEN TOOLS v4.1 (WIDE)")
    print("1. Auto Grid Launch (All)")
    print("2. Detect & Add Roblox (Auto)")
    print("3. List Packages")
    print("4. Clear All Data")
    print("5. Exit")
    io.write("Pilih: ")
    return io.read()
end

function main()
    io.stdout:setvbuf("no")
    loadPackages()
    updateScreenResolution()
    
    while true do
        local choice = showMenu()
        if choice == "1" then launchAutoGrid()
        elseif choice == "2" then autoDetectRoblox()
        elseif choice == "3" then 
            for i,p in ipairs(packages) do print(i..". "..p.name) end 
        elseif choice == "4" then packages={}; savePackages(); print("Cleared.")
        elseif choice == "5" then break 
        end
    end
end

main()

