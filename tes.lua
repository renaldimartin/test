#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v4.3 (PRO EDITION)
-- Auto Grid Freeform - UG Cloner Edition
-- ==========================================
-- Update v4.3:
-- [+] RATIO 1:2.5 Split (Lebih presisi)
-- [+] SETTINGS MENU: Atur Delay Launch
-- [+] Save/Load Config otomatis
-- [+] Fix Status Bar Safety Tetap Ada
-- ==========================================

print("================================")
print("  ZEEN TOOLS v4.3 (PRO)")
print("  Ratio: 1:2.5 | Custom Delay")
print("================================")
print()

-- KONFIGURASI DEFAULT
local STATUS_BAR_HEIGHT = 60 -- Safety margin pixel atas
local DEFAULT_DELAY = 10     -- Default delay 10 detik

-- File paths
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local CONFIG_FILE = "/data/data/com.termux/files/home/.zeen_config.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

-- Data storage
local packages = {}
local active_tasks = {}
local config = {
    delay = DEFAULT_DELAY
}
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 

-- Execute root command
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

-- Load & Save Config (Delay)
function loadConfig()
    local f = io.open(CONFIG_FILE, "r")
    if f then
        for line in f:lines() do
            local key, val = line:match("(%w+)=(%d+)")
            if key and val then
                config[key] = tonumber(val)
            end
        end
        f:close()
    end
end

function saveConfig()
    local f = io.open(CONFIG_FILE, "w")
    if f then
        f:write("delay=" .. config.delay .. "\n")
        f:close()
        return true
    end
    return false
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

-- Auto Detect Resolution
function updateScreenResolution()
    local result = exec("wm size")
    local w, h = result:match("Physical size: (%d+)x(%d+)")
    
    if w and h then
        w = tonumber(w)
        h = tonumber(h)
        local ori = getOrientation()
        
        if ori == "landscape" then
            if w < h then DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w
            else DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h end
        else
            if w > h then DISPLAY_WIDTH, DISPLAY_HEIGHT = h, w
            else DISPLAY_WIDTH, DISPLAY_HEIGHT = w, h end
        end
        print("✓ Screen: " .. DISPLAY_WIDTH .. "x" .. DISPLAY_HEIGHT .. " (Safe Top: " .. STATUS_BAR_HEIGHT .. "px)")
    else
        print("⚠ Gagal deteksi layar, default: 1280x720")
    end
end

-- Determine layout type
function getLayoutType(numApps)
    if numApps <= 4 then return "2x2 Full"
    elseif numApps <= 6 then return "Right Side 1:2.5"
    else return "2x4 Full" end
end

-- Get grid positions (UPDATED RATIO 1:2.5)
function getGridPositions(numApps)
    local layoutType = getLayoutType(numApps)
    
    if layoutType == "2x2 Full" then
        local w = math.floor(DISPLAY_WIDTH / 2)
        local h = math.floor(DISPLAY_HEIGHT / 2)
        return {
            {name="TL", left=0, top=0, right=w, bottom=h},
            {name="TR", left=w, top=0, right=DISPLAY_WIDTH, bottom=h},
            {name="BL", left=0, top=h, right=w, bottom=DISPLAY_HEIGHT},
            {name="BR", left=w, top=h, right=DISPLAY_WIDTH, bottom=DISPLAY_HEIGHT},
        }

    elseif layoutType == "Right Side 1:2.5" then
        -- ==================================================
        -- LOGIKA 1:2.5 SPLIT
        -- Total Bagian = 1 (Kiri) + 2.5 (Kanan) = 3.5
        -- Persentase Kanan = 2.5 / 3.5 ≈ 71.4%
        -- ==================================================
        
        local usable_height = DISPLAY_HEIGHT - STATUS_BAR_HEIGHT
        local h_slot = math.floor(usable_height / 3)
        
        -- Hitung Lebar berdasarkan rasio 1:2.5
        local ratio_mult = 2.5 / 3.5
        local grid_width = math.floor(DISPLAY_WIDTH * ratio_mult)
        
        local start_x = DISPLAY_WIDTH - grid_width
        local w_slot = math.floor(grid_width / 2)
        
        -- Koordinat Y
        local y1 = STATUS_BAR_HEIGHT
        local y2 = STATUS_BAR_HEIGHT + h_slot
        local y3 = STATUS_BAR_HEIGHT + (h_slot*2)
        
        local b1 = y1 + h_slot
        local b2 = y2 + h_slot
        local b3 = DISPLAY_HEIGHT 
        
        return {
            -- Baris 1
            {name="R1 Left",  left=start_x,        top=y1, right=start_x+w_slot, bottom=b1},
            {name="R1 Right", left=start_x+w_slot, top=y1, right=DISPLAY_WIDTH,    bottom=b1},
            -- Baris 2
            {name="R2 Left",  left=start_x,        top=y2, right=start_x+w_slot, bottom=b2},
            {name="R2 Right", left=start_x+w_slot, top=y2, right=DISPLAY_WIDTH,    bottom=b2},
            -- Baris 3
            {name="R3 Left",  left=start_x,        top=y3, right=start_x+w_slot, bottom=b3},
            {name="R3 Right", left=start_x+w_slot, top=y3, right=DISPLAY_WIDTH,    bottom=b3},
        }

    else -- 2x4 Fallback
        local h = math.floor(DISPLAY_HEIGHT / 4)
        local w = h * 2
        return {
            {name="R1 L", left=0, top=0,     right=w,             bottom=h},
            {name="R1 R", left=w, top=0,     right=DISPLAY_WIDTH, bottom=h},
            {name="R2 L", left=0, top=h,     right=w,             bottom=h*2},
            {name="R2 R", left=w, top=h,     right=DISPLAY_WIDTH, bottom=h*2},
            {name="R3 L", left=0, top=h*2,   right=w,             bottom=h*3},
            {name="R3 R", left=w, top=h*2,   right=DISPLAY_WIDTH, bottom=h*3},
            {name="R4 L", left=0, top=h*3,   right=w,             bottom=DISPLAY_HEIGHT},
            {name="R4 R", left=w, top=h*3,   right=DISPLAY_WIDTH, bottom=DISPLAY_HEIGHT},
        }
    end
