#!/bin/bash

echo "=========================================="
echo "Pi Monitor Fix Verification"
echo "=========================================="

PI_IP=$(hostname -I | awk '{print $1}')

echo "Testing Pi Monitor fixes..."
echo ""

# Test 1: Check service status
echo "1. Service Status:"
if systemctl is-active --quiet pi-monitor.service; then
    echo "   ✓ Service is running"
else
    echo "   ✗ Service is not running"
    sudo systemctl status pi-monitor.service --no-pager -l
fi

# Test 2: Check web interface response
echo ""
echo "2. Web Interface:"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000 | grep -q "200"; then
    echo "   ✓ Web interface responding (HTTP 200)"
else
    echo "   ✗ Web interface not responding"
fi

# Test 3: Check system metrics API
echo ""
echo "3. System Metrics API:"
API_RESPONSE=$(curl -s http://localhost:5000/api/status)
if echo "$API_RESPONSE" | grep -q "uptime"; then
    echo "   ✓ System metrics API responding"
    echo "   Sample data:"
    echo "$API_RESPONSE" | python3 -m json.tool | head -20
else
    echo "   ✗ System metrics API not working"
    echo "   Response: $API_RESPONSE"
fi

# Test 4: Check file permissions
echo ""
echo "4. File Permissions:"
if [ -w "/tmp" ]; then
    echo "   ✓ /tmp directory is writable (for overclock temp files)"
else
    echo "   ✗ /tmp directory not writable"
fi

if sudo -u pi-monitor test -r "/boot/firmware/config.txt"; then
    echo "   ✓ pi-monitor user can read config.txt"
else
    echo "   ✗ pi-monitor user cannot read config.txt"
fi

# Test 5: Check psutil installation
echo ""
echo "5. Python Dependencies:"
if sudo -u pi-monitor /opt/pi-monitor/venv/bin/python -c "import psutil; print('psutil version:', psutil.__version__)" 2>/dev/null; then
    echo "   ✓ psutil installed and working"
else
    echo "   ✗ psutil not working"
fi

if sudo -u pi-monitor /opt/pi-monitor/venv/bin/python -c "from vcgencmd import Vcgencmd; v=Vcgencmd(); print('vcgencmd temp:', v.measure_temp())" 2>/dev/null; then
    echo "   ✓ vcgencmd working"
else
    echo "   ✗ vcgencmd not working"
fi

# Test 6: Log file status
echo ""
echo "6. Log Files:"
LOG_FILE="/home/pi-monitor/app.log"
if [ -f "$LOG_FILE" ]; then
    echo "   ✓ Application log file exists: $LOG_FILE"
    echo "   Last 3 log entries:"
    tail -3 "$LOG_FILE" | sed 's/^/     /'
else
    echo "   ✗ Application log file not found"
fi

echo ""
echo "=========================================="
echo "ACCESS INFORMATION"
echo "=========================================="
echo ""
echo "Pi Monitor Web Interface:"
echo "  Local:   http://localhost:5000"
echo "  Network: http://$PI_IP:5000"
echo ""
echo "Expected Features:"
echo "  • 2x4 status grid with 8 real-time metrics"
echo "  • System metrics: uptime, CPU%, memory%, load avg"
echo "  • Dynamic overclock warning (only when exceeding defaults)"
echo "  • Working overclock apply functionality"
echo "  • Live charts and historical snapshots"
echo ""
echo "If system metrics still show '--', wait 30 seconds and refresh the page."
echo "System metrics initialize after the first API status call."
