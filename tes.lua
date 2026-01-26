#!/data/data/com.termux/files/usr/bin/lua

-- Auto Grid Freeform v2.0
-- Multi-app grid positioning dengan auto-detection

print("================================")
print("  Auto Grid Freeform v2.0")
print("================================")
print()

-- Display configuration
local DISPLAY_WIDTH = 1080
local DISPLAY_HEIGHT = 2400

-- File untuk menyimpan package list
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"

-- Default packages
local packages = {}

-- Active tasks tracker
local active_tasks = {}

-- Fungsi execute command
function exec(cmd)
    local handle = io.popen("su -c '" .. cmd .. "' 2>&1")
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Fungsi detect orientation
function getOrientation()
    local result = exec("dumpsys window | grep 'mCurrentRotation'")
    
    -- ROTATION_0 atau ROTATION_180 = Portrait
    -- ROTATION_90 atau ROTATION_270 = Landscape
    if result:match("ROTATION_90") or result:match("ROTATION_270") then
        return "landscape"
    else
        return "portrait"
    end
end

-- Fungsi get grid positions based on orientation
function getGridPositions()
    local orientation = getOrientation()
    
    if orientation == "portrait" then
        -- Portrait: 4 grid di setengah bawah layar
        -- Top half (1200px) kosong, bottom half dibagi 4
        return {
            {name = "Kiri Atas", left = 0, top = 1200, right = 540, bottom = 1800},
            {name = "Kanan Atas", left = 540, top = 1200, right = 1080, bottom = 1800},
            {name = "Kiri Bawah", left = 0, top = 1800, right = 540, bottom = 2400},
            {name = "Kanan Bawah", left = 540, top = 1800, right = 1080, bottom = 2400},
        }
    else
        -- Landscape: 4 grid di setengah kanan layar
        -- Left half (1200px) kosong, right half dibagi 4
        return {
            {name = "Kiri Atas", left = 1200, top = 0, right = 1800, bottom = 540},
            {name = "Kanan Atas", left = 1800, top = 0, right = 2400, bottom = 540},
            {name = "Kiri Bawah", left = 1200, top = 540, right = 1800, bottom = 1080},
            {name = "Kanan Bawah", left = 1800, top = 540, right = 2400, bottom = 1080},
        }
    end
end

-- Fungsi save packages
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

-- Fungsi load packages
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

-- Fungsi auto-detect Roblox packages
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
        return
    end
    
    -- Parse packages
    local detected = {}
    for line in result:gmatch("[^\r\n]+") do
        local pkg = line:match("package:(.+)")
        if pkg then
            table.insert(detected, pkg)
        end
    end
    
    if #detected == 0 then
        print("✗ Tidak ada package Roblox ditemukan!")
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
    local choice = io.read()
    
    if choice == "0" or choice == "" then
        print("Batal.")
        return
    end
    
    local toAdd = {}
    
    if choice:lower() == "all" then
        toAdd = detected
    else
        -- Parse comma-separated numbers
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
        -- Check if already exists
        local exists = false
        for _, existing in ipairs(packages) do
            if existing.package == pkg then
                exists = true
                break
            end
        end
        
        if not exists then
            -- Generate name from package
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

-- Fungsi add package manual
function addPackage()
    print()
    print("═══════════════════════════")
    print("  ADD PACKAGE MANUAL")
    print("═══════════════════════════")
    print()
    
    io.write("Nama App: ")
    local name = io.read()
    
    if not name or name == "" then
        print("✗ Nama tidak boleh kosong!")
        return
    end
    
    io.write("Package Name: ")
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

-- Fungsi list packages
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

-- Fungsi remove package
function removePackage()
    print()
    
    if #packages == 0 then
        print("✗ Tidak ada package!")
        return
    end
    
    listPackages()
    
    io.write("Hapus nomor (0 = batal): ")
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

