#!/bin/bash

echo "=========================================="
echo "Pi Monitor vcgencmd Permission Fix"
echo "=========================================="

# Check current vcgencmd status
echo "Checking vcgencmd availability..."
if command -v vcgencmd >/dev/null 2>&1; then
    echo "✓ vcgencmd command exists"
else
    echo "✗ vcgencmd command not found - installing..."
    sudo apt update && sudo apt install -y libraspberrypi-bin
fi

# Check current user groups
echo ""
echo "Current pi-monitor user groups:"
groups pi-monitor

# Add pi-monitor user to required groups
echo ""
echo "Adding pi-monitor user to required groups..."
sudo usermod -a -G video,gpio,i2c,spi,dialout pi-monitor

echo "Updated pi-monitor user groups:"
groups pi-monitor

# Test vcgencmd access for pi-monitor user
echo ""
echo "Testing vcgencmd access for pi-monitor user..."
sudo -u pi-monitor vcgencmd measure_temp
VCGEN_EXIT_CODE=$?

if [ $VCGEN_EXIT_CODE -eq 0 ]; then
    echo "✓ vcgencmd working for pi-monitor user"
    
    # Restart the service
    echo ""
    echo "Restarting pi-monitor service..."
    sudo systemctl restart pi-monitor.service
    sleep 3
    
    # Check service status
    if systemctl is-active --quiet pi-monitor.service; then
        echo "✓ Service started successfully"
        PI_IP=$(hostname -I | awk '{print $1}')
        echo ""
        echo "Web interface should now be available at:"
        echo "  Local:   http://localhost:5000"
        echo "  Network: http://$PI_IP:5000"
    else
        echo "✗ Service still failing - checking logs..."
        sudo journalctl -u pi-monitor.service -n 5 --no-pager
    fi
else
    echo "✗ vcgencmd still not working - may need reboot for group changes"
    echo "Try: sudo reboot"
fi

echo ""
echo "Fix complete."
