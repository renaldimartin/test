#!/data/data/com.termux/files/usr/bin/lua

--[[
    ZEEN TOOLS v1.0.0 (Fixed)
    - Safe Cache Clearing (No Data Loss)
    - Flicker-Free Monitoring
    - Full Setup Wizard
]]

-- ==========================================
-- CONFIGURATION & GLOBALS
-- ==========================================

local CONFIG_FILE = "/data/data/com.termux/files/home/.zeen_config.dat"
local PACKAGE_FILE = "/data/data/com.termux/files/home/.zeen_packages.dat"
local WEBHOOK_FILE = "/data/data/com.termux/files/home/.zeen_webhook.dat"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.zeen_exec.sh"

-- Display
local DISPLAY_WIDTH = 1280
local DISPLAY_HEIGHT = 720

-- State
local config = {
    delay_launch = 10,
    clear_cache_interval = 30, -- minutes
    clear_cache_enabled = true,
    rejoin_interval = 0, -- hours (0 = off)
    device_name = "Android Device"
}
local webhook_config = {
    url = "",
    interval = 0
}
local packages = {}
local app_states = {} -- Stores detailed state per app
local last_webhook_time = 0
local last_global_cache_clean = 0

-- ANSI Colors & Controls
local C_RESET = "\27[0m"
local C_RED = "\27[31m"
local C_GREEN = "\27[32m"
local C_YELLOW = "\27[33m"
local C_BLUE = "\27[34m"
local C_MAGENTA = "\27[35m"
local C_CYAN = "\27[36m"
local C_WHITE = "\27[37m"
local C_BOLD = "\27[1m"
local C_HOME = "\27[H"   -- Move cursor to top-left
local C_CLEAR = "\27[2J" -- Clear screen completely
local C_HIDE = "\27[?25l" -- Hide cursor
local C_SHOW = "\27[?25h" -- Show cursor

-- ==========================================
-- UTILITY FUNCTIONS
-- ==========================================

function sleep(n)
    os.execute("sleep " .. tonumber(n))
end

-- Execute Root Command safely
function exec(cmd)
    local f = io.open(TEMP_SCRIPT, "w")
    if not f then return "" end
    f:write("#!/system/bin/sh\n")
    f:write(cmd .. "\n")
    f:close()
    
    os.execute("chmod +x " .. TEMP_SCRIPT)
    local output_file = "/data/data/com.termux/files/home/.zeen_output.txt"
    os.execute("su -c '" .. TEMP_SCRIPT .. " > " .. output_file .. " 2>&1'")
    
    local result = ""
    local rf = io.open(output_file, "r")
    if rf then
        result = rf:read("*a")
        rf:close()
    end
    
    os.remove(TEMP_SCRIPT)
    os.remove(output_file)
    if result then result = result:gsub("^%s*(.-)%s*$", "%1") end
    return result
end

function get_device_name()
    local model = exec("getprop ro.product.model")
    if model and model ~= "" then config.device_name = model end
end

-- ==========================================
-- FILE I/O
-- ==========================================