-- Fungsi clear all packages
function clearAllPackages()
    print()
    io.write("Hapus SEMUA package? (yes/no): ")
    local confirm = io.read()
    
    if confirm:lower() == "yes" or confirm:lower() == "y" then
        packages = {}
        savePackages()
        print("✓ Semua package dihapus!")
    else
        print("Batal.")
    end
end

-- Fungsi get task ID
function getTaskId(package)
    local result = exec("dumpsys activity activities | grep '" .. package .. "'")
    local taskId = result:match("#(%d+)")
    
    if not taskId then
        taskId = result:match("t(%d+)")
    end
    
    return taskId
end

-- Fungsi enable freeform
function enableFreeform()
    exec("settings put global enable_freeform_support 1")
    exec("settings put global force_resizable_activities 1")
    exec("settings put global force_freeform_windows 1")
end

-- Fungsi launch app
function launchFreeform(package, appName)
    print("→ Launching " .. appName .. "...")
    exec("am force-stop " .. package)
    exec("am start --windowingMode 5 " .. package)
    
    os.execute("sleep 3")
    
    local taskId = getTaskId(package)
    if taskId then
        print("✓ Task ID: " .. taskId)
        active_tasks[package] = taskId
        return taskId
    else
        os.execute("sleep 2")
        taskId = getTaskId(package)
        if taskId then
            print("✓ Task ID: " .. taskId)
            active_tasks[package] = taskId
            return taskId
        else
            print("✗ Failed to get task ID")
            return nil
        end
    end
end

-- Fungsi resize window
function resizeToGrid(taskId, position)
    local grid_positions = getGridPositions()
    local pos = grid_positions[position]
    
    if not pos then
        print("✗ Invalid position!")
        return false
    end
    
    print("→ Positioning to: " .. pos.name)
    local cmd = string.format(
        "am task resize %s %d %d %d %d",
        taskId, pos.left, pos.top, pos.right, pos.bottom
    )
    
    exec(cmd)
    os.execute("sleep 1")
    
    print("✓ Positioned!")
    return true
end

-- Fungsi show grid layout
function showGridLayout()
    local orientation = getOrientation()
    
    print()
    print("Current Orientation: " .. orientation:upper())
    print()
    
    if orientation == "portrait" then
        print("Grid Layout (Portrait):")
        print()
        print("┌─────────────────────┐")
        print("│                     │")
        print("│    KOSONG (ATAS)    │")
        print("│                     │")
        print("├──────────┬──────────┤")
        print("│    1     │    2     │")
        print("│  Kiri    │  Kanan   │")
        print("│  Atas    │  Atas    │")
        print("├──────────┼──────────┤")
        print("│    3     │    4     │")
        print("│  Kiri    │  Kanan   │")
        print("│  Bawah   │  Bawah   │")
        print("└──────────┴──────────┘")
    else
        print("Grid Layout (Landscape):")
        print()
        print("┌────────────┬──────────┬──────────┐")
        print("│            │    1     │    2     │")
        print("│            │  Kiri    │  Kanan   │")
        print("│   KOSONG   │  Atas    │  Atas    │")
        print("│   (KIRI)   ├──────────┼──────────┤")
        print("│            │    3     │    4     │")
        print("│            │  Kiri    │  Kanan   │")
        print("│            │  Bawah   │  Bawah   │")
        print("└────────────┴──────────┴──────────┘")
    end
    print()
end