end

-- Modify XML
function modifyUGClonerPrefs(package, position, numApps)
    local grid_positions = getGridPositions(numApps)
    local pos = grid_positions[position]
    
    if not pos then return false end
    
    local cloneId = package:match("clien([%w]+)$") or "z1"
    
    local findCmd = string.format("ls /data/data/%s/shared_prefs/*.xml 2>/dev/null | grep -i pref", package)
    local foundFiles = exec(findCmd)
    local prefFile = ""
    
    if foundFiles and foundFiles ~= "" then
        prefFile = foundFiles:match("([^\n]+_preferences%.xml)") or foundFiles:match("([^\n]+)")
    else
        prefFile = string.format("/data/data/%s/shared_prefs/com.roblox.clien%s_preferences.xml", package, cloneId)
        if not exec("test -f " .. prefFile .. " && echo 'yes'"):match("yes") then
            print("✗ Prefs file not found: " .. package)
            return false
        end
    end

    print("→ Set " .. pos.name .. ": (" .. pos.left .. "," .. pos.top .. ")")
    
    local commands = {
        string.format("sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_left\\\" value=\\\"%d\\\"/' '%s'", pos.left, prefFile),
        string.format("sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_top\\\" value=\\\"%d\\\"/' '%s'", pos.top, prefFile),
        string.format("sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_right\\\" value=\\\"%d\\\"/' '%s'", pos.right, prefFile),
        string.format("sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9-]*\\\"/app_cloner_current_window_bottom\\\" value=\\\"%d\\\"/' '%s'", pos.bottom, prefFile),
    }
    
    for _, cmd in ipairs(commands) do exec(cmd) end
    return true
end

-- Save/Load Packages
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

-- Menu Settings
function showSettings()
    while true do
        print("\n══ SETTINGS ══")
        print("Current Delay: " .. config.delay .. " seconds")
        print()
        print("1. Ubah Delay (Detik)")
        print("2. Kembali")
        io.write("Pilih: ")
        local choice = io.read()
        
        if choice == "1" then
            io.write("Masukkan delay baru (detik): ")
            local newDelay = tonumber(io.read())
            if newDelay and newDelay > 0 then
                config.delay = newDelay
                saveConfig()
                print("✓ Delay disimpan: " .. newDelay .. "s")
            else
                print("✗ Input tidak valid!")
            end
        elseif choice == "2" then
            break
        end
    end
end

-- Auto-detect Roblox
function autoDetectRoblox()
    print("\n══ AUTO-DETECT ROBLOX ══")
    local result = exec("pm list packages | grep 'roblox'")
    local detected = {}
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then table.insert(detected, pkg) end
    end
    
    if #detected == 0 then print("✗ Tidak ada Roblox ditemukan."); io.read(); return end
    
    print("✓ Ditemukan " .. #detected .. " packages. Ketik 'all' untuk add.")
    io.write("Pilihan: ")
    if io.read() == "all" then
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
    
    if numApps >= 5 and numApps <= 6 then
        print("ℹ Mode: 1:2.5 Split (Safe Bar)")
    end
    
    print("ℹ Delay per app: " .. config.delay .. "s")
    io.write("Lanjutkan? (y/n): ")
    if io.read() ~= "y" then return end
    
    local maxApps = math.min(8, numApps)
    for i = 1, maxApps do
        local pkg = packages[i]
        print("\n[" .. i .. "/" .. maxApps .. "] " .. pkg.name)
        
        exec("am force-stop " .. pkg.package)
        os.execute("sleep 0.5") -- Short wait for kill
        
        modifyUGClonerPrefs(pkg.package, i, numApps)
        
        exec("am start " .. pkg.package)
        print("→ Launched.")
        
        if i < maxApps then
            print("⏳ Waiting " .. config.delay .. "s...")
            os.execute("sleep " .. config.delay)
        else
            print("✓ Last app launched.")
        end
    end
    print("\n✓ DONE ALL!")
end

-- Main Menu
function showMenu()
    print("\nZEEN TOOLS v4.3")
    print("1. Auto Grid Launch")
    print("2. Detect Roblox")
    print("3. List Packages")
    print("4. Settings (Delay)")
    print("5. Clear Data")
    print("6. Exit")
    io.write("Pilih: ")
    return io.read()
end

function main()
    io.stdout:setvbuf("no")
    loadPackages()
    loadConfig() -- Load settingan user
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

