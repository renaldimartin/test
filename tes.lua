#!/data/data/com.termux/files/usr/bin/lua

-- Auto Grid Freeform v3.1 - UG Cloner Edition
-- Supports UG Cloner apps with built-in floating
-- Modifies XML preferences for precise grid positioning
-- Handles various package naming patterns

print("================================")
print("  Auto Grid Freeform v3.1")
print("  UG Cloner Edition")
print("================================")
print()

-- Display configuration
local DISPLAY_WIDTH = 1280  -- Landscape mode
local DISPLAY_HEIGHT = 720

-- File paths
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

-- Data storage
local packages = {}
local active_tasks = {}

-- Execute root command via temp script file
function exec(cmd)
    local f = io.open(TEMP_SCRIPT, "w")
    if not f then
        return ""
    end
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

-- Determine layout type based on number of apps
function getLayoutType(numApps)
    if numApps <= 4 then
        return "2x2"
    elseif numApps <= 6 then
        return "2x3"
    else
        return "2x4"
    end
end

-- Get grid positions (full screen layout)
function getGridPositions(numApps)
    local layoutType = getLayoutType(numApps)
    
    if layoutType == "2x2" then
        local w = math.floor(DISPLAY_WIDTH / 2)
        local h = math.floor(DISPLAY_HEIGHT / 2)
        return {
            {name="Top Left",     left=0, top=0,   right=w,             bottom=h},
            {name="Top Right",    left=w, top=0,   right=DISPLAY_WIDTH, bottom=h},
            {name="Bottom Left",  left=0, top=h,   right=w,             bottom=DISPLAY_HEIGHT},
            {name="Bottom Right", left=w, top=h,   right=DISPLAY_WIDTH, bottom=DISPLAY_HEIGHT},
        }
    elseif layoutType == "2x3" then
        -- Perfect for 6 apps!
        local w = math.floor(DISPLAY_WIDTH / 2)  -- 640
        local h = math.floor(DISPLAY_HEIGHT / 3) -- 240
        return {
            {name="Row 1 Left",  left=0, top=0,     right=w,             bottom=h},
            {name="Row 1 Right", left=w, top=0,     right=DISPLAY_WIDTH, bottom=h},
            {name="Row 2 Left",  left=0, top=h,     right=w,             bottom=h*2},
            {name="Row 2 Right", left=w, top=h,     right=DISPLAY_WIDTH, bottom=h*2},
            {name="Row 3 Left",  left=0, top=h*2,   right=w,             bottom=DISPLAY_HEIGHT},
            {name="Row 3 Right", left=w, top=h*2,   right=DISPLAY_WIDTH, bottom=DISPLAY_HEIGHT},
        }
    else -- 2x4
        local h = math.floor(DISPLAY_HEIGHT / 4)
        local w = h * 2  -- 1:2 ratio
        return {
            {name="Row 1 Left",  left=0, top=0,     right=w,             bottom=h},
            {name="Row 1 Right", left=w, top=0,     right=DISPLAY_WIDTH, bottom=h},
            {name="Row 2 Left",  left=0, top=h,     right=w,             bottom=h*2},
            {name="Row 2 Right", left=w, top=h,     right=DISPLAY_WIDTH, bottom=h*2},
            {name="Row 3 Left",  left=0, top=h*2,   right=w,             bottom=h*3},
            {name="Row 3 Right", left=w, top=h*2,   right=DISPLAY_WIDTH, bottom=h*3},
            {name="Row 4 Left",  left=0, top=h*3,   right=w,             bottom=DISPLAY_HEIGHT},
            {name="Row 4 Right", left=w, top=h*3,   right=DISPLAY_WIDTH, bottom=DISPLAY_HEIGHT},
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
    
    -- Detect clone identifier from package name
    local cloneId = package:match("clien([%w]+)$") or "z1"
    local prefFile = string.format(
        "/data/data/%s/shared_prefs/com.roblox.clien%s_preferences.xml",
        package, cloneId
    )
    
    print("→ Modifying preferences for position: " .. pos.name)
    print("   Package: " .. package)
    print("   Clone ID: " .. cloneId)
    print("   Pref file: " .. prefFile)
    
    -- Check if file exists
    local checkCmd = string.format("test -f %s && echo 'EXISTS' || echo 'NOT_FOUND'", prefFile)
    local fileCheck = exec(checkCmd)
    
    if not fileCheck:match("EXISTS") then
        print("✗ Preferences file not found!")
        print("   Trying to find correct file...")
        
        -- Try to find the actual preferences file
        local findCmd = string.format("ls /data/data/%s/shared_prefs/*.xml 2>/dev/null | grep -i pref", package)
        local foundFiles = exec(findCmd)
        
        if foundFiles and foundFiles ~= "" then
            print("   Found files:")
            for file in foundFiles:gmatch("[^\n]+") do
                print("     • " .. file)
            end
            -- Use the first file that contains "preferences"
            prefFile = foundFiles:match("([^\n]+_preferences%.xml)")
            if not prefFile then
                prefFile = foundFiles:match("([^\n]+)") -- fallback to first file
            end
            print("   Using: " .. prefFile)
        else
            print("✗ Could not find any preferences file!")
            return false
        end
    else
        print("✓ Preferences file found!")
    end
    
    -- Modify the XML values
    print("→ Setting window bounds: (" .. pos.left .. "," .. pos.top .. ") - (" .. pos.right .. "," .. pos.bottom .. ")")
    
    local commands = {
        string.format("sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_left\\\" value=\\\"%d\\\"/' '%s'", pos.left, prefFile),
        string.format("sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_top\\\" value=\\\"%d\\\"/' '%s'", pos.top, prefFile),
        string.format("sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_right\\\" value=\\\"%d\\\"/' '%s'", pos.right, prefFile),
        string.format("sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_bottom\\\" value=\\\"%d\\\"/' '%s'", pos.bottom, prefFile),
    }
    
    for _, cmd in ipairs(commands) do
        exec(cmd)
    end
    
    -- Verify modifications
    local verifyCmd = string.format("grep -E 'app_cloner_current_window_(left|top|right|bottom)' '%s'", prefFile)
    local result = exec(verifyCmd)
    
    if result and result:match(tostring(pos.left)) then
        print("✓ Preferences successfully modified!")
        return true
    else
        print("⚠ Warning: Could not verify modifications")
        return true -- Continue anyway
    end
end

-- Save packages to file
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

-- Load packages from file
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

-- Auto-detect Roblox packages
function autoDetectRoblox()
    print()
    print("═══════════════════════════")
    print("  AUTO-DETECT ROBLOX APPS")
    print("═══════════════════════════")
    print()
    
    print("→ Scanning for Roblox packages...")
    local result = exec("pm list packages | grep 'roblox'")
    
    if not result or result == "" then
        print("✗ Tidak ada package Roblox ditemukan!")
        print()
        io.write("Tekan Enter untuk kembali...")
        io.read()
        return
    end
    
    local detected = {}
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then
            table.insert(detected, pkg)
        end
    end
    
    if #detected == 0 then
        print("✗ Tidak ada package Roblox ditemukan!")
        print()
        io.write("Tekan Enter untuk kembali...")
        io.read()
        return
    end
    
    print("✓ Ditemukan " .. #detected .. " package Roblox:")
    print()
    
    for i, pkg in ipairs(detected) do
        print(i .. ". " .. pkg)
    end
    
    print()
    print("Pilihan:")
    print("  • Ketik 'all' untuk add semua")
    print("  • Ketik nomor spesifik (contoh: 1,3,4)")
    print("  • Ketik '0' untuk batal")
    print()
    io.write("Pilihan: ")
    io.flush()
    local choice = io.read()
    
    if not choice or choice == "0" or choice == "" then
        print("Batal.")
        return
    end
    
    local toAdd = {}
    
    if choice:lower() == "all" then
        toAdd = detected
    else
        for num in choice:gmatch("%d+") do
            local idx = tonumber(num)
            if idx and detected[idx] then
                table.insert(toAdd, detected[idx])
            end
        end
    end
    
    if #toAdd == 0 then
        print("✗ Tidak ada package yang dipilih!")
        return
    end
    
    print()
    print("→ Menambahkan " .. #toAdd .. " package...")
    
    local added = 0
    for _, pkg in ipairs(toAdd) do
        local exists = false
        for _, existing in ipairs(packages) do
            if existing.package == pkg then
                exists = true
                break
            end
        end
        
        if not exists then
            local name = pkg:match("com%.roblox%.(.+)") or pkg
            name = name:gsub("%.", " "):gsub("^%l", string.upper)
            
            table.insert(packages, {name = "Roblox " .. name, package = pkg})
            added = added + 1
            print("  ✓ " .. pkg)
        else
            print("  ○ " .. pkg .. " (sudah ada)")
        end
    end
    
    if added > 0 then
        if savePackages() then
            print()
            print("✓ Berhasil menambahkan " .. added .. " package baru!")
        end
    else
        print()
        print("○ Semua package sudah ada dalam list.")
    end
end

-- Add package manually
function addPackage()
    print()
    print("═══════════════════════════")
    print("  ADD PACKAGE MANUAL")
    print("═══════════════════════════")
    print()
    
    io.write("Nama App: ")
    io.flush()
    local name = io.read()
    
    if not name or name == "" then
        print("✗ Nama tidak boleh kosong!")
        return
    end
    
    io.write("Package Name: ")
    io.flush()
    local package = io.read()
    
    if not package or package == "" then
        print("✗ Package name tidak boleh kosong!")
        return
    end
    
    for _, pkg in ipairs(packages) do
        if pkg.package == package then
            print("✗ Package sudah ada!")
            return
        end
    end
    
    print()
    print("→ Verifying package...")
    local result = exec("pm list packages | grep '" .. package .. "'")
    
    if result:match(package) then
        print("✓ Package ditemukan!")
        table.insert(packages, {name = name, package = package})
        
        if savePackages() then
            print("✓ Package berhasil ditambahkan!")
        end
    else
        print("✗ Package tidak ditemukan di sistem!")
    end
end

-- List all packages
function listPackages()
    print()
    print("═══════════════════════════")
    print("  PACKAGE LIST")
    print("═══════════════════════════")
    
    if #packages == 0 then
        print("(Belum ada package)")
    else
        for i, pkg in ipairs(packages) do
            print(i .. ". " .. pkg.name)
            print("   " .. pkg.package)
        end
    end
    print()
end

-- Remove a package
function removePackage()
    print()
    
    if #packages == 0 then
        print("✗ Tidak ada package!")
        return
    end
    
    listPackages()
    
    io.write("Hapus nomor (0 = batal): ")
    io.flush()
    local choice = tonumber(io.read())
    
    if not choice or choice == 0 then
        print("Batal.")
        return
    end
    
    if choice > 0 and choice <= #packages then
        local removed = table.remove(packages, choice)
        print("✓ '" .. removed.name .. "' dihapus!")
        savePackages()
    else
        print("✗ Pilihan tidak valid!")
    end
end

-- Clear all packages
function clearAllPackages()
    print()
    io.write("Hapus SEMUA package? (yes/no): ")
    io.flush()
    local confirm = io.read()
    
    if confirm and (confirm:lower() == "yes" or confirm:lower() == "y") then
        packages = {}
        savePackages()
        print("✓ Semua package dihapus!")
    else
        print("Batal.")
    end
end

-- Get task ID for a package
function getTaskId(package)
    local result = exec("dumpsys activity activities | grep '" .. package .. "'")
    local taskId = result:match("#(%d+)")
    
    if not taskId then
        taskId = result:match("t(%d+)")
    end
    
    return taskId
end

-- Launch app with pre-set position
function launchWithPosition(package, appName, position, numApps)
    print("═══ Preparing " .. appName .. " ═══")
    print("→ Target position: " .. position)
    
    -- STEP 1: Force stop app
    print("→ Force stopping...")
    exec("am force-stop " .. package)
    os.execute("sleep 1")
    
    -- STEP 2: Modify XML preferences BEFORE launch
    if not modifyUGClonerPrefs(package, position, numApps) then
        print("✗ Failed to modify preferences!")
        print("   App may not position correctly.")
    end
    
    -- STEP 3: Launch app
    print("→ Launching app...")
    exec("am start " .. package)
    
    print("→ Waiting for app to start...")
    os.execute("sleep 3")
    
    local taskId = getTaskId(package)
    if taskId then
        print("✓ App launched successfully!")
        print("   Task ID: " .. taskId)
        active_tasks[package] = taskId
        return taskId
    else
        print("⚠ Could not get task ID (app may still be launching)")
        return nil
    end
end

-- Show grid layout visualization
function showGridLayout()
    local orientation = getOrientation()
    local numApps = #packages
    local layoutType = getLayoutType(numApps)
    
    print()
    print("═══════════════════════════")
    print("  GRID LAYOUT PREVIEW")
    print("═══════════════════════════")
    print()
    print("Orientation: " .. orientation:upper())
    print("Layout Type: " .. layoutType)
    print("Number of Apps: " .. numApps)
    print("Screen: " .. DISPLAY_WIDTH .. "x" .. DISPLAY_HEIGHT)
    print()
    
    if layoutType == "2x2" then
        local w = math.floor(DISPLAY_WIDTH / 2)
        local h = math.floor(DISPLAY_HEIGHT / 2)
        print("Grid Layout (2x2) - FULL SCREEN:")
        print()
        print("┌──────────┬──────────┐")
        print("│    1     │    2     │")
        print("│  " .. w .. "x" .. h .. " │  " .. w .. "x" .. h .. " │")
        print("├──────────┼──────────┤")
        print("│    3     │    4     │")
        print("│  " .. w .. "x" .. h .. " │  " .. w .. "x" .. h .. " │")
        print("└──────────┴──────────┘")
        
    elseif layoutType == "2x3" then
        local w = math.floor(DISPLAY_WIDTH / 2)
        local h = math.floor(DISPLAY_HEIGHT / 3)
        print("Grid Layout (2x3) - FULL SCREEN:")
        print()
        print("┌──────────┬──────────┐")
        print("│    1     │    2     │")
        print("│  " .. w .. "x" .. h .. " │  " .. w .. "x" .. h .. " │")
        print("├──────────┼──────────┤")
        print("│    3     │    4     │")
        print("│  " .. w .. "x" .. h .. " │  " .. w .. "x" .. h .. " │")
        print("├──────────┼──────────┤")
        print("│    5     │    6     │")
        print("│  " .. w .. "x" .. h .. " │  " .. w .. "x" .. h .. " │")
        print("└──────────┴──────────┘")
        
    else
        local h = math.floor(DISPLAY_HEIGHT / 4)
        local w = h * 2
        print("Grid Layout (2x4) - FULL SCREEN:")
        print()
        print("┌──────────┬──────────┐")
        print("│    1     │    2     │")
        print("├──────────┼──────────┤")
        print("│    3     │    4     │")
        print("├──────────┼──────────┤")
        print("│    5     │    6     │")
        print("├──────────┼──────────┤")
        print("│    7     │    8     │")
        print("└──────────┴──────────┘")
        print()
        print("Each: " .. w .. "x" .. h .. " (1:2 ratio)")
    end
    print()
end

-- AUTO GRID LAUNCH - Main feature
function launchAutoGrid()
    print()
    print("═══════════════════════════════════")
    print("  AUTO GRID LAUNCH")
    print("═══════════════════════════════════")
    print()
    
    if #packages == 0 then
        print("✗ Belum ada package!")
        print()
        print("Gunakan option 6 (Auto-Detect) untuk")
        print("scan dan add packages otomatis.")
        print()
        io.write("Tekan Enter untuk kembali...")
        io.read()
        return
    end
    
    local numApps = #packages
    local layoutType = getLayoutType(numApps)
    local maxApps = math.min(8, numApps)
    
    print("Apps to launch: " .. maxApps)
    print("Layout: " .. layoutType)
    print()
    
    showGridLayout()
    
    print("═══════════════════════════════════")
    print()
    io.write("Lanjutkan launch? (y/n): ")
    io.flush()
    local confirm = io.read()
    
    if not confirm or not (confirm:lower() == "y" or confirm:lower() == "yes") then
        print("Dibatalkan.")
        return
    end
    
    print()
    print("→ Starting auto-grid launch...")
    print("   This may take a while...")
    print()
    
    for i = 1, maxApps do
        local pkg = packages[i]
        print()
        print("═══ [ " .. i .. "/" .. maxApps .. " ] ═══")
        
        launchWithPosition(pkg.package, pkg.name, i, numApps)
        
        if i < maxApps then
            print()
            print("→ Waiting before next launch...")
            os.execute("sleep 2")
        end
    end
    
    print()
    print("═══════════════════════════════════")
    print("✓ AUTO GRID LAUNCH COMPLETE!")
    print("═══════════════════════════════════")
    print()
    print("All apps should now be positioned in")
    print("a " .. layoutType .. " grid layout.")
end

-- Launch single app
function launchSingleApp()
    print()
    print("═══════════════════════════")
    print("  LAUNCH SINGLE APP")
    print("═══════════════════════════")
    print()
    
    if #packages == 0 then
        print("✗ Belum ada package!")
        return
    end
    
    print("Pilih App:")
    for i, pkg in ipairs(packages) do
        print(i .. ". " .. pkg.name)
    end
    print()
    io.write("Pilihan (0 = batal): ")
    io.flush()
    local choice = tonumber(io.read())
    
    if not choice or choice == 0 or not packages[choice] then
        print("Dibatalkan.")
        return
    end
    
    local pkg = packages[choice]
    
    print()
    showGridLayout()
    
    local maxPos = math.min(8, #packages)
    io.write("Posisi grid (1-" .. maxPos .. "): ")
    io.flush()
    local pos = tonumber(io.read())
    
    if pos and pos >= 1 and pos <= maxPos then
        print()
        launchWithPosition(pkg.package, pkg.name, pos, #packages)
    else
        print("✗ Posisi tidak valid!")
    end
end

-- Move/reposition active app
function moveActiveApp()
    print()
    print("═══════════════════════════")
    print("  MOVE/REPOSITION APP")
    print("═══════════════════════════")
    print()
    
    if #packages == 0 then
        print("✗ Belum ada package!")
        return
    end
    
    print("Pilih App untuk dipindah:")
    for i, pkg in ipairs(packages) do
        local status = active_tasks[pkg.package] and " [ACTIVE]" or ""
        print(i .. ". " .. pkg.name .. status)
    end
    print()
    io.write("Pilihan (0 = batal): ")
    io.flush()
    local choice = tonumber(io.read())
    
    if not choice or choice == 0 or not packages[choice] then
        print("Dibatalkan.")
        return
    end
    
    local pkg = packages[choice]
    
    print()
    showGridLayout()
    
    local maxPos = math.min(8, #packages)
    io.write("Posisi baru (1-" .. maxPos .. "): ")
    io.flush()
    local pos = tonumber(io.read())
    
    if pos and pos >= 1 and pos <= maxPos then
        print()
        print("→ Repositioning to position " .. pos .. "...")
        launchWithPosition(pkg.package, pkg.name, pos, #packages)
    else
        print("✗ Posisi tidak valid!")
    end
end

-- Show active tasks
function showActiveTasks()
    print()
    print("═══════════════════════════")
    print("  ACTIVE TASKS")
    print("═══════════════════════════")
    print()
    
    if next(active_tasks) == nil then
        print("(Belum ada task yang active)")
    else
        local count = 0
        for pkg, taskId in pairs(active_tasks) do
            local name = pkg
            for _, p in ipairs(packages) do
                if p.package == pkg then
                    name = p.name
                    break
                end
            end
            count = count + 1
            print(count .. ". " .. name)
            print("   Package: " .. pkg)
            print("   Task ID: " .. taskId)
            print()
        end
        print("Total: " .. count .. " active task(s)")
    end
    print()
end

-- Main menu
function showMenu()
    print()
    print("═══════════════════════════")
    print("  MAIN MENU")
    print("═══════════════════════════")
    print()
    print("🚀 LAUNCH & POSITION:")
    print("  1. Auto Grid Launch (All)")
    print("  2. Launch Single App")
    print("  3. Move/Reposition App")
    print()
    print("📊 INFO & VIEW:")
    print("  4. Show Grid Layout")
    print("  5. Show Active Tasks")
    print()
    print("📦 PACKAGE MANAGEMENT:")
    print("  6. 🔍 Auto-Detect Roblox")
    print("  7. Add Package Manual")
    print("  8. List Packages")
    print("  9. Remove Package")
    print("  10. Clear All Packages")
    print()
    print("  11. Exit")
    print()
    print("═══════════════════════════")
    io.write("Pilihan: ")
    io.flush()
    return io.read()
end

-- Main program loop
function main()
    -- Disable buffering for immediate output
    io.stdout:setvbuf("no")
    io.stdin:setvbuf("no")
    
    -- Load saved packages
    loadPackages()
    
    print("═══════════════════════════")
    print("  Welcome!")
    print("═══════════════════════════")
    print()
    
    if #packages > 0 then
        print("✓ Loaded " .. #packages .. " saved package(s)")
    else
        print("📌 TIP: Use option 6 to auto-detect")
        print("   all Roblox packages on your device!")
    end
    
    -- Main loop
    while true do
        local choice = showMenu()
        
        if choice == "1" then
            launchAutoGrid()
        elseif choice == "2" then
            launchSingleApp()
        elseif choice == "3" then
            moveActiveApp()
        elseif choice == "4" then
            showGridLayout()
        elseif choice == "5" then
            showActiveTasks()
        elseif choice == "6" then
            autoDetectRoblox()
        elseif choice == "7" then
            addPackage()
        elseif choice == "8" then
            listPackages()
        elseif choice == "9" then
            removePackage()
        elseif choice == "10" then
            clearAllPackages()
        elseif choice == "11" then
            print()
            print("═══════════════════════════")
            print("  Terima kasih!")
            print("  Sampai jumpa! 👋")
            print("═══════════════════════════")
            print()
            break
        else
            print()
            print("✗ Pilihan tidak valid!")
            os.execute("sleep 1")
        end
        
        if choice ~= "11" then
            print()
            io.write("Tekan Enter untuk lanjut...")
            io.read()
        end
    end
end

-- Run the program
main()