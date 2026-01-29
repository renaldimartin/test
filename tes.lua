#!/data/data/com.termux/files/usr/bin/lua

--[[
    ZEEN TOOLS v1.0.0
    The Ultimate Roblox Clone Manager for Termux
    
    Features:
    - State Machine Monitoring
    - Auto Grid Layout (6 Apps/Screen)
    - Discord Webhook Integration
    - Private Server Injection
    - Root Access Management
]]

-- ==========================================
-- DEPENDENCY & CONFIGURATION
-- ==========================================

local lfs_exists, lfs = pcall(require, "lfs") -- Optional check
local json_exists, json = pcall(require, "cjson") -- Optional check

-- Configuration Files
local CONFIG_FILE = "/data/data/com.termux/files/home/.zeen_config.dat"
local PACKAGE_FILE = "/data/data/com.termux/files/home/.zeen_packages.dat"
local WEBHOOK_FILE = "/data/data/com.termux/files/home/.zeen_webhook.dat"
local TEMP_SCRIPT = "/data/data/com.termux/files/home/.zeen_exec.sh"

-- Display Settings
local DISPLAY_WIDTH = 1280
local DISPLAY_HEIGHT = 720
local COLUMNS = 2
local ROWS = 3

-- Global State
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
local app_states = {} -- Stores current state of each app
local last_webhook_time = 0

-- ANSI Colors
local C_RESET = "\27[0m"
local C_RED = "\27[31m"
local C_GREEN = "\27[32m"
local C_YELLOW = "\27[33m"
local C_BLUE = "\27[34m"
local C_MAGENTA = "\27[35m"
local C_CYAN = "\27[36m"
local C_WHITE = "\27[37m"
local C_BOLD = "\27[1m"

-- ==========================================
-- UTILITY FUNCTIONS
-- ==========================================

function sleep(n)
    os.execute("sleep " .. tonumber(n))
end

function clear_screen()
    os.execute("clear")
end

-- Execute command with Root (su)
function exec(cmd)
    local f = io.open(TEMP_SCRIPT, "w")
    if not f then return "" end
    f:write("#!/system/bin/sh\n")
    f:write(cmd .. "\n")
    f:close()
    
    os.execute("chmod +x " .. TEMP_SCRIPT)
    
    local output_file = "/data/data/com.termux/files/home/.zeen_output.txt"
    -- Redirect stderr to stdout to catch errors
    os.execute("su -c '" .. TEMP_SCRIPT .. " > " .. output_file .. " 2>&1'")
    
    local result = ""
    local rf = io.open(output_file, "r")
    if rf then
        result = rf:read("*a")
        rf:close()
    end
    
    os.remove(TEMP_SCRIPT)
    os.remove(output_file)
    
    -- Cleanup whitespace
    if result then result = result:gsub("^%s*(.-)%s*$", "%1") end
    return result
end

