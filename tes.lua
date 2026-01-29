#!/data/data/com.termux/files/usr/bin/lua

-- Auto Grid Freeform v3.2 - UG Cloner Edition
-- Supports UG Cloner apps with built-in floating
-- Modifies XML preferences for precise grid positioning
-- Handles various package naming patterns
-- RIGHT SIDE LAYOUT (1:2 Split) with Status Bar Protection

print("================================")
print("  Auto Grid Freeform v3.2")
print("  UG Cloner Edition")
print("  Right Side Layout (1:2)")
print("================================")
print()

-- Display configuration (will be detected automatically)
local DISPLAY_WIDTH = 0
local DISPLAY_HEIGHT = 0
local STATUS_BAR_HEIGHT = 80  -- Status bar protection area
local CURRENT_ORIENTATION = "unknown"

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

-- Detect orientation and screen size
function detectDisplay()
    print("→ Detecting screen configuration...")
    
    -- Get screen size
    local sizeResult = exec("wm size")
    local width, height = sizeResult:match("Physical size: (%d+)x(%d+)")
    
    if width and height then
        width = tonumber(width)
        height = tonumber(height)
        
        -- Determine orientation
        if width > height then
            CURRENT_ORIENTATION = "landscape"
            DISPLAY_WIDTH = width
            DISPLAY_HEIGHT = height
        else
            CURRENT_ORIENTATION = "portrait"
            DISPLAY_WIDTH = height  -- Swap for consistent calculation
            DISPLAY_HEIGHT = width
        end
        
        print("✓ Screen Detected: " .. width .. "x" .. height)
        print("✓ Orientation: " .. CURRENT_ORIENTATION)
        print("✓ Using dimensions: " .. DISPLAY_WIDTH .. "x" .. DISPLAY_HEIGHT)
        return true
    else
        -- Fallback to dumpsys
        local dumpResult = exec("dumpsys window | grep 'cur='")
        width, height = dumpResult:match("cur=(%d+)x(%d+)")
        
        if width and height then
            width = tonumber(width)
            height = tonumber(height)
            
            if width > height then
                CURRENT_ORIENTATION = "landscape"
                DISPLAY_WIDTH = width
                DISPLAY_HEIGHT = height
            else
                CURRENT_ORIENTATION = "portrait"
                DISPLAY_WIDTH = height
                DISPLAY_HEIGHT = width
            end
            
            print("✓ Screen Detected (fallback): " .. width .. "x" .. height)
            print("✓ Orientation: " .. CURRENT_ORIENTATION)
            return true
        end
    end
    
    -- If detection failed, use defaults
    print("⚠ Could not detect screen size, using defaults")
    DISPLAY_WIDTH = 1280
    DISPLAY_HEIGHT = 720
    CURRENT_ORIENTATION = "landscape"
    return false
end

-- Legacy function for compatibility
function getOrientation()
    return CURRENT_ORIENTATION
end

-- Determine layout type based on number of apps
function getLayoutType(numApps)
    -- Always use right side 3x2 layout (6 apps max)
    return "right_3x2"
end

