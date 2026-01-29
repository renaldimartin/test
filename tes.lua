#!/data/data/com.termux/files/usr/bin/lua

-- ==========================================
-- PROJECT ZEEN TOOLS v4.4 (LEFT EDITION)
-- Auto Grid Freeform - UG Cloner Edition
-- ==========================================
-- Update v4.4 (Custom Request):
-- [+] LAYOUT: LEFT SIDE ONLY (Kiri Full)
-- [+] RATIO: 2:1 (Kiri 66% Aktif, Kanan 33% Kosong)
-- [+] Grid otomatis menyesuaikan area kiri
-- ==========================================

print("================================")
print("  ZEEN TOOLS v4.4 (LEFT 2:1)")
print("  Focus: Left Side | Ratio 2:1")
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
    -- Kita paksa semua menggunakan logika LEFT SIDE 2:1
    return "Left Side 2:1"
end

-- Get grid positions (NEW RATIO 2:1 LEFT)
function getGridPositions(numApps)
    -- ==================================================
    -- LOGIKA 2:1 SPLIT (LEFT FOCUS)
    -- Total Bagian = 2 (Kiri) + 1 (Kanan) = 3 Bagian
    -- Area Aktif (Kiri) = 2/3 dari lebar layar
    -- Area Kosong (Kanan) = 1/3 dari lebar layar
    -- ==================================================
    
    local usable_height = DISPLAY_HEIGHT - STATUS_BAR_HEIGHT
    local h_slot = math.floor(usable_height / 3) -- Dibagi 3 baris ke bawah
    
    -- Hitung Lebar Area Aktif (2/3 dari total lebar)
    local active_width_limit = math.floor(DISPLAY_WIDTH * (2 / 3))
    
    -- Karena area kiri cukup lebar (2/3), kita bagi lagi jadi 2 kolom
    local w_slot = math.floor(active_width_limit / 2)
    
    -- Koordinat Y
    local y1 = STATUS_BAR_HEIGHT
    local y2 = STATUS_BAR_HEIGHT + h_slot
    local y3 = STATUS_BAR_HEIGHT + (h_slot*2)
    
    local b1 = y1 + h_slot
    local b2 = y2 + h_slot
    local b3 = DISPLAY_HEIGHT 
    
    -- Koordinat X (Hanya bermain di area kiri 0 sampai active_width_limit)
    -- Kolom Kiri: 0 sampai w_slot
    -- Kolom Kanan: w_slot sampai active_width_limit
    
    return {
        -- Baris 1 (Atas)
        {name="R1 Left",  left=0,      top=y1, right=w_slot,             bottom=b1},
        {name="R1 Right", left=w_slot, top=y1, right=active_width_limit, bottom=b1},
        
        -- Baris 2 (Tengah)
        {name="R2 Left",  left=0,      top=y2, right=w_slot,             bottom=b2},
        {name="R2 Right", left=w_slot, top=y2, right=active_width_limit, bottom=b2},
        
        -- Baris 3 (Bawah)
        {name="R3 Left",  left=0,      top=y3, right=w_slot,             bottom=b3},
        {name="R3 Right", left=w_slot, top=y3, right=active_width_limit, bottom=b3},
        
        -- Extra slot jika lebih dari 6 (menumpuk di R1)
        {name="Extra 1",  left=0,      top=y1, right=w_slot,             bottom=b1},
        {name="Extra 2",  left=w_slot, top=y1, right=active_width_limit, bottom=b1},
    }
end

-- Modify XML
function modifyUGClonerPrefs(package, position, numApps)
    local grid_positions = getGridPositions(numApps)
    -- Gunakan modulo jika apps lebih dari slot yang tersedia
    local pos_index = ((position - 1) % #grid_positions) + 1
    local pos = grid_positions[pos_index]
    
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

    print("→ Set " .. pos.name .. ": (" .. pos.left .. "," .. pos.top .. ") - Width Limit: " .. pos.right)
    
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
    print("\n══ AUTO GRID LAUNCH (LEFT 2:1) ══")
    if #packages == 0 then print("✗ No packages!"); return end
    
    updateScreenResolution()
    local numApps = #packages
    
    print("ℹ Mode: Left Side 2:1 (Right Empty)")
    print("ℹ Delay per app: " .. config.delay .. "s")
    io.write("Lanjutkan? (y/n): ")
    if io.read() ~= "y" then return end
    
    local maxApps = math.min(8, numApps)
    for i = 1, maxApps do
        local pkg = packages[i]
        print("\n[" .. i .. "/" .. maxApps .. "] " .. pkg.name)
        
        exec("am force-stop " .. pkg.package)
        os.execute("sleep 0.5") 
        
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
    print("\nZEEN TOOLS v4.4 (LEFT 2:1)")
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

