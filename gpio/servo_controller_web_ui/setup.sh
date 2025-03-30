#!/usr/bin/env bash

# Servo_controller_web_ui Setup Script for Raspberry Pi
# Version 

set -e  # Exit on error

# Display banner
echo "=================================================="
echo "  Servo_controller_web_ui Setup for Raspberry Pi"
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

# Update system packages
echo "Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Install required packages
echo "Installing dependencies..."
# Add your required packages here
# install_package "package-name"

# Your setup code here

echo "Servo_controller_web_ui setup completed!"
