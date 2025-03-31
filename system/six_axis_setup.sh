#!/usr/bin/env bash

# Script to set up PlayStation 3 controllers
# With improved error handling, duplicate prevention, and cleanup option

set -e  # Exit on error

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
    echo "Cleaning up..."
    
    # Ask user for confirmation
    read -p "This will remove sixpair and sixad installations. Continue? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        # Stop sixad service
        if systemctl is-active --quiet sixad; then
            sudo systemctl stop sixad
        fi
        
        # Remove sixad
        if [ -d "$HOME/sixad" ]; then
            cd "$HOME"
            sudo apt remove -y sixad || echo "Warning: Unable to remove sixad package"
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
        
        echo "Cleanup completed"
    else
        echo "Cleanup canceled"
    fi
    exit 0
}

# Process command line arguments
if [ "$1" = "--cleanup" ]; then
    cleanup
fi

# Install required packages
echo "Installing dependencies..."
for pkg in libusb-dev git libbluetooth-dev checkinstall; do
    install_package "$pkg"
done
# Only install these if not already installed (you mentioned they are)
if ! is_package_installed "joystick"; then
    install_package "joystick"
fi
if ! is_package_installed "pkg-config"; then
    install_package "pkg-config"
fi

# Check if sixpair already exists in /usr/local/bin
SIXPAIR_EXISTS=false
if [ -f "/usr/local/bin/sixpair" ]; then
    echo "sixpair already installed in /usr/local/bin"
    SIXPAIR_EXISTS=true
fi

# Set up sixpair if needed
if [ "$SIXPAIR_EXISTS" = false ]; then
    echo "Setting up sixpair..."
    mkdir -p "$HOME/sixpair"
    cd "$HOME/sixpair"
    if [ ! -f "sixpair.c" ]; then
        wget http://www.pabr.org/sixlinux/sixpair.c || error_exit "Failed to download sixpair.c"
    fi
    
    gcc -o sixpair sixpair.c -lusb || error_exit "Failed to compile sixpair"
    sudo cp sixpair /usr/local/bin/ || error_exit "Failed to copy sixpair to /usr/local/bin"
    echo "Installed sixpair to /usr/local/bin"
else
    # If sixpair.c exists but compiled binary doesn't, compile it
    if [ -d "$HOME/sixpair" ] && [ -f "$HOME/sixpair/sixpair.c" ] && [ ! -f "$HOME/sixpair/sixpair" ]; then
        cd "$HOME/sixpair"
        gcc -o sixpair sixpair.c -lusb || error_exit "Failed to compile sixpair"
        sudo cp sixpair /usr/local/bin/ || error_exit "Failed to copy sixpair to /usr/local/bin"
        echo "Updated sixpair in /usr/local/bin"
    fi
fi

# Run sixpair using the known location
echo "Running sixpair (connect controller via USB now)..."
sudo /usr/local/bin/sixpair || error_exit "sixpair failed. Is the controller connected via USB?"

# Set up sixad
if [ ! -d "$HOME/sixad" ]; then
    echo "Setting up sixad..."
    cd "$HOME"
    git clone https://github.com/RetroPie/sixad.git || error_exit "Failed to clone sixad repository"
    cd "$HOME/sixad"
    make || error_exit "Failed to build sixad"
    sudo mkdir -p /var/lib/sixad/profiles
    sudo checkinstall -y || error_exit "Failed to install sixad"
else
    echo "sixad directory already exists"
fi

# Start sixad service
echo "Starting sixad service..."
if ! systemctl is-active --quiet sixad 2>/dev/null; then
    sudo sixad --start || error_exit "Failed to start sixad"
    sudo update-rc.d sixad defaults || error_exit "Failed to set sixad to start on boot"
else
    echo "sixad service is already running"
fi

echo "PlayStation 3 controller setup completed successfully!"
echo "To clean up this installation in the future, run this script with --cleanup"
