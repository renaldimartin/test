-- ZEEN TOOLS Code with Full Menu System

-- Function to display the menu
function displayMenu()
    print("=== ZEEN TOOLS ===")
    print("1. Feature 1")
    print("2. Feature 2")
    print("3. Feature 3")
    print("4. Exit")
end

-- Function for Feature 1
function feature1()
    print("Executing Feature 1...")
end

-- Function for Feature 2
function feature2()
    print("Executing Feature 2...")
end

-- Function for Feature 3
function feature3()
    print("Executing Feature 3...")
end

-- Main program loop
while true do
    displayMenu()
    local choice = io.read()
    if choice == "1" then
        feature1()
    elseif choice == "2" then
        feature2()
    elseif choice == "3" then
        feature3()
    elseif choice == "4" then
        print("Exiting...")
        break
    else
        print("Invalid choice, please try again.")
    end
end