-- Get grid positions (RIGHT SIDE ONLY - 1:2 split layout)
function getGridPositions(numApps)
    -- LEFT SIDE = 1/3 of screen (empty)
    -- RIGHT SIDE = 2/3 of screen (for 6 apps in 3 rows x 2 columns)
    
    local leftSideWidth = math.floor(DISPLAY_WIDTH / 3)  -- 426 pixels (left empty)
    local rightSideLeft = leftSideWidth  -- Start of right side: 426
    local rightSideWidth = DISPLAY_WIDTH - leftSideWidth  -- Right side width: 854 pixels
    
    -- Right side divided into 2 columns
    local columnWidth = math.floor(rightSideWidth / 2)  -- 427 pixels per column
    
    -- Right side divided into 3 rows
    local rowHeight = math.floor(DISPLAY_HEIGHT / 3)  -- 240 pixels per row
    
    -- Calculate column positions on the right side
    local col1Left = rightSideLeft  -- 426
    local col1Right = col1Left + columnWidth  -- 853
    local col2Left = col1Right  -- 853
    local col2Right = DISPLAY_WIDTH  -- 1280
    
    -- Calculate row positions
    local row1Top = 0
    local row1Bottom = rowHeight  -- 240
    local row2Top = rowHeight  -- 240
    local row2Bottom = rowHeight * 2  -- 480
    local row3Top = rowHeight * 2  -- 480
    local row3Bottom = DISPLAY_HEIGHT  -- 720
    
    -- Positions with status bar protection for Row 1
    return {
        -- Row 1 (dengan status bar protection)
        {name="R1-Left",  left=col1Left, top=STATUS_BAR_HEIGHT, right=col1Right, bottom=row1Bottom},
        {name="R1-Right", left=col2Left, top=STATUS_BAR_HEIGHT, right=col2Right, bottom=row1Bottom},
        
        -- Row 2 (normal)
        {name="R2-Left",  left=col1Left, top=row2Top, right=col1Right, bottom=row2Bottom},
        {name="R2-Right", left=col2Left, top=row2Top, right=col2Right, bottom=row2Bottom},
        
        -- Row 3 (normal)
        {name="R3-Left",  left=col1Left, top=row3Top, right=col1Right, bottom=row3Bottom},
        {name="R3-Right", left=col2Left, top=row3Top, right=col2Right, bottom=row3Bottom},
    }
end

