#!/bin/bash

echo "=========================================="
echo "Pi Monitor Systemd Service Fix"
echo "=========================================="

echo "The issue is systemd security restrictions blocking home directory access."
echo "Modifying service file..."

# Backup the current service file
sudo cp /etc/systemd/system/pi-monitor.service /etc/systemd/system/pi-monitor.service.backup

# Create new service file with relaxed security settings
sudo tee /etc/systemd/system/pi-monitor.service > /dev/null << 'EOF'
[Unit]
Description=Raspberry Pi Monitor Web Interface
After=network.target

[Service]
Type=simple
User=pi-monitor
Group=pi-monitor
WorkingDirectory=/opt/pi-monitor
Environment=PATH=/opt/pi-monitor/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/pi-monitor/venv/bin/python /opt/pi-monitor/app.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

# Relaxed security settings for Pi hardware access
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

echo "Service file updated with relaxed security settings."

# Reload systemd and restart service
sudo systemctl daemon-reload
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
    sleep 2
    if curl -s http://localhost:5000 >/dev/null; then
        echo "✓ Web interface responding"
    else
        echo "⚠ Web interface starting up..."
    fi
else
    echo "✗ Service still failing:"
    sudo journalctl -u pi-monitor.service -n 5 --no-pager
fi
