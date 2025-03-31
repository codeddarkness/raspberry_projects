#!/usr/bin/env bash

# PlayStation Controller Setup Script for Raspberry Pi
# Handles both PS3 and PS4 controllers with error checking and cleanup options

set -e  # Exit on error

# Display banner
echo "=================================================="
echo "  PlayStation Controller Setup for Raspberry Pi"
echo "=================================================="
echo ""

# Function to display error messages and exit
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Function to check if a package is installed
is_package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Function to install a package if not already installed
install_package() {
    if ! is_package_installed "$1"; then
        echo "Installing $1..."
        sudo apt install -y "$1" || error_exit "Failed to install $1"
    else
        echo "Package $1 is already installed"
    fi
}

# Function to handle cleanup
cleanup() {
    echo "Cleaning up PlayStation controller setup..."
    
    # Ask user for confirmation
    read -p "This will remove controller installations. Continue? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        # Stop sixad service if installed
        if systemctl is-active --quiet sixad 2>/dev/null; then
            sudo systemctl stop sixad
            echo "Stopped sixad service"
        fi
        
        # Remove sixad
        if dpkg -l | grep -q sixad; then
            sudo dpkg -r sixad
            echo "Removed sixad package"
        fi
        
        if [ -d "$HOME/sixad" ]; then
            sudo rm -rf "$HOME/sixad"
            echo "Removed sixad directory"
        fi
        
        # Remove sixpair
        if [ -d "$HOME/sixpair" ]; then
            rm -rf "$HOME/sixpair"
            echo "Removed sixpair directory"
        fi
        
        # Remove sixpair from /usr/local/bin if it exists
        if [ -f "/usr/local/bin/sixpair" ]; then
            sudo rm -f "/usr/local/bin/sixpair"
            echo "Removed sixpair from /usr/local/bin"
        fi
        
        # Remove ds4drv if installed
        if pip3 list | grep -q ds4drv; then
            sudo pip3 uninstall -y ds4drv
            echo "Removed ds4drv Python package"
        fi
        
        # Remove ds4drv udev rules
        if [ -f "/etc/udev/rules.d/50-ds4drv.rules" ]; then
            sudo rm -f /etc/udev/rules.d/50-ds4drv.rules
            sudo udevadm control --reload-rules
            sudo udevadm trigger
            echo "Removed ds4drv udev rules"
        fi
        
        # Remove ds4drv from rc.local
        if grep -q "ds4drv" /etc/rc.local; then
            sudo sed -i '/ds4drv/d' /etc/rc.local
            echo "Removed ds4drv from startup"
        fi
        
        echo "Cleanup completed successfully"
    else
        echo "Cleanup canceled"
    fi
    exit 0
}

# Function to setup PS3 controller
setup_ps3() {
    echo "Starting PS3 controller setup..."
    
    # Install required packages
    echo "Installing dependencies..."
    for pkg in libusb-dev git libbluetooth-dev checkinstall joystick pkg-config; do
        install_package "$pkg"
    done
    
    # Setup sixpair for PS3 controller pairing
    echo "Setting up sixpair..."
    if [ ! -f "/usr/local/bin/sixpair" ]; then
        mkdir -p "$HOME/sixpair"
        cd "$HOME/sixpair"
        if [ ! -f "sixpair.c" ]; then
            wget http://www.pabr.org/sixlinux/sixpair.c || error_exit "Failed to download sixpair.c"
        fi
        
        gcc -o sixpair sixpair.c -lusb || error_exit "Failed to compile sixpair"
        sudo cp sixpair /usr/local/bin/ || error_exit "Failed to copy sixpair to /usr/local/bin"
        echo "sixpair installed to /usr/local/bin"
    else
        echo "sixpair is already installed"
    fi
    
    # Ask if user wants to use sixad or bluetoothctl
    echo ""
    echo "PS3 controller can be connected using either:"
    echo "1) SIXAD (recommended for gaming/retropie)"
    echo "2) Bluetoothctl (more compatible with other Bluetooth devices)"
    read -p "Which method do you want to use? (1/2): " ps3_method
    
    if [ "$ps3_method" = "1" ]; then
        setup_sixad
    else
        setup_ps3_bluetoothctl
    fi
}

