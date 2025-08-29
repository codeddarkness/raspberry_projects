#!/bin/bash

echo "=========================================="
echo "Pi Monitor Directory Permission Fix"
echo "=========================================="

# Check current ownership and permissions
echo "Current /home/pi-monitor status:"
ls -la /home/ | grep pi-monitor

echo ""
echo "Fixing ownership and permissions..."

# Fix ownership of the home directory
sudo chown -R pi-monitor:pi-monitor /home/pi-monitor
sudo chmod 755 /home/pi-monitor

# Ensure the results directory exists with correct permissions
sudo mkdir -p /home/pi-monitor/pi_monitor_results
sudo chown -R pi-monitor:pi-monitor /home/pi-monitor/pi_monitor_results
sudo chmod -R 755 /home/pi-monitor/pi_monitor_results

# Fix the readings file location
sudo touch /home/pi-monitor/readings.txt
sudo chown pi-monitor:pi-monitor /home/pi-monitor/readings.txt
sudo chmod 644 /home/pi-monitor/readings.txt

echo "Updated permissions:"
ls -la /home/pi-monitor/

echo ""
echo "Restarting pi-monitor service..."
sudo systemctl stop pi-monitor.service
sleep 2
sudo systemctl start pi-monitor.service
sleep 3

# Check service status
if systemctl is-active --quiet pi-monitor.service; then
    echo "✓ Service started successfully"
    PI_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "Web interface available at:"
    echo "  Local:   http://localhost:5000"
    echo "  Network: http://$PI_IP:5000"
    
    # Test web response
    if curl -s http://localhost:5000 >/dev/null; then
        echo "✓ Web interface responding"
    else
        echo "⚠ Web interface not responding yet (may need a moment)"
    fi
else
    echo "✗ Service still failing:"
    sudo journalctl -u pi-monitor.service -n 3 --no-pager
fi