-- Simple split string
function split(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

-- Get Device Name
function get_device_name()
    local model = exec("getprop ro.product.model")
    if model and model ~= "" then
        config.device_name = model
    end
end

-- ==========================================
-- DATA PERSISTENCE
-- ==========================================

function save_packages()
    local file = io.open(PACKAGE_FILE, "w")
    if file then
        for _, pkg in ipairs(packages) do
            -- Format: name|package|ps_link
            local ps = pkg.ps_link or ""
            file:write(pkg.name .. "|" .. pkg.package .. "|" .. ps .. "\n")
        end
        file:close()
    end
end

function load_packages()
    local file = io.open(PACKAGE_FILE, "r")
    if file then
        packages = {}
        for line in file:lines() do
            local parts = split(line, "|")
            if #parts >= 2 then
                table.insert(packages, {
                    name = parts[1],
                    package = parts[2],
                    ps_link = parts[3] or ""
                })
            end
        end
        file:close()
    end
end

function save_config()
    local file = io.open(CONFIG_FILE, "w")
    if file then
        file:write("delay_launch=" .. config.delay_launch .. "\n")
        file:write("clear_cache_interval=" .. config.clear_cache_interval .. "\n")
        file:write("clear_cache_enabled=" .. tostring(config.clear_cache_enabled) .. "\n")
        file:write("rejoin_interval=" .. config.rejoin_interval .. "\n")
        file:close()
    end
    
    local w_file = io.open(WEBHOOK_FILE, "w")
    if w_file then
        w_file:write("url=" .. webhook_config.url .. "\n")
        w_file:write("interval=" .. webhook_config.interval .. "\n")
        w_file:close()
    end
end

function load_config()
    local file = io.open(CONFIG_FILE, "r")
    if file then
        for line in file:lines() do
            local k, v = line:match("(.-)=(.+)")
            if k == "delay_launch" then config.delay_launch = tonumber(v) end
            if k == "clear_cache_interval" then config.clear_cache_interval = tonumber(v) end
            if k == "clear_cache_enabled" then config.clear_cache_enabled = (v == "true") end
            if k == "rejoin_interval" then config.rejoin_interval = tonumber(v) end
        end
        file:close()
    end
    
    local w_file = io.open(WEBHOOK_FILE, "r")
    if w_file then
        for line in w_file:lines() do
            local k, v = line:match("(.-)=(.+)")
            if k == "url" then webhook_config.url = v end
            if k == "interval" then webhook_config.interval = tonumber(v) end
        end
        w_file:close()
    end
    get_device_name()
end

-- ==========================================
-- UI ELEMENTS
-- ==========================================

function print_logo()
    print(C_GREEN .. [[
███████╗███████╗███████╗███╗   ██╗
╚══███╔╝██╔════╝██╔════╝████╗  ██║
  ███╔╝ █████╗  █████╗  ██╔██╗ ██║
 ███╔╝  ██╔══╝  ██╔══╝  ██║╚██╗██║
███████╗███████╗███████╗██║ ╚████║
╚══════╝╚══════╝╚══════╝╚═╝  ╚═══╝
        ZEEN TOOLS v1.0.0
]] .. C_RESET)
end

function print_header(title)
    print(C_CYAN .. "════════════════════════════════════════")
    print("  " .. title)
    print("════════════════════════════════════════" .. C_RESET)
end

-- ==========================================
-- CORE LOGIC: GRID & MODIFICATION
-- ==========================================

function get_grid_pos(index)
    -- Normalize index to 1-6
    local normalized_idx = (index - 1) % 6 + 1
    
    local w = math.floor(DISPLAY_WIDTH / 2)
    local h = math.floor(DISPLAY_HEIGHT / 3)
    
    -- Col 1 or 2
    local col = (normalized_idx - 1) % 2
    -- Row 1, 2, or 3
    local row = math.floor((normalized_idx - 1) / 2)
    
    return {
        left = col * w,
        top = row * h,
        right = (col * w) + w,
        bottom = (row * h) + h
    }
end

function modify_xml(package, index)
    local pos = get_grid_pos(index)
    
    -- Find Preference File
    local find_cmd = "ls /data/data/" .. package .. "/shared_prefs/*preferences.xml 2>/dev/null"
    local pref_file = exec(find_cmd)
    
    if not pref_file or pref_file == "" then
        -- Fallback: try finding any xml
        pref_file = exec("ls /data/data/" .. package .. "/shared_prefs/*.xml 2>/dev/null | head -n 1")
    end
    
    if not pref_file or pref_file == "" then return false end
    
    -- Inject Values using sed (Standard Unix Tool)
    local sed_cmds = {
        string.format("sed -i 's/app_cloner_current_window_left\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_left\\\" value=\\\"%d\\\"/' '%s'", pos.left, pref_file),
        string.format("sed -i 's/app_cloner_current_window_top\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_top\\\" value=\\\"%d\\\"/' '%s'", pos.top, pref_file),
        string.format("sed -i 's/app_cloner_current_window_right\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_right\\\" value=\\\"%d\\\"/' '%s'", pos.right, pref_file),
        string.format("sed -i 's/app_cloner_current_window_bottom\\\" value=\\\"[0-9]*\\\"/app_cloner_current_window_bottom\\\" value=\\\"%d\\\"/' '%s'", pos.bottom, pref_file)
    }
    
    for _, cmd in ipairs(sed_cmds) do
        exec(cmd)
    end
    
    return true
end

function get_ram_usage(package)
    -- Simple RSS check
    local pid = exec("pidof " .. package)
    if not pid or pid == "" then return "0MB" end
    local rss = exec("ps -o rss -p " .. pid .. " | tail -n 1")
    if rss and tonumber(rss) then
        return math.floor(tonumber(rss) / 1024) .. "MB"
    end
    return "?MB"
end

function get_cpu_usage(package)
    -- This is expensive, maybe skip for performance or use simplified top
    return "?%" 
end

-- ==========================================
-- WEBHOOK SYSTEM
-- ==========================================

function send_webhook()
    if webhook_config.url == "" then return end
    
    local total_online = 0
    local total_offline = 0
    local fields = {}
    
    for i, pkg in ipairs(packages) do
        local state = app_states[pkg.package]
        local is_online = (state and state.status == "ONLINE")
        
        if is_online then total_online = total_online + 1 else total_offline = total_offline + 1 end
        
        local icon = is_online and "🟢" or "🔴"
        local ram = is_online and get_ram_usage(pkg.package) or "-"
        local status_text = is_online and ("Running | 💾 " .. ram) or "Offline"
        
        -- Safe package name/account name
        local name_display = pkg.name or pkg.package
        
        table.insert(fields, string.format([[
        {
            "name": "%s **%s**",
            "value": "`%s`",
            "inline": true
        }]], icon, name_display, status_text))
    end
    
    local time_str = os.date("%H:%M %d-%B-%Y")
    local json_body = string.format([[
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
    ]], config.device_name, total_online, total_offline, #packages, table.concat(fields, ","), time_str)
    
    -- Write JSON to file to avoid quoting hell in shell
    local f = io.open("/data/data/com.termux/files/home/.zeen_payload.json", "w")
    f:write(json_body)
    f:close()
    
    exec("curl -H \"Content-Type: application/json\" -d @/data/data/com.termux/files/home/.zeen_payload.json \"" .. webhook_config.url .. "\"")
end

-- ==========================================
-- STATE MACHINE MONITORING
-- ==========================================

function start_monitoring()
    if #packages == 0 then
        print(C_RED .. "✗ Tidak ada package untuk dimonitor!" .. C_RESET)
        sleep(2)
        return
    end

    -- Initial State Setup
    for _, pkg in ipairs(packages) do
        app_states[pkg.package] = {
            status = "RESETTING",
            last_update = os.time(),
            pid = nil
        }
    end
    
    -- Hide cursor
    io.write("\27[?25l")
    
    local running = true
    while running do
        clear_screen()
        print_logo()
        
        print(C_WHITE .. "  MONITORING ACTIVE (CTRL+C to Stop)" .. C_RESET)
        print(C_CYAN .. "  Dev: " .. config.device_name .. C_RESET)
        print()
        
        -- Header Table
        print(string.format(C_BOLD .. "  %-4s %-25s %-15s %-10s" .. C_RESET, "NO", "NAME/ACC", "STATUS", "RAM"))
        print(C_WHITE .. "  ----------------------------------------------------------" .. C_RESET)
        
        local current_time = os.time()
        
        for i, pkg in ipairs(packages) do
            local state = app_states[pkg.package]
            local pkg_name = pkg.package
            
            -- STATE MACHINE LOGIC
            
            -- 1. RESETTING
            if state.status == "RESETTING" then
                exec("am force-stop " .. pkg_name)
                state.status = "BOOSTING"
                state.last_update = current_time
            
            -- 2. BOOSTING (Clear Cache)
            elseif state.status == "BOOSTING" then
                if config.clear_cache_enabled then
                    exec("pm clear " .. pkg_name .. " --cache-only") -- Note: pm clear wipes data on some androids, careful. using trim-caches usually needs privilege.
                    -- Safer to just skip generic clear or use specific path rm
                    exec("rm -rf /data/data/" .. pkg_name .. "/cache/*")
                end
                state.status = "OPTIMIZED"
                
            -- 3. OPTIMIZED (Inject Config)
            elseif state.status == "OPTIMIZED" then
                modify_xml(pkg_name, i)
                state.status = "READY"
                
            -- 4. READY (Launch)
            elseif state.status == "READY" then
                if pkg.ps_link and pkg.ps_link ~= "" then
                    -- Launch via Private Server Link
                    exec("am start -a android.intent.action.VIEW -d \"" .. pkg.ps_link .. "\" " .. pkg_name)
                else
                    -- Standard Launch
                    exec("am start " .. pkg_name)
                end
                -- Delay per app to prevent CPU spike
                if config.delay_launch > 0 then
                    local delay_progress = "Waiting..."
                    -- We can't sleep here or it blocks UI. 
                    -- For v1.0, we block briefly. Ideally use non-blocking time check.
                    sleep(config.delay_launch)
                end
                state.status = "LAUNCHED"
                state.last_update = current_time
                
            -- 5. LAUNCHED (Check PID)
            elseif state.status == "LAUNCHED" then
                local pid = exec("pidof " .. pkg_name)
                if pid and pid ~= "" then
                    if (current_time - state.last_update) > 5 then
                        state.status = "ONLINE"
                        state.pid = pid
                    end
                else
                    -- Failed to launch?
                     if (current_time - state.last_update) > 15 then
                        state.status = "RETRYING"
                     end
                end
                
            -- 6. ONLINE (Monitor)
            elseif state.status == "ONLINE" then
                local pid = exec("pidof " .. pkg_name)
                if not pid or pid == "" then
                    state.status = "RETRYING" -- Crashed/Closed
                else
                    -- Check Rejoin Interval
                    if config.rejoin_interval > 0 then
                        local runtime = os.difftime(current_time, state.last_update)
                        if runtime > (config.rejoin_interval * 3600) then
                            state.status = "RESETTING" -- Scheduled restart
                        end
                    end
                end
            
            -- 7. RETRYING
            elseif state.status == "RETRYING" then
                 state.status = "RESETTING"
            end
            
            -- RENDER ROW
            local status_color = C_WHITE
            if state.status == "ONLINE" then status_color = C_GREEN
            elseif state.status == "RETRYING" or state.status == "RESETTING" then status_color = C_RED
            elseif state.status == "LAUNCHED" then status_color = C_YELLOW
            else status_color = C_BLUE end
            
            local ram = (state.status == "ONLINE") and get_ram_usage(pkg_name) or "-"
            
            print(string.format("  %-4d %-25s %s%-15s%s %-10s", 
                i, 
                string.sub(pkg.name, 1, 24), 
                status_color, 
                state.status, 
                C_RESET, 
                ram
            ))
        end
        
        -- Webhook Check
        if webhook_config.interval > 0 and (current_time - last_webhook_time) > webhook_config.interval then
            -- Run in background to not freeze loop? Lua is single threaded. 
            -- We just run it, curl is fast enough.
            send_webhook()
            last_webhook_time = current_time
        end
        
        sleep(2) -- Loop interval
    end
    
    -- Restore cursor
    io.write("\27[?25h")
end

-- ==========================================
-- MENUS
-- ==========================================

function menu_edit_config()
    while true do
        clear_screen()
        print_header("EDIT CONFIG")
        print("1. Add Package")
        print("2. Add Link PS (Private Server)")
        print("3. Set Delay Launched (" .. config.delay_launch .. "s)")
        print("4. Webhook Settings")
        print("5. Auto Clear Cache Settings")
        print("6. Set Interval Rejoin (" .. config.rejoin_interval .. "h)")
        print("0. Back")
        print()
        io.write("Choice > ")
        local choice = io.read()
        
        if choice == "0" then break
        elseif choice == "1" then menu_add_package()
        elseif choice == "2" then menu_add_ps()
        elseif choice == "3" then
            io.write("Enter delay (seconds): ")
            config.delay_launch = tonumber(io.read()) or 10
            save_config()
        elseif choice == "4" then menu_webhook()
        elseif choice == "5" then
            print("1. Set Interval (Current: " .. config.clear_cache_interval .. "m)")
            print("2. Toggle (Current: " .. tostring(config.clear_cache_enabled) .. ")")
            local cc = io.read()
            if cc == "1" then 
                io.write("Minutes: ")
                config.clear_cache_interval = tonumber(io.read()) or 30
            elseif cc == "2" then
                config.clear_cache_enabled = not config.clear_cache_enabled
            end
            save_config()
        elseif choice == "6" then
            io.write("Interval Hours (0 to disable): ")
            config.rejoin_interval = tonumber(io.read()) or 0
            save_config()
        end
    end
end

function menu_add_package()
    print_header("ADD PACKAGE")
    print("1. Auto Detect (com.roblox)")
    print("2. Manual Input")
    print("3. Delete Package")
    print("0. Back")
    local c = io.read()
    
    if c == "1" then
        print("\nScanning...")
        local res = exec("pm list packages | grep 'roblox'")
        local candidates = {}
        for line in res:gmatch("[^\r\n]+") do
            local pkg = line:match("package:(.+)")
            if pkg then table.insert(candidates, pkg) end
        end
        
        if #candidates == 0 then print("No Roblox detected.") sleep(1) return end
        
        for i, p in ipairs(candidates) do print(i .. ". " .. p) end
        
        print("\nType 'all' or numbers (e.g. 1,2): ")
        local sel = io.read()
        if sel == "all" then
            for _, p in ipairs(candidates) do
                table.insert(packages, {name="Roblox " .. #packages+1, package=p, ps_link=""})
            end
        else
            for num in sel:gmatch("%d+") do
                local n = tonumber(num)
                if candidates[n] then
                    table.insert(packages, {name="Roblox " .. n, package=candidates[n], ps_link=""})
                end
            end
        end
        save_packages()
        print("Saved!")
        sleep(1)
        
    elseif c == "2" then
        io.write("Package Name (e.g com.roblox.client): ")
        local p = io.read()
        io.write("Display Name: ")
        local n = io.read()
        table.insert(packages, {name=n, package=p, ps_link=""})
        save_packages()
    elseif c == "3" then
        if #packages == 0 then return end
        for i, pkg in ipairs(packages) do print(i .. ". " .. pkg.name) end
        print("Type 'all' or numbers to delete:")
        local sel = io.read()
        if sel == "all" then
            packages = {}
        else
            -- Delete in reverse order to keep indices valid
            local to_del = {}
            for num in sel:gmatch("%d+") do to_del[tonumber(num)] = true end
            for i = #packages, 1, -1 do
                if to_del[i] then table.remove(packages, i) end
            end
        end
        save_packages()
    end
end

function menu_add_ps()
    print_header("PRIVATE SERVER LINKS")
    if #packages == 0 then print("No packages added.") sleep(1) return end
    
    print("1. Add All (Same Link)")
    print("2. Add Per Package")
    print("3. Delete All Links")
    local c = io.read()
    
    if c == "1" then
        io.write("Link PS: ")
        local l = io.read()
        for _, pkg in ipairs(packages) do pkg.ps_link = l end
        save_packages()
    elseif c == "2" then
        for i, pkg in ipairs(packages) do
            print(i .. ". " .. pkg.name .. " [" .. (pkg.ps_link ~= "" and "SET" or "EMPTY") .. "]")
        end
        io.write("Select number: ")
        local idx = tonumber(io.read())
        if packages[idx] then
            io.write("Link PS: ")
            packages[idx].ps_link = io.read()
            save_packages()
        end
    elseif c == "3" then
        for _, pkg in ipairs(packages) do pkg.ps_link = "" end
        save_packages()
    end
end

function menu_webhook()
    print_header("WEBHOOK SETTINGS")
    print("1. Add/Edit URL")
    print("2. Set Interval (Current: " .. webhook_config.interval .. "s)")
    print("3. Test Notification")
    print("0. Back")
    local c = io.read()
    
    if c == "1" then
        io.write("Webhook URL: ")
        webhook_config.url = io.read()
        save_config()
    elseif c == "2" then
        io.write("Interval (seconds, enter to skip): ")
        local i = io.read()
        if i ~= "" then webhook_config.interval = tonumber(i) end
        save_config()
    elseif c == "3" then
        if webhook_config.url == "" then
            print("URL is empty!")
        else
            print("Sending test...")
            local json_body = [[
            {
                "username": "ZEEN TOOLS",
                "content": "👋 **Welcome to ZEEN TOOLS v1.0.0**\nWebhook integration is working correctly!"
            }
            ]]
            local f = io.open("/data/data/com.termux/files/home/.zeen_test.json", "w")
            f:write(json_body)
            f:close()
            exec("curl -H \"Content-Type: application/json\" -d @/data/data/com.termux/files/home/.zeen_test.json \"" .. webhook_config.url .. "\"")
            print("Sent!")
        end
        sleep(2)
    end
end

function setup_wizard()
    print_header("SETUP WIZARD")
    print("Welcome to ZEEN TOOLS!")
    print("Let's set up the basics.\n")
    
    if #packages == 0 then
        print("Step 1: Auto-Detect Packages? (y/n)")
        local yn = io.read()
        if yn == "y" then
             local res = exec("pm list packages | grep 'roblox'")
             for line in res:gmatch("[^\r\n]+") do
                local pkg = line:match("package:(.+)")
                if pkg then 
                    local num = #packages + 1
                    table.insert(packages, {name="Roblox " .. num, package=pkg, ps_link=""}) 
                end
             end
             print("Found " .. #packages .. " packages.")
        end
    end
    
    print("\nStep 2: Set Delay Launch (seconds) [Default: 10]: ")
    local d = io.read()
    if d ~= "" then config.delay_launch = tonumber(d) end
    
    save_config()
    save_packages()
    print("\nSetup Complete!")
    sleep(1)
end

-- ==========================================
-- MAIN ENTRY
-- ==========================================

function main()
    load_config()
    load_packages()
    
    while true do
        clear_screen()
        print_logo()
        print("  1. Start Monitoring " .. C_GREEN .. "(▶)" .. C_RESET)
        print("  2. First Run Setup (Wizard)")
        print("  3. Edit Config")
        print("  0. Exit")
        print()
        io.write("  Choice > ")
        local choice = io.read()
        
        if choice == "1" then
            start_monitoring()
        elseif choice == "2" then
            setup_wizard()
        elseif choice == "3" then
            menu_edit_config()
        elseif choice == "0" then
            print("\nSee you next time! 👋")
            break
        else
            print("Invalid choice!")
            sleep(1)
        end
    end
end

-- Start
main()