# Function to setup PS3 with SIXAD
setup_sixad() {
    echo "Setting up SIXAD for PS3 controller..."
    
    # Set up sixad if not already installed
    if ! dpkg -l | grep -q sixad; then
        cd "$HOME"
        if [ ! -d "$HOME/sixad" ]; then
            echo "Cloning SIXAD repository..."
            git clone https://github.com/RetroPie/sixad.git || error_exit "Failed to clone sixad repository"
        fi
        
        cd "$HOME/sixad"
        echo "Compiling SIXAD..."
        make || error_exit "Failed to build sixad"
        
        echo "Installing SIXAD..."
        sudo mkdir -p /var/lib/sixad/profiles
        sudo checkinstall -y || error_exit "Failed to install sixad"
    else
        echo "SIXAD is already installed"
    fi
    
    echo ""
    echo "1) Connect your PS3 controller via USB"
    echo "2) Run sixpair to configure controller for Bluetooth"
    echo "3) Disconnect the controller when prompted"
    echo "4) Press the PS button when prompted to connect wirelessly"
    read -p "Press ENTER when ready to continue..." dummy
    
    # Run sixpair with controller connected
    echo "Running sixpair - make sure your controller is connected via USB..."
    sudo /usr/local/bin/sixpair || error_exit "sixpair failed. Is the controller connected via USB?"
    
    echo "Sixpair completed. You can now disconnect your controller."
    read -p "Press ENTER when you've disconnected the controller..." dummy
    
    # Start sixad service
    echo "Starting SIXAD service..."
    if ! systemctl is-active --quiet sixad 2>/dev/null; then
        sudo sixad --start || error_exit "Failed to start sixad"
        sudo update-rc.d sixad defaults || error_exit "Failed to set sixad to start on boot"
    else
        echo "SIXAD service is already running"
    fi
    
    echo ""
    echo "Press the PS button on your controller now to connect wirelessly."
    echo "The LED on the controller should briefly flash and then one LED should remain lit."
}

# Function to setup PS3 with bluetoothctl
setup_ps3_bluetoothctl() {
    echo "Setting up PS3 controller with bluetoothctl..."
    
    echo ""
    echo "1) Connect your PS3 controller via USB"
    echo "2) Run sixpair to configure controller for Bluetooth"
    echo "3) Disconnect the controller when prompted"
    echo "4) We'll then pair the controller using Bluetooth"
    read -p "Press ENTER when ready to continue..." dummy
    
    # Run sixpair with controller connected
    echo "Running sixpair - make sure your controller is connected via USB..."
    sudo /usr/local/bin/sixpair || error_exit "sixpair failed. Is the controller connected via USB?"
    
    echo "Sixpair completed. You can now disconnect your controller."
    read -p "Press ENTER when you've disconnected the controller..." dummy
    
    echo "Starting Bluetooth pairing process..."
    echo "When prompted to press the PS button, press it on your controller."
    echo "You will need to note the MAC address that appears (format like XX:XX:XX:XX:XX:XX)"
    echo ""
    echo "Follow these steps in the bluetoothctl prompt:"
    echo "1. When asked, enter: agent on"
    echo "2. When asked, enter: default-agent"
    echo "3. When asked, enter: scan on"
    echo "4. Press the PS button on your controller"
    echo "5. Note the MAC address that appears"
    echo "6. When asked, enter: connect YOUR_MAC_ADDRESS (replace with the actual address)"
    echo "7. When asked, enter: trust YOUR_MAC_ADDRESS (replace with the actual address)"
    echo "8. When asked, enter: quit"
    echo ""
    read -p "Press ENTER to begin the Bluetooth pairing process..." dummy
    
    sudo bluetoothctl
    
    echo ""
    echo "Bluetooth pairing process completed."
    echo "Your PS3 controller should now be paired with your Raspberry Pi."
    echo "To test if it's working, you can run: sudo jstest /dev/input/js0"
}

# Function to setup PS4 controller
setup_ps4() {
    echo "Starting PS4 controller setup..."
    
    # Install required packages
    echo "Installing dependencies..."
    for pkg in joystick; do
        install_package "$pkg"
    done
    
    # Ask for connection method
    echo ""
    echo "PS4 controller can be connected using:"
    echo "1) Bluetooth pairing (simplest method)"
    echo "2) USB cable (most reliable method)"
    echo "3) DS4DRV userspace driver (if other methods fail)"
    read -p "Which method do you want to use? (1/2/3): " ps4_method
    
    if [ "$ps4_method" = "1" ]; then
        setup_ps4_bluetooth
    elif [ "$ps4_method" = "3" ]; then
        setup_ps4_ds4drv
    else
        echo ""
        echo "To use the PS4 controller via USB:"
        echo "1) Simply connect your PS4 controller using a micro USB cable"
        echo "2) Test if it's working with: sudo jstest /dev/input/js0"
        echo ""
    fi
}

