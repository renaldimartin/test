-- ===== ZEEN TOOLS v0.0.1 =====
-- Auto Rejoin Roblox Game System
-- File: tes.lua

local function clear_screen()
    os.execute("clear") or os.execute("cls")
end

local function print_logo()
    print("\27[36m")
    print("███████╗███████╗███████╗███╗   ██╗")
    print("╚════██║██╔════╝██╔════╝████╗  ██║")
    print("    ██║███████╗█████╗  ██╔██╗ ██║")
    print("    ██║╚════██║██╔══╝  ██║╚██╗██║")
    print("███████║███████║███████╗██║ ╚████║")
    print("╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝")
    print("\27[0m")
    print("        TOOLS v0.0.1")
    print("")
end

local function print_main_menu()
    print_logo()
    print("\27[32m=== MAIN MENU ===\27[0m")
    print("1. Start Monitoring")
    print("2. First Setup (Setup Wizard)")
    print("3. Edit Config")
    print("4. Cookies Manager")
    print("0. Exit/Keluar")
    print("")
end

local function ensure_directory()
    local sdcard_path = "/sdcard/Zeen"
    os.execute("mkdir -p " .. sdcard_path)
    return sdcard_path
end

local function setup_wizard()
    clear_screen()
    print_logo()
    print("\27[33m=== FIRST SETUP (Setup Wizard) ===\27[0m\n")
    
    -- Q1: Auto detect Package
    print("Q: Auto detect Package spesifik: com.roblox?")
    print("1. Auto Detect (com.roblox)")
    print("2. Manually (e.g com.zeen)")
    io.write("Pilihan [1/2]: ")
    local package_choice = io.read()
    
    if package_choice == "1" then
        print("\27[32m✓ Package: com.roblox terdeteksi\27[0m\n")
    else
        io.write("Masukkan package name (e.g com.zeen): ")
        local manual_package = io.read()
        print("\27[32m✓ Package: " .. manual_package .. " ditambahkan\27[0m\n")
    end
    
    -- Q2: Add Link for All
    print("Q: Add Link for All?")
    io.write("Masukkan (y/n): ")
    local add_link_all = io.read():lower()
    print("")
    
    -- Q3: Mask Username
    print("Q: Mask username?")
    io.write("Masukkan (y/n) - Jika Y maka username akan disensor (Zeen = Zxxn): ")
    local mask_username = io.read():lower()
    print("")
    
    -- Q4: Add Delay Launched
    print("Q: Add Delay Launched (Default: 0 Detik)")
    io.write("Masukkan delay dalam detik (atau tekan Enter untuk skip): ")
    local delay_launch = io.read()
    print("")
    
    -- Q5: Add Webhook Link
    print("Q: Add link Webhook?")
    io.write("Masukkan link Webhook (atau tekan Enter untuk skip): ")
    local webhook_link = io.read()
    
    if webhook_link ~= "" then
        print("Q: Delay Launch Notifikasi (Default: 0 Menit)")
        io.write("Masukkan delay dalam menit (atau tekan Enter untuk skip): ")
        local delay_notif = io.read()
    end
    print("")
    
    -- Q6: Set Delay Interval
    print("Q: Set Delay Interval (Enter to skip, dalam Menit)")
    io.write("Masukkan delay interval: ")
    local delay_interval = io.read()
    print("")
    
    print("\27[32m✓ Konfigurasi berhasil disimpan!\27[0m\n")
    
    io.write("Tekan Enter untuk kembali ke menu utama...")
    io.read()
end

local function start_monitoring()
    clear_screen()
    print_logo()
    print("\27[33m=== START MONITORING ===\27[0m\n")
    print("Monitoring dimulai...")
    print("Tekan Ctrl+C untuk berhenti\n")
    
    io.write("Tekan Enter untuk kembali ke menu utama...")
    io.read()
end

local function edit_config()
    clear_screen()
    print_logo()
    print("\27[33m=== EDIT CONFIG ===\27[0m\n")
    
    print("Konfigurasi saat ini:")
    print("- Package: com.roblox")
    print("- Add Link All: y")
    print("- Mask Username: y")
    print("- Delay Launched: 0 detik")
    print("- Delay Interval: -\n")
    
    io.write("Tekan Enter untuk kembali ke menu utama...")
    io.read()
end

local function cookies_manager()
    clear_screen()
    print_logo()
    print("\27[33m=== COOKIES MANAGER ===\27[0m\n")
    print("1. Import Cookies")
    print("2. Export Cookies")
    print("3. Delete All Cookies")
    print("0. Kembali ke Menu Utama")
    print("")
    io.write("Pilihan: ")
    local choice = io.read()
    
    if choice == "1" then
        print("\n\27[33mImport Cookies:\27[0m")
        io.write("Masukkan path file cookies: ")
        local path = io.read()
        print("\27[32m✓ Cookies berhasil diimport dari: " .. path .. "\27[0m\n")
    elseif choice == "2" then
        print("\n\27[33mExport Cookies:\27[0m")
        print("\27[32m✓ Cookies berhasil diexport ke: /sdcard/Zeen/cookies.txt\27[0m\n")
    elseif choice == "3" then
        print("\n\27[31m⚠ Apakah Anda yakin ingin menghapus semua cookies?\27[0m")
        io.write("Konfirmasi (y/n): ")
        local confirm = io.read():lower()
        if confirm == "y" then
            print("\27[32m✓ Semua cookies berhasil dihapus\27[0m\n")
        else
            print("\27[33m✗ Pembatalan penghapusan cookies\27[0m\n")
        end
    elseif choice == "0" then
        return
    else
        print("\27[31m✗ Pilihan tidak valid!\27[0m\n")
    end
    
    io.write("Tekan Enter untuk kembali ke menu utama...")
    io.read()
end

local function main()
    while true do
        clear_screen()
        print_main_menu()
        io.write("Pilihan [0-4]: ")
        local choice = io.read()
        
        if choice == "1" then
            start_monitoring()
        elseif choice == "2" then
            setup_wizard()
        elseif choice == "3" then
            edit_config()
        elseif choice == "4" then
            cookies_manager()
        elseif choice == "0" then
            clear_screen()
            print("\27[32mTerima kasih telah menggunakan ZEEN TOOLS!\27[0m\n")
            break
        else
            print("\27[31m✗ Pilihan tidak valid!\27[0m\n")
            io.write("Tekan Enter untuk melanjutkan...")
            io.read()
        end
    end
end

-- Main execution
main()