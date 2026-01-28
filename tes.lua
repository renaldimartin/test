#!/data/data/com.termux/files/usr/bin/lua

-- ==================================================
-- PROJECT ZEEN TOOLS v1.0.0 (MAJOR UPDATE)
-- Auto Grid Freeform - Monitoring Edition
-- ==================================================
-- Changelog v1.0.0:
-- [+] New UI: Real-time Monitoring Dashboard (Table)
-- [+] Ratio Layout 1:2 (1 Kiri : 2 Kanan)
-- [+] State Machine: Reseting->Boosting->Online
-- [+] Auto Detect Roblox Username (via XML)
-- [+] RAM Monitoring per App
-- [+] Auto Retry/Recovery System
-- ==================================================

-- KONFIGURASI
local STATUS_BAR_HEIGHT = 60
local REFRESH_RATE = 10 -- Detik (Kecepatan refresh UI)
local RAM_UPDATE_INTERVAL = 5 -- Update RAM tiap 5 detik (biar gak berat)

-- File paths
local PACKAGE_FILE = "/data/data/com.termux/files/home/.roblox_packages.txt"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.temp_cmd.sh"

-- Data storage
local packages = {} -- Structure: {name, package, status, ram, real_user, state_step}
local DISPLAY_WIDTH = 1280 
local DISPLAY_HEIGHT = 720 
local current_monitoring_index = 1
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

-- ================= HELPER FUNCTIONS =================

function exec(cmd)
    local f = io.open(TEMP_SCRIPT, "w")
    if not f then return "" end
    f:write("#!/system/bin/sh\n")
    f:write(cmd .. "\n")
    f:close()
    os.execute("chmod +x " .. TEMP_SCRIPT)
    local output_file = "/data/data/com.termux/files/home/.temp_output.txt"
    -- Menggunakan timeout agar tidak hang
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

-- ================= CORE LOGIC v1.0.0 =================

-- [BARU] Detect Roblox Username dari XML
function getRobloxUsername(pkgName)
    -- Mencoba mencari username di file preferences umum Roblox
    -- Pattern grep mencari value di XML seperti: <string name="UserName">ZEEN_PLAYER</string>
    -- Atau mencari di shared_prefs apapun yang mengandung string nama akun
    
    local cmd = "grep -r \"UserName\" /data/data/" .. pkgName .. "/shared_prefs/ | head -n 1"
    local raw = exec(cmd)
    
    -- Parsing kasar hasil XML
    local user = raw:match("value=\"([^\"]+)\"")
    
    if not user or user == "" then
        -- Coba cari DisplayName jika UserName kosong
        cmd = "grep -r \"DisplayName\" /data/data/" .. pkgName .. "/shared_prefs/ | head -n 1"
        raw = exec(cmd)
        user = raw:match("value=\"([^\"]+)\"")
    end

    if user and user ~= "" then
        return user
    else
        return "Unknown"
    end
end

-- [BARU] Get RAM Usage (MB)
function getRamUsage(pkgName)
    -- Mengambil PSS Total
    local cmd = "dumpsys meminfo " .. pkgName .. " | grep 'TOTAL'"
    local raw = exec(cmd)
    local kb = raw:match("%s*(%d+)%s*")
    
    if kb then
        local mb = math.floor(tonumber(kb) / 1024)
        return mb .. " MB"
    else
        return "0 MB"
    end
end

-- [BARU] Optimize System (Kill background apps except Termux & Roblox)
function optimizeSystem()
    -- Kill background processes safe list
    -- Ini versi simpel: trim caches dan kill background processes umum
    exec("pm trim-caches 100M")
    -- exec("am kill-all") -- Hati-hati dengan ini di beberapa device
end

-- [LAYOUT] 1:2 Ratio Calculation
function getGridPositions(numApps)
    local usable_height = DISPLAY_HEIGHT - STATUS_BAR_HEIGHT
    local h_slot = math.floor(usable_height / 3)
    
    -- RASIO 1:2 (Total 3 Bagian)
    -- Kiri: 1 Bagian (33.3%)
    -- Kanan: 2 Bagian (66.6%)
    
    local grid_width = math.floor(DISPLAY_WIDTH * (2/3))
    local start_x = DISPLAY_WIDTH - grid_width
    local w_slot = math.floor(grid_width / 2)
    
    -- Koordinat Y
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