# Function to setup PS4 with Bluetooth
setup_ps4_bluetooth() {
    echo "Setting up PS4 controller with Bluetooth..."
    
    # Check if sixad is installed and offer to remove it
    if dpkg -l | grep -q sixad; then
        echo "SIXAD is installed, which may conflict with PS4 controllers."
        read -p "Do you want to remove SIXAD? (y/n): " remove_sixad
        if [[ "$remove_sixad" =~ ^[Yy]$ ]]; then
            sudo dpkg -r sixad
            echo "SIXAD has been removed"
        fi
    fi
    
    echo ""
    echo "Starting Bluetooth pairing process..."
    echo "When prompted, press and hold both the SHARE and PS buttons on your controller"
    echo "until the light starts flashing rapidly."
    echo ""
    echo "Follow these steps in the bluetoothctl prompt:"
    echo "1. When asked, enter: agent on"
    echo "2. When asked, enter: default-agent"
    echo "3. When asked, enter: scan on"
    echo "4. Press and hold SHARE+PS buttons on your controller until it flashes"
    echo "5. Note the MAC address that appears with 'Wireless Controller'"
    echo "6. When asked, enter: connect YOUR_MAC_ADDRESS (replace with the actual address)"
    echo "7. When asked, enter: trust YOUR_MAC_ADDRESS (replace with the actual address)"
    echo "8. When asked, enter: quit"
    echo ""
    read -p "Press ENTER to begin the Bluetooth pairing process..." dummy
    
    sudo bluetoothctl
    
    echo ""
    echo "Bluetooth pairing process completed."
    echo "Your PS4 controller should now be paired with your Raspberry Pi."
    echo "To test if it's working, you can run: sudo jstest /dev/input/js0"
}

# Function to setup PS4 with DS4DRV
setup_ps4_ds4drv() {
    echo "Setting up PS4 controller with DS4DRV userspace driver..."
    
    # Install Python requirements
    install_package "python3-dev"
    install_package "python3-pip"
    
    # Install DS4DRV
    echo "Installing DS4DRV..."
    sudo pip3 install ds4drv
    
    # Setup udev rules
    echo "Setting up udev rules..."
    sudo wget https://raw.githubusercontent.com/chrippa/ds4drv/master/udev/50-ds4drv.rules -O /etc/udev/rules.d/50-ds4drv.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    
    # Add to startup
    echo "Adding DS4DRV to startup..."
    if ! grep -q "ds4drv" /etc/rc.local; then
        sudo sed -i '/exit 0/i \/usr\/local\/bin\/ds4drv --hidraw --led 000008 \&' /etc/rc.local
    fi
    
    echo ""
    echo "Now you need to pair your PS4 controller with Bluetooth first."
    read -p "Have you already paired your controller with Bluetooth? (y/n): " is_paired
    
    if [[ ! "$is_paired" =~ ^[Yy]$ ]]; then
        setup_ps4_bluetooth
    fi
    
    echo ""
    echo "Testing DS4DRV with your controller..."
    echo "Press CTRL+C to stop the test when you're satisfied it's working."
    read -p "Press ENTER to begin testing..." dummy
    
    sudo ds4drv --hidraw --led 000008
    
    echo ""
    echo "DS4DRV setup completed. Your controller should be usable now."
    echo "To test if it's working, you can run: sudo jstest /dev/input/js0"
    echo "The driver will start automatically on boot."
}

# Function to update the system
update_system() {
    echo "Updating system packages..."
    sudo apt update || error_exit "Failed to update package lists"
    sudo apt upgrade -y || error_exit "Failed to upgrade packages"
    echo "System update completed"
}

# Main menu
show_menu() {
    echo ""
    echo "PLAYSTATION CONTROLLER SETUP MENU"
    echo "================================="
    echo "1) Update system"
    echo "2) Setup PS3 controller"
    echo "3) Setup PS4 controller"
    echo "4) Test controller"
    echo "5) Cleanup installations"
    echo "6) Exit"
    echo ""
    read -p "Select an option: " menu_choice
    
    case $menu_choice in
        1)
            update_system
            show_menu
            ;;
        2)
            setup_ps3
            show_menu
            ;;
        3)
            setup_ps4
            show_menu
            ;;
        4)
            echo "Testing controller... Press CTRL+C to exit the test."
            sudo jstest /dev/input/js0 || echo "No controller detected at /dev/input/js0"
            show_menu
            ;;
        5)
            cleanup
            ;;
        6)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option, please try again."
            show_menu
            ;;
    esac
}

# Check for command line parameters
if [ "$1" = "--cleanup" ]; then
    cleanup
fi

# Start the script
echo "This script will help you set up PlayStation controllers on your Raspberry Pi."
show_menu