function split(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do table.insert(t, str) end
    return t
end

function save_data()
    -- Packages
    local f = io.open(PACKAGE_FILE, "w")
    if f then
        for _, pkg in ipairs(packages) do
            f:write(pkg.name .. "|" .. pkg.package .. "|" .. (pkg.ps_link or "") .. "\n")
        end
        f:close()
    end
    
    -- Config
    f = io.open(CONFIG_FILE, "w")
    if f then
        f:write("delay_launch=" .. config.delay_launch .. "\n")
        f:write("clear_cache_interval=" .. config.clear_cache_interval .. "\n")
        f:write("clear_cache_enabled=" .. tostring(config.clear_cache_enabled) .. "\n")
        f:write("rejoin_interval=" .. config.rejoin_interval .. "\n")
        f:close()
    end
    
    -- Webhook
    f = io.open(WEBHOOK_FILE, "w")
    if f then
        f:write("url=" .. webhook_config.url .. "\n")
        f:write("interval=" .. webhook_config.interval .. "\n")
        f:close()
    end
end

function load_data()
    -- Load Packages
    local f = io.open(PACKAGE_FILE, "r")
    if f then
        packages = {}
        for line in f:lines() do
            local parts = split(line, "|")
            if #parts >= 2 then
                table.insert(packages, {name=parts[1], package=parts[2], ps_link=parts[3] or ""})
            end
        end
        f:close()
    end
    
    -- Load Config
    f = io.open(CONFIG_FILE, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("(.-)=(.+)")
            if k == "delay_launch" then config.delay_launch = tonumber(v) end
            if k == "clear_cache_interval" then config.clear_cache_interval = tonumber(v) end
            if k == "clear_cache_enabled" then config.clear_cache_enabled = (v == "true") end
            if k == "rejoin_interval" then config.rejoin_interval = tonumber(v) end
        end
        f:close()
    end
    
    -- Load Webhook
    f = io.open(WEBHOOK_FILE, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("(.-)=(.+)")
            if k == "url" then webhook_config.url = v end
            if k == "interval" then webhook_config.interval = tonumber(v) end
        end
        f:close()
    end
    get_device_name()
end

-- ==========================================
-- LOGIC: GRID & SYSTEM
-- ==========================================

function get_grid_pos(index)
    local idx = (index - 1) % 6 -- 0 to 5
    local w = math.floor(DISPLAY_WIDTH / 2)
    local h = math.floor(DISPLAY_HEIGHT / 3)
    
    local col = idx % 2 -- 0 or 1
    local row = math.floor(idx / 2) -- 0, 1, or 2
    
    return {
        left = col * w,
        top = row * h,
        right = (col * w) + w,
        bottom = (row * h) + h
    }
end

function modify_xml(package, index)
    local pos = get_grid_pos(index)
    local pref_file = exec("ls /data/data/" .. package .. "/shared_prefs/*preferences.xml 2>/dev/null | head -n 1")
    
    if not pref_file or pref_file == "" then return false end
    
    -- Use specific values to avoid regex complexity issues in minimal environments
    local cmds = {
        "sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_left\\\" value=\\\""..pos.left.."\\\"/' " .. pref_file,
        "sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_top\\\" value=\\\""..pos.top.."\\\"/' " .. pref_file,
        "sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_right\\\" value=\\\""..pos.right.."\\\"/' " .. pref_file,
        "sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_bottom\\\" value=\\\""..pos.bottom.."\\\"/' " .. pref_file
    }
    for _, cmd in ipairs(cmds) do exec(cmd) end
    return true
end

function get_ram_usage(package)
    local pid = exec("pidof " .. package)
    if not pid or pid == "" then return "0MB" end
    local rss = exec("ps -o rss -p " .. pid .. " | tail -n 1")
    if rss and tonumber(rss) then return math.floor(tonumber(rss) / 1024) .. "MB" end
    return "?MB"
end

-- ==========================================
-- WEBHOOK
-- ==========================================

function send_webhook()
    if webhook_config.url == "" then return end
    
    local fields = {}
    local online_count, offline_count = 0, 0
    
    for i, pkg in ipairs(packages) do
        local st = app_states[pkg.package]
        local is_online = (st and st.status == "ONLINE")
        if is_online then online_count = online_count + 1 else offline_count = offline_count + 1 end
        
        local icon = is_online and "🟢" or "🔴"
        local ram = is_online and get_ram_usage(pkg.package) or "-"
        local time_online = "-"
        if is_online and st.online_start then
             local diff = os.time() - st.online_start
             local h = math.floor(diff/3600)
             local m = math.floor((diff%3600)/60)
             time_online = string.format("%02dh %02dm", h, m)
        end
        
        local desc_val = is_online and 
            string.format("⏱️ %s | 💾 %s", time_online, ram) or 
            "Offline"
            
        table.insert(fields, string.format([[{"name": "%s **%s**", "value": "`%s`", "inline": true}]], icon, pkg.name, desc_val))
    end
    
    local json = string.format([[
    {
        "username": "ZEEN TOOLS",
        "avatar_url": "https://i.imgur.com/4M34hi2.png",
        "embeds": [{
            "title": "ZEEN MONITORING STATUS",
            "color": 3066993,
            "fields": [
                { "name": "Device", "value": "%s", "inline": true },
                { "name": "Status", "value": "🟢 On: %d | 🔴 Off: %d | 🤖 Tot: %d", "inline": false },
                %s
            ],
            "footer": { "text": "ZEEN TOOLS | %s" }
        }]
    }
    ]], config.device_name, online_count, offline_count, #packages, table.concat(fields, ","), os.date("%H:%M %d-%b-%Y"))
    
    local f = io.open("/data/data/com.termux/files/home/.zeen_pl.json", "w")
    f:write(json)
    f:close()
    exec("curl -s -H \"Content-Type: application/json\" -d @/data/data/com.termux/files/home/.zeen_pl.json \"" .. webhook_config.url .. "\" > /dev/null")
end

-- ==========================================
-- MONITORING (NO FLICKER)
-- ==========================================

function start_monitoring()
    if #packages == 0 then
        print(C_RED .. "✗ No packages configured!" .. C_RESET)
        sleep(2)
        return
    end

    -- Init States
    for _, pkg in ipairs(packages) do
        app_states[pkg.package] = { 
            status = "RESETTING", 
            last_update = os.time(), 
            online_start = nil 
        }
    end
    
    print(C_CLEAR) -- Clear ONLY ONCE at start
    io.write(C_HIDE) -- Hide cursor
    
    local running = true
    while running do
        local now = os.time()
        
        -- Auto Clear Cache Global Check
        if config.clear_cache_enabled and (now - last_global_cache_clean) > (config.clear_cache_interval * 60) then
            last_global_cache_clean = now
            -- We don't block here, individual app logic handles specific cleaning
        end

        -- PRINT UI (Overwriting from top)
        io.write(C_HOME) 
        print(C_GREEN .. [[
███████╗███████╗███████╗███╗   ██╗
╚══███╔╝██╔════╝██╔════╝████╗  ██║
  ███╔╝ █████╗  █████╗  ██╔██╗ ██║
 ███╔╝  ██╔══╝  ██╔══╝  ██║╚██╗██║
███████╗███████╗███████╗██║ ╚████║
╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝
        ZEEN TOOLS v1.0.0
]] .. C_RESET)
        
        print(C_CYAN .. "  Dev: " .. config.device_name .. C_RESET)
        print(C_WHITE .. "  Status: " .. (config.clear_cache_enabled and "Auto-Clean ON" or "Auto-Clean OFF") .. " | Delay: " .. config.delay_launch .. "s" .. C_RESET)
        print()
        
        -- Table Header
        print(string.format(C_BOLD .. "  %-3s %-20s %-12s %-8s %-10s" .. C_RESET, "NO", "NAME", "STATUS", "RAM", "UPTIME"))
        print(C_WHITE .. "  ────────────────────────────────────────────────────────────" .. C_RESET)
        
        for i, pkg in ipairs(packages) do
            local st = app_states[pkg.package]
            local pkg_name = pkg.package
            
            -- === STATE MACHINE ===
            if st.status == "RESETTING" then
                exec("am force-stop " .. pkg_name)
                st.status = "BOOSTING"
                st.last_update = now
                st.online_start = nil
                
            elseif st.status == "BOOSTING" then
                -- SAFE CLEAR: ONLY DELETE CACHE FOLDER
                exec("rm -rf /data/data/" .. pkg_name .. "/cache/*")
                exec("rm -rf /data/data/" .. pkg_name .. "/code_cache/*")
                -- NEVER USE 'pm clear' here
                st.status = "OPTIMIZED"
                
            elseif st.status == "OPTIMIZED" then
                modify_xml(pkg_name, i)
                st.status = "READY"
                
            elseif st.status == "READY" then
                if pkg.ps_link and pkg.ps_link ~= "" then
                    exec("am start -a android.intent.action.VIEW -d \"" .. pkg.ps_link .. "\" " .. pkg_name)
                else
                    exec("am start " .. pkg_name)
                end
                
                -- Display Countdown without blocking UI totally?
                -- For simple Lua, we just wait.
                -- To update status while waiting, we would need coroutines, 
                -- but here we just update status text next loop.
                if config.delay_launch > 0 and (now - st.last_update) < config.delay_launch then
                   -- Still waiting
                else
                   st.status = "LAUNCHED"
                   st.last_update = now
                   sleep(config.delay_launch) -- Use configured delay
                end
                
            elseif st.status == "LAUNCHED" then
                local pid = exec("pidof " .. pkg_name)
                if pid and pid ~= "" then
                    if (now - st.last_update) > 5 then
                        st.status = "ONLINE"
                        st.online_start = now
                    end
                elseif (now - st.last_update) > 20 then
                    st.status = "RETRYING"
                end
                
            elseif st.status == "ONLINE" then
                local pid = exec("pidof " .. pkg_name)
                if not pid or pid == "" then
                    st.status = "RETRYING"
                else
                    if config.rejoin_interval > 0 and st.online_start then
                         if (now - st.online_start) > (config.rejoin_interval * 3600) then
                             st.status = "RESETTING"
                         end
                    end
                end
            elseif st.status == "RETRYING" then
                st.status = "RESETTING"
            end
            
            -- === RENDER ROW ===
            local s_color = C_WHITE
            if st.status == "ONLINE" then s_color = C_GREEN
            elseif st.status == "RESETTING" or st.status == "RETRYING" then s_color = C_RED
            elseif st.status == "LAUNCHED" then s_color = C_YELLOW
            else s_color = C_BLUE end
            
            local ram = (st.status == "ONLINE") and get_ram_usage(pkg_name) or "-"
            local uptime = "-"
            if st.status == "ONLINE" and st.online_start then
                 local diff = now - st.online_start
                 local m = math.floor(diff/60)
                 if m > 60 then uptime = math.floor(m/60).."h" else uptime = m.."m" end
            end
            
            -- Truncate name if too long
            local dname = pkg.name
            if #dname > 18 then dname = string.sub(dname, 1, 15) .. "..." end
            
            print(string.format("  %-3d %-20s %s%-12s%s %-8s %-10s", 
                i, dname, s_color, st.status, C_RESET, ram, uptime))
        end
        
        -- Webhook Check
        if webhook_config.interval > 0 and webhook_config.url ~= "" then
            if (now - last_webhook_time) > webhook_config.interval then
                last_webhook_time = now
                send_webhook() -- Warning: this pauses loop briefly
            end
        end
        
        -- Clear trailing lines (optional cleanup)
        print(C_WHITE .. "\n  [CTRL+C to Stop Monitoring]" .. C_RESET)
        
        sleep(2)
    end
    io.write(C_SHOW)
end

-- ==========================================
-- SETUP WIZARD (FULL)
-- ==========================================

function setup_wizard()
    print(C_CLEAR)
    print(C_HOME)
    print(C_GREEN .. "════ SETUP WIZARD v1.0.0 ════" .. C_RESET)
    print("Mari konfigurasi alat tempur Anda.\n")
    
    -- 1. Scan Packages
    print(C_YELLOW .. "[1/6] Scanning Packages..." .. C_RESET)
    local res = exec("pm list packages | grep 'roblox'")
    local found = {}
    for line in res:gmatch("[^\r\n]+") do
        local p = line:match("package:(.+)")
        if p then table.insert(found, p) end
    end
    
    if #found > 0 then
        print("Ditemukan " .. #found .. " package Roblox.")
        io.write("Tambahkan semua otomatis? (y/n) > ")
        local yn = io.read()
        if yn == "y" then
            packages = {}
            for idx, p in ipairs(found) do
                table.insert(packages, {name="Akun " .. idx, package=p, ps_link=""})
            end
            print("✓ " .. #packages .. " package ditambahkan.")
        end
    else
        print("⚠ Tidak ada package ditemukan. Anda bisa tambah manual nanti.")
    end
    
    -- 2. Delay
    print(C_YELLOW .. "\n[2/6] Delay Launcher" .. C_RESET)
    print("Waktu jeda antar buka aplikasi (detik).")
    io.write("Input (Default 10): ")
    local d = io.read()
    config.delay_launch = tonumber(d) or 10
    
    -- 3. Webhook
    print(C_YELLOW .. "\n[3/6] Discord Webhook" .. C_RESET)
    io.write("Masukkan URL Webhook (Enter untuk skip): ")
    local wh = io.read()
    webhook_config.url = wh
    if wh ~= "" then
        io.write("Interval notifikasi (detik, cth: 300): ")
        local intv = io.read()
        webhook_config.interval = tonumber(intv) or 300
        
        print("Testing Webhook...")
        local json = '{"username":"ZEEN TOOLS","content":"🎉 **Setup Wizard Completed!** Webhook Connected."}'
        local f = io.open("/data/data/com.termux/files/home/.ztest.json","w"); f:write(json); f:close()
        exec("curl -H \"Content-Type: application/json\" -d @/data/data/com.termux/files/home/.ztest.json \""..wh.."\"")
    end
    
    -- 4. Auto Clear Cache
    print(C_YELLOW .. "\n[4/6] Auto Clear Cache" .. C_RESET)
    io.write("Aktifkan hapus cache otomatis? (y/n): ")
    local acc = io.read()
    if acc == "y" then
        config.clear_cache_enabled = true
        io.write("Interval hapus cache (menit, Default 30): ")
        config.clear_cache_interval = tonumber(io.read()) or 30
    else
        config.clear_cache_enabled = false
    end
    
    -- 5. Auto Rejoin
    print(C_YELLOW .. "\n[5/6] Auto Rejoin" .. C_RESET)
    print("Reset aplikasi setelah berjalan sekian jam.")
    io.write("Interval Jam (0 = matikan fitur ini): ")
    config.rejoin_interval = tonumber(io.read()) or 0
    
    save_data()
    print(C_GREEN .. "\n✓ Setup Selesai! Data tersimpan." .. C_RESET)
    sleep(2)
end

-- ==========================================
-- EDIT CONFIG MENU
-- ==========================================

function menu_edit()
    while true do
        print(C_CLEAR .. C_HOME)
        print("══ EDIT CONFIG ══")
        print("1. Manage Packages (Add/Del)")
        print("2. Manage Link PS")
        print("3. Delay Launch ("..config.delay_launch.."s)")
        print("4. Webhook ("..(webhook_config.url ~= "" and "ON" or "OFF")..")")
        print("5. Clear Cache ("..(config.clear_cache_enabled and "ON" or "OFF")..")")
        print("6. Rejoin Interval ("..config.rejoin_interval.."h)")
        print("0. Back")
        io.write("Choice > ")
        local c = io.read()
        
        if c == "0" then break
        elseif c == "1" then
            print("\n1. Auto Detect & Add All")
            print("2. Manual Add")
            print("3. Delete All")
            local sc = io.read()
            if sc == "1" then
                local res = exec("pm list packages | grep 'roblox'")
                local cnt = 0
                for line in res:gmatch("[^\r\n]+") do
                   local p = line:match("package:(.+)")
                   local exists = false
                   for _,kp in ipairs(packages) do if kp.package == p then exists=true end end
                   if not exists then
                       table.insert(packages, {name="Roblox "..#packages+1, package=p, ps_link=""})
                       cnt = cnt+1
                   end
                end
                print("Added "..cnt.." new packages.")
                save_data()
                sleep(1)
            elseif sc == "3" then
                packages = {}
                save_data()
                print("All deleted.")
                sleep(1)
            end
        elseif c == "2" then
            print("\n1. Set All to one Link")
            print("2. Set per App")
            print("3. Delete All Links")
            local sc = io.read()
            if sc == "1" then
                io.write("Link PS: ")
                local l = io.read()
                for _,p in ipairs(packages) do p.ps_link = l end
                save_data()
            elseif sc == "3" then
                for _,p in ipairs(packages) do p.ps_link = "" end
                save_data()
            end
        elseif c == "3" then
            io.write("Delay (seconds): ")
            config.delay_launch = tonumber(io.read()) or 10
            save_data()
        elseif c == "4" then
            io.write("Webhook URL: ")
            webhook_config.url = io.read()
            io.write("Interval (seconds): ")
            webhook_config.interval = tonumber(io.read()) or 300
            save_data()
        elseif c == "5" then
            config.clear_cache_enabled = not config.clear_cache_enabled
            if config.clear_cache_enabled then
                io.write("Interval (minutes): ")
                config.clear_cache_interval = tonumber(io.read()) or 30
            end
            save_data()
        elseif c == "6" then
            io.write("Rejoin Hours (0=off): ")
            config.rejoin_interval = tonumber(io.read()) or 0
            save_data()
        end
    end
end

-- ==========================================
-- MAIN
-- ==========================================

function main()
    load_data()
    -- Set unbuffered input/output
    io.stdout:setvbuf("no")
    
    while true do
        print(C_CLEAR .. C_HOME)
        print(C_GREEN .. [[
███████╗███████╗███████╗███╗   ██╗
╚══███╔╝██╔════╝██╔════╝████╗  ██║
  ███╔╝ █████╗  █████╗  ██╔██╗ ██║
 ███╔╝  ██╔══╝  ██╔══╝  ██║╚██╗██║
███████╗███████╗███████╗██║ ╚████║
╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝
        ZEEN TOOLS v1.0.0
]] .. C_RESET)
        print("  1. Start Monitoring " .. C_GREEN .. "[RUN]" .. C_RESET)
        print("  2. First Run Setup (Wizard)")
        print("  3. Edit Config")
        print("  0. Exit")
        print()
        io.write("  Choice > ")
        local c = io.read()
        
        if c == "1" then start_monitoring()
        elseif c == "2" then setup_wizard()
        elseif c == "3" then menu_edit()
        elseif c == "0" then 
            print("Bye!"); break 
        end
    end
end

main()