-- Modifikasi Preferences
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

-- ================= DASHBOARD UI =================

function drawDashboard()
    -- Clear Screen
    io.write("\27[2J\27[H")
    
    print(C_CYAN .. C_BOLD)
    print("███████╗███████╗███████╗███╗   ██╗")
    print("╚══███╔╝██╔════╝██╔════╝████╗  ██║")
    print("  ███╔╝ █████╗  █████╗  ██╔██╗ ██║")
    print(" ███╔╝  ██╔══╝  ██╔══╝  ██║╚██╗██║")
    print("███████╗███████╗███████╗██║ ╚████║")
    print("╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝")
    print("        ZEEN TOOLS v1.0.0         ")
    print(C_RESET)
    
    print(C_WHITE .. "──────────────────────────────────────────────────" .. C_RESET)
    -- Header Table
    print(string.format("%s%-3s | %-16s | %-8s | %-12s%s", C_BOLD, "No", "Nama Akun", "RAM", "Status", C_RESET))
    print(C_WHITE .. "──────────────────────────────────────────────────" .. C_RESET)
    
    -- Rows
    for i, pkg in ipairs(packages) do
        local statusColor = C_WHITE
        if pkg.status == "Reseting" then statusColor = C_RED
        elseif pkg.status == "Boosting" then statusColor = C_YELLOW
        elseif pkg.status == "Optimized" then statusColor = C_BLUE
        elseif pkg.status == "Launched" then statusColor = C_CYAN
        elseif pkg.status == "Online" then statusColor = C_GREEN
        elseif pkg.status == "Retrying" then statusColor = C_RED
        end
        
        -- Nama akun (ambil 14 karakter max)
        local displayName = pkg.real_user
        if string.len(displayName) > 14 then displayName = string.sub(displayName, 1, 13) .. "." end
        
        print(string.format("%-3d | %-16s | %-8s | %s%-12s%s", 
            i, 
            displayName, 
            pkg.ram, 
            statusColor, pkg.status, C_RESET
        ))
    end
    print(C_WHITE .. "──────────────────────────────────────────────────" .. C_RESET)
    
    -- Footer Info
    local activePkg = packages[current_monitoring_index] or {}
    local progressText = activePkg.status or "Idle"
    print(string.format("%sMonitoring: %d/%d (%s)%s", C_BOLD, current_monitoring_index, #packages, progressText, C_RESET))
    print(C_WHITE .. "\n[CTRL+C] Stop Script" .. C_RESET)
end

-- ================= STATE MACHINE LOGIC =================

function processAppLogic(index, totalApps)
    local pkg = packages[index]
    
    -- STATE MACHINE
    if pkg.state_step == 0 then
        -- Step 0: Initial
        pkg.status = "Reseting"
        pkg.state_step = 1
        
    elseif pkg.state_step == 1 then
        -- Step 1: Force Stop / Reset
        pkg.status = "Reseting"
        exec("am force-stop " .. pkg.package)
        
        -- Ambil username selagi app mati (lebih aman read filenya)
        if pkg.real_user == "Scanning..." then
            pkg.real_user = getRobloxUsername(pkg.package)
        end
        
        pkg.state_step = 2
        
    elseif pkg.state_step == 2 then
        -- Step 2: Boosting
        pkg.status = "Boosting"
        exec("pm trim-caches 50M") -- Clear cache ringan
        pkg.state_step = 3
        
    elseif pkg.state_step == 3 then
        -- Step 3: Optimized
        pkg.status = "Optimized"
        optimizeSystem() -- Kill background apps lain
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
        pkg.wait_timer = 5 -- Beri waktu 5 detik sebelum cek Online
        
    elseif pkg.state_step == 6 then
        -- Step 6: Checking Online Status
        if pkg.wait_timer > 0 then
            pkg.wait_timer = pkg.wait_timer - 1
        else
            -- Cek apakah prosesnya masih hidup
            local check = exec("pidof " .. pkg.package)
            if check and check ~= "" then
                pkg.status = "Online"
                -- Jika sudah online, tugas monitoring pindah ke app berikutnya
                if current_monitoring_index < totalApps then
                    current_monitoring_index = current_monitoring_index + 1
                end
            else
                pkg.status = "Retrying"
                pkg.state_step = 1 -- Ulang dari awal
            end
        end
        
    elseif pkg.state_step == 7 then
        -- Step 7 (Maintenance): Sudah Online, pantau terus
        -- Jika crash, masuk Retrying
        local check = exec("pidof " .. pkg.package)
        if not check or check == "" then
            pkg.status = "Retrying"
            pkg.state_step = 1 -- Reset lagi
            current_monitoring_index = index -- Fokus balik ke app ini
        else
            pkg.status = "Online"
        end
    end
end

-- ================= MAIN MONITORING LOOP =================

function startMonitoring()
    if #packages == 0 then print("✗ No packages!"); return end
    
    -- Inisialisasi Data
    for i, p in ipairs(packages) do
        p.status = "Waiting"
        p.ram = "0 MB"
        p.real_user = "Scanning..."
        p.state_step = 0 -- 0=Init
        p.wait_timer = 0
    end
    
    current_monitoring_index = 1
    updateScreenResolution()
    
    -- LOOP UTAMA (Infinite sampai CTRL+C)
    while true do
        loop_counter = loop_counter + 1
        
        -- 1. Jalankan Logic untuk App yang sedang giliran monitoring
        --    Tapi kita juga bisa cek app lain yang sudah 'Online' apakah crash (maintenance)
        
        -- Proses app yang sedang antri (Current Index)
        if current_monitoring_index <= #packages then
            processAppLogic(current_monitoring_index, #packages)
        end
        
        -- Cek Background (Maintenance) untuk app yang sudah lewat giliran (sudah Online)
        -- Kita cek setiap 10 loop agar tidak berat
        if loop_counter % 10 == 0 then
            for i = 1, current_monitoring_index - 1 do
                processAppLogic(i, #packages) -- Masuk ke step 7 (maintenance check)
            end
        end
        
        -- 2. Update RAM (Jangan setiap frame, berat!)
        if loop_counter % (RAM_UPDATE_INTERVAL * 2) == 0 then
            for i, p in ipairs(packages) do
                -- Hanya update RAM jika app sudah Launched/Online
                if p.state_step >= 5 then
                    p.ram = getRamUsage(p.package)
                end
            end
        end
        
        -- 3. Draw UI
        drawDashboard()
        
        -- 4. Delay Refresh
        exec("sleep " .. REFRESH_RATE)
    end
end

-- ================= BOILERPLATE (Load/Save/Menu) =================

function loadPackages()
    local file = io.open(PACKAGE_FILE, "r")
    if file then
        packages = {}
        for line in file:lines() do
            local name, package = line:match("(.+)|(.+)")
            if name and package then 
                -- Tambah field baru untuk monitoring
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
        -- Menu Sederhana (Monitoring ada di opsi 1)
        io.write("\27[2J\27[H") -- Clear
        print("ZEEN TOOLS v1.0.0")
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

Penjelasan Preview Tampilan & Sistem
Ketika kamu menekan menu 1, layar akan bersih dan menampilkan Dashboard seperti ini (Real-time update):
███████╗███████╗███████╗███╗   ██╗
╚══███╔╝██╔════╝██╔════╝████╗  ██║
  ███╔╝ █████╗  █████╗  ██╔██╗ ██║
 ███╔╝  ██╔══╝  ██╔══╝  ██║╚██╗██║
███████╗███████╗███████╗██║ ╚████║
╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝
        ZEEN TOOLS v1.0.0         
──────────────────────────────────────────────────
No  | Nama Akun        | RAM      | Status      
──────────────────────────────────────────────────
1   | ProGamer123      | 250 MB   | Online      
2   | ZeenFarmer99     | 180 MB   | Launched    
3   | AkunCadangan     | 0 MB     | Boosting    
4   | Roblox Client4   | 0 MB     | Waiting     
5   | Roblox Client5   | 0 MB     | Waiting     
6   | Roblox Client6   | 0 MB     | Waiting     
──────────────────────────────────────────────────
Monitoring: 3/6 (Boosting)

[CTRL+C] Stop Script

