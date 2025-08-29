#!/bin/bash

# Fix for Pi Monitor Installation Script
# Resolves permission issues with directory creation

echo "=========================================="
echo "Pi Monitor Installation Fix"
echo "=========================================="

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a regular user (not root)"
    exit 1
fi

echo "Fixing installation directories and permissions..."

# Define paths
INSTALL_DIR="/opt/pi-monitor"
SERVICE_USER="pi-monitor"

# Check if user exists
if id "$SERVICE_USER" &>/dev/null; then
    echo "User $SERVICE_USER exists, fixing directories..."
    
    # Create the actual home directory in /home if it doesn't exist
    sudo mkdir -p /home/$SERVICE_USER
    sudo chown $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER
    
    # Create the results directory in the correct location
    sudo mkdir -p /home/$SERVICE_USER/pi_monitor_results
    sudo chown $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER/pi_monitor_results
    
    # Ensure install directory exists and has correct ownership
    sudo mkdir -p $INSTALL_DIR
    sudo chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
    
    # Create subdirectories
    sudo mkdir -p $INSTALL_DIR/{templates,static,logs}
    sudo chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
    
    echo "✓ Directory structure fixed"
    echo "✓ Permissions corrected"
    echo ""
    echo "You can now continue with the installation."
    echo "Re-run: bash install_pi_monitor.sh"
    
else
    echo "User $SERVICE_USER not found. Please run the main installation script first."
    exit 1
fi

# Also fix the main installation script for future use
if [ -f "install_pi_monitor.sh" ]; then
    echo "Patching installation script..."
    
    # Create a corrected version
    sed 's|sudo -u $SERVICE_USER mkdir -p /home/$SERVICE_USER/pi_monitor_results|sudo mkdir -p /home/$SERVICE_USER/pi_monitor_results \&\& sudo chown $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER/pi_monitor_results|g' install_pi_monitor.sh > install_pi_monitor_fixed.sh
    
    chmod +x install_pi_monitor_fixed.sh
    echo "✓ Created fixed installation script: install_pi_monitor_fixed.sh"
fi

echo ""
echo "Fix complete! The installation should now proceed successfully."
