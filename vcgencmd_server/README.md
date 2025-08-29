# Pi Monitor v3.0

A comprehensive web-based monitoring and overclocking interface for Raspberry Pi 5, designed for performance testing and thermal analysis.

## Quick Install

```bash
chmod +x install_pi_monitor.sh
./install_pi_monitor.sh
```

Access at `http://your-pi-ip:5000`

## Features

### Real-Time Monitoring
- **8-metric status grid**: Temperature, clock speed, voltage, throttle status, uptime, CPU load, memory usage, load averages
- **Live charting**: Temperature, clock frequency, and CPU usage with Chart.js
- **2x4 responsive layout**: Optimized for mobile and desktop viewing

### Performance Testing  
- **CPU stress testing**: Automatic `stress` package installation and management
- **Overclock configuration**: Safe frequency and voltage adjustment with Pi 5 validation
- **Dynamic warnings**: Only appear when exceeding Pi 5 defaults (>2400MHz CPU, >800MHz GPU, ≠0μV)

### Data Analysis
- **Snapshot saving**: Capture current state with notes and complete system metrics
- **Historical results**: View past test results with system performance context
- **Chart overlay mode**: Compare multiple test results visually
- **Application & system logs**: Real-time log viewing with auto-refresh

## Management

```bash
# Service control
./pi-monitor-control.sh {start|stop|restart|status|logs|open}

# Manual service commands
sudo systemctl {start|stop|restart} pi-monitor
sudo journalctl -u pi-monitor -f  # View logs
```

## File Structure

```
vcgencmd_server/
├── install_pi_monitor.sh      # Master installer
├── pi-monitor-control.sh      # Service management script  
├── backup/                    # Previous patch scripts
├── todo.md                    # Development notes
└── README.md                  # This file

/opt/pi-monitor/               # Installation directory
├── app.py                     # Flask web application
├── templates/                 # HTML templates
├── static/                    # CSS and JavaScript
└── venv/                      # Python virtual environment

/home/pi-monitor/              # Data directory
├── readings.txt               # Monitoring data
├── pi_monitor_results/        # Saved snapshots
└── app.log                    # Application logs
```

## Safety Notes

- **Monitor temperatures**: Keep below 80°C during stress testing
- **Adequate cooling**: Ensure proper heatsink/fan before overclocking  
- **Official power supply**: Use Pi 5 official 5V 5A adapter
- **Backup SD card**: Before attempting extreme overclocks

## Troubleshooting

**Service not starting:**
```bash
sudo journalctl -u pi-monitor.service -n 20
```

**System metrics showing '--':**
- Wait 30 seconds after page load for initialization
- Check service logs for sensor access errors

**Overclock apply failing:**
- Ensure adequate permissions in `/etc/sudoers.d/pi-monitor`
- Check `/tmp` directory is writable

**Web interface not accessible:**
- Check firewall: `sudo ufw status`
- Verify port 5000 is open: `sudo ufw allow 5000`

## Hardware Requirements

- **Raspberry Pi 5** (tested on Model B Rev 1.1)
- **Adequate cooling** for stress testing and overclocking
- **Network connection** for web interface access

Built for reliable Pi 5 performance monitoring and safe overclocking experimentation.