-- Show grid layout visualization
function showGridLayout()
    print()
    print("═══════════════════════════════════")
    print("  GRID LAYOUT VISUALIZATION")
    print("  Right Side Wide (1:2 Split)")
    print("═══════════════════════════════════")
    print()
    print("Screen Detected: " .. DISPLAY_WIDTH .. "x" .. DISPLAY_HEIGHT)
    print("Orientation: " .. CURRENT_ORIENTATION:upper())
    print("Layout Mode: Right Side Wide (1:3 Split)")
    print()
    
    local grid_positions = getGridPositions(#packages)
    local numApps = math.min(6, #packages)
    
    print("═══════════════════════════════════════════════════════")
    print("║              LEFT SIDE               ║  RIGHT SIDE   ║")
    print("║             (KOSONG)                 ║   (6 APPS)    ║")
    print("║            1/3 WIDTH                 ║  2/3 WIDTH    ║")
    print("║══════════════════════════════════════╬═══════╦═══════╣")
    print("║                                      ║ App 1 ║ App 2 ║ <- Status Bar Protected")
    print("║                                      ║  (L)  ║  (R)  ║")
    print("║             (EMPTY)                  ╠═══════╬═══════╣")
    print("║                                      ║ App 3 ║ App 4 ║")
    print("║         Layar Kosong                 ║  (L)  ║  (R)  ║")
    print("║        untuk konten                  ╠═══════╬═══════╣")
    print("║           lainnya                    ║ App 5 ║ App 6 ║")
    print("║                                      ║  (L)  ║  (R)  ║")
    print("═══════════════════════════════════════════════════════")
    print()
    print("Grid Positions (Right Side Only):")
    for i = 1, math.min(6, numApps) do
        local pos = grid_positions[i]
        local status_note = ""
        if i <= 2 then
            status_note = " <- Status Bar Protected"
        end
        print(string.format("%d. %s: (%d,%d) -> (%d,%d)%s", 
            i, pos.name, pos.left, pos.top, pos.right, pos.bottom, status_note))
    end
    print()
end

-- Launch with position
function launchWithPosition(package, name, position, numApps)
    print("→ Processing " .. name .. "...")
    
    -- Modify preferences first
    if not modifyUGClonerPrefs(package, position, numApps) then
        print("⚠ Could not modify preferences, continuing anyway...")
    end
    
    -- Kill existing instance
    print("→ Killing existing instance...")
    exec("am force-stop " .. package)
    os.execute("sleep 1")
    
    -- Launch app
    print("→ Launching app...")
    local launchCmd = string.format(
        "am start -n %s/com.roblox.client.startup.ActivitySplash",
        package
    )
    
    local result = exec(launchCmd)
    
    if result:match("Error") or result:match("does not exist") then
        print("✗ Launch failed!")
        print("   Trying alternative activity...")
        
        -- Try alternative activity
        launchCmd = string.format(
            "monkey -p %s -c android.intent.category.LAUNCHER 1",
            package
        )
        result = exec(launchCmd)
    end
    
    os.execute("sleep 2")
    
    -- Get task ID
    local taskResult = exec("dumpsys activity activities | grep -A 3 '" .. package .. "' | grep 'TaskRecord'")
    local taskId = taskResult:match("#(%d+)")
    
    if taskId then
        print("→ App running in task #" .. taskId)
        active_tasks[package] = taskId
        
        -- Ensure window bounds are applied via WM commands (backup method)
        local grid_positions = getGridPositions(numApps)
        local pos = grid_positions[position]
        
        if pos then
            print("→ Applying window bounds via WM...")
            local wmCmd = string.format(
                "wm task set-bounds %s %d %d %d %d",
                taskId, pos.left, pos.top, pos.right, pos.bottom
            )
            exec(wmCmd)
            print("✓ Window bounds applied!")
        end
    else
        print("⚠ Could not determine task ID")
    end
    
    print("✓ Posisi RT Left: (" .. position .. ")")
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
    print("1. Tambah semua package")
    print("2. Pilih package secara manual")
    print("0. Batal")
    print()
    io.write("Pilihan: ")
    io.flush()
    local choice = io.read()
    
    if choice == "1" then
        packages = {}
        for i, pkg in ipairs(detected) do
            table.insert(packages, {
                name = "Roblox Client" .. (i > 1 and " " .. i or ""),
                package = pkg
            })
        end
        savePackages()
        print()
        print("✓ Berhasil menambahkan " .. #packages .. " package!")
    elseif choice == "2" then
        packages = {}
        for i, pkg in ipairs(detected) do
            print()
            print("[" .. i .. "/" .. #detected .. "] " .. pkg)
            io.write("Tambahkan package ini? (y/n): ")
            io.flush()
            local add = io.read()
            if add and (add:lower() == "y" or add:lower() == "yes") then
                io.write("Nama untuk package ini: ")
                io.flush()
                local name = io.read()
                if name and name ~= "" then
                    table.insert(packages, {name = name, package = pkg})
                    print("✓ Ditambahkan!")
                end
            end
        end
        savePackages()
        print()
        print("✓ Berhasil menambahkan " .. #packages .. " package!")
    else
        print("Dibatalkan.")
    end
end

-- Add package manually
function addPackage()
    print()
    print("═══════════════════════════")
    print("  TAMBAH PACKAGE MANUAL")
    print("═══════════════════════════")
    print()
    io.write("Nama: ")
    io.flush()
    local name = io.read()
    io.write("Package: ")
    io.flush()
    local package = io.read()
    
    if name and package and name ~= "" and package ~= "" then
        table.insert(packages, {name = name, package = package})
        savePackages()
        print()
        print("✓ Package berhasil ditambahkan!")
    else
        print()
        print("✗ Input tidak valid!")
    end
end

-- List all packages
function listPackages()
    print()
    print("═══════════════════════════")
    print("  DAFTAR PACKAGES")
    print("═══════════════════════════")
    print()
    
    if #packages == 0 then
        print("(Belum ada package)")
    else
        for i, pkg in ipairs(packages) do
            print(i .. ". " .. pkg.name)
            print("   " .. pkg.package)
            print()
        end
        print("Total: " .. #packages .. " package(s)")
    end
    print()
end

-- Remove package
function removePackage()
    print()
    print("═══════════════════════════")
    print("  HAPUS PACKAGE")
    print("═══════════════════════════")
    print()
    
    if #packages == 0 then
        print("✗ Belum ada package!")
        return
    end
    
    listPackages()
    
    io.write("Nomor package yang akan dihapus (0 = batal): ")
    io.flush()
    local num = tonumber(io.read())
    
    if num and num > 0 and num <= #packages then
        local removed = table.remove(packages, num)
        savePackages()
        print()
        print("✓ Package '" .. removed.name .. "' berhasil dihapus!")
    else
        print()
        print("Dibatalkan.")
    end
end

-- Clear all packages
function clearAllPackages()
    print()
    print("═══════════════════════════")
    print("  HAPUS SEMUA PACKAGES")
    print("═══════════════════════════")
    print()
    io.write("⚠ Yakin ingin menghapus semua package? (y/n): ")
    io.flush()
    local confirm = io.read()
    
    if confirm and (confirm:lower() == "y" or confirm:lower() == "yes") then
        packages = {}
        savePackages()
        print()
        print("✓ Semua package berhasil dihapus!")
    else
        print()
        print("Dibatalkan.")
    end
end

-- Launch auto grid
function launchAutoGrid()
    print()
    print("═══════════════════════════════════")
    print("  AUTO GRID LAUNCH")
    print("  Right Side Wide (1:2 Split)")
    print("═══════════════════════════════════")
    print()
    
    if #packages == 0 then
        print("✗ Belum ada package!")
        print()
        io.write("Tekan Enter untuk kembali...")
        io.read()
        return
    end
    
    local numApps = #packages
    local maxApps = math.min(6, numApps)  -- Maximum 6 apps on right side
    local layoutType = "right_3x2"
    
    print("Info:")
    print("• Menggunakan 75% lebar layar (Kanan)")
    print("• Layout: " .. layoutType .. " (3 baris x 2 kolom)")
    print("• Layar kiri kosong untuk konten lain")
    print("• Baris 1 dilindungi dari status bar")
    print()
    
    if numApps > 6 then
        print("⚠ Hanya 6 app pertama yang akan di-launch")
        print("  (layout maksimal: 6 apps)")
        print()
    end
    
    print("Packages yang akan di-launch:")
    for i = 1, maxApps do
        print(i .. ". " .. packages[i].name)
    end
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
    print("a " .. layoutType .. " grid layout on the right side.")
    print("Left side (1/3 of screen) remains empty.")
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
    
    io.write("Posisi grid (1-6): ")
    io.flush()
    local pos = tonumber(io.read())
    
    if pos and pos >= 1 and pos <= 6 then
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
    
    io.write("Posisi baru (1-6): ")
    io.flush()
    local pos = tonumber(io.read())
    
    if pos and pos >= 1 and pos <= 6 then
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
    print("  6. 🔄 Re-detect Display")
    print()
    print("📦 PACKAGE MANAGEMENT:")
    print("  7. 🔍 Auto-Detect Roblox")
    print("  8. Add Package Manual")
    print("  9. List Packages")
    print("  10. Remove Package")
    print("  11. Clear All Packages")
    print()
    print("  0. Exit")
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
    
    -- Detect display configuration
    print("═══════════════════════════")
    print("  INITIALIZING...")
    print("═══════════════════════════")
    print()
    detectDisplay()
    print()
    
    -- Load saved packages
    loadPackages()
    
    print("═══════════════════════════")
    print("  Welcome!")
    print("  Right Side Layout (1:2)")
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
            print()
            print("═══════════════════════════")
            print("  RE-DETECTING DISPLAY")
            print("═══════════════════════════")
            print()
            detectDisplay()
        elseif choice == "7" then
            autoDetectRoblox()
        elseif choice == "8" then
            addPackage()
        elseif choice == "9" then
            listPackages()
        elseif choice == "10" then
            removePackage()
        elseif choice == "11" then
            clearAllPackages()
        elseif choice == "0" or choice == "11" then
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
        
        if choice ~= "0" and choice ~= "11" then
            print()
            io.write("Tekan Enter untuk lanjut...")
            io.read()
        end
    end
end

-- Run the program
main()