-- Fungsi AUTO GRID - Launch all packages
function launchAutoGrid()
    print()
    print("═══════════════════════════════════")
    print("  AUTO GRID LAUNCH")
    print("═══════════════════════════════════")
    print()
    
    if #packages == 0 then
        print("✗ Belum ada package!")
        print("  Gunakan 'Auto-Detect Roblox' atau 'Add Package'")
        return
    end
    
    if #packages > 4 then
        print("⚠ Warning: Lebih dari 4 package detected!")
        print("  Hanya 4 pertama yang akan di-launch.")
        print()
    end
    
    local orientation = getOrientation()
    print("Orientation: " .. orientation:upper())
    print()
    
    enableFreeform()
    
    local max_apps = math.min(4, #packages)
    
    print("→ Launching " .. max_apps .. " apps...")
    print()
    
    for i = 1, max_apps do
        local pkg = packages[i]
        print("[ APP " .. i .. " ] " .. pkg.name)
        
        local taskId = launchFreeform(pkg.package, pkg.name)
        
        if taskId then
            resizeToGrid(taskId, i)
        else
            print("✗ Failed to launch")
        end
        
        print()
        
        -- Small delay between launches
        if i < max_apps then
            os.execute("sleep 1")
        end
    end
    
    print("═══════════════════════════════════")
    print("✓ AUTO GRID COMPLETE!")
    print("═══════════════════════════════════")
    
    showGridLayout()
end

-- Fungsi launch single app
function launchSingleApp()
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
    io.write("Pilihan: ")
    local choice = tonumber(io.read())
    
    if not choice or not packages[choice] then
        print("✗ Pilihan tidak valid!")
        return
    end
    
    local pkg = packages[choice]
    
    enableFreeform()
    local taskId = launchFreeform(pkg.package, pkg.name)
    
    if taskId then
        print()
        showGridLayout()
        io.write("Posisi grid (1-4): ")
        local pos = tonumber(io.read())
        
        if pos and pos >= 1 and pos <= 4 then
            resizeToGrid(taskId, pos)
        end
    end
end

-- Fungsi move active app
function moveActiveApp()
    print()
    
    if #packages == 0 then
        print("✗ Belum ada package!")
        return
    end
    
    print("Pilih App:")
    for i, pkg in ipairs(packages) do
        local status = active_tasks[pkg.package] and " (active)" or ""
        print(i .. ". " .. pkg.name .. status)
    end
    print()
    io.write("Pilihan: ")
    local choice = tonumber(io.read())
    
    if not choice or not packages[choice] then
        print("✗ Pilihan tidak valid!")
        return
    end
    
    local pkg = packages[choice]
    local taskId = active_tasks[pkg.package] or getTaskId(pkg.package)
    
    if taskId then
        print()
        showGridLayout()
        io.write("Posisi baru (1-4): ")
        local pos = tonumber(io.read())
        
        if pos and pos >= 1 and pos <= 4 then
            resizeToGrid(taskId, pos)
        end
    else
        print("✗ App tidak aktif! Launch dulu.")
    end
end

-- Fungsi show active tasks
function showActiveTasks()
    print()
    print("Active Tasks:")
    
    if next(active_tasks) == nil then
        print("  (Belum ada)")
    else
        for pkg, taskId in pairs(active_tasks) do
            -- Find name
            local name = pkg
            for _, p in ipairs(packages) do
                if p.package == pkg then
                    name = p.name
                    break
                end
            end
            print("  • " .. name .. " → Task #" .. taskId)
        end
    end
    print()
end

-- Main menu
function showMenu()
    print()
    print("═══════════════════════════")
    print("  AUTO GRID MENU")
    print("═══════════════════════════")
    print("1. 🚀 AUTO GRID LAUNCH")
    print("2. Launch Single App")
    print("3. Move Active App")
    print("4. Show Grid Layout")
    print("5. Show Active Tasks")
    print()
    print("--- Package Management ---")
    print("6. 🔍 Auto-Detect Roblox")
    print("7. Add Package Manual")
    print("8. List Packages")
    print("9. Remove Package")
    print("10. Clear All Packages")
    print()
    print("11. Keluar")
    print()
    io.write("Pilihan: ")
    return io.read()
end

-- Main program
function main()
    loadPackages()
    
    if #packages > 0 then
        print("Loaded " .. #packages .. " package(s)")
    else
        print("Tip: Gunakan 'Auto-Detect Roblox' untuk scan packages!")
    end
    
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
            print("Terima kasih! 👋")
            break
            
        else
            print("✗ Pilihan tidak valid!")
        end
        
        print()
        io.write("Tekan Enter untuk lanjut...")
        io.read()
    end
end

-- Run
main()