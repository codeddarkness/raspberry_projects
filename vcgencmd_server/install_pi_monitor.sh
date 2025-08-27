#!/bin/bash

# Raspberry Pi 5 Monitor Web Interface Installation Script
# Sets up a comprehensive monitoring system with overclocking controls

set -e

echo "=========================================="
echo "Raspberry Pi 5 Monitor Installation"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    print_warning "This script is designed for Raspberry Pi"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a regular user (not root)"
    echo "The script will use sudo when needed"
    exit 1
fi

# Check available disk space
AVAILABLE_SPACE=$(df /home | tail -1 | awk '{print $4}')
AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))

if [ $AVAILABLE_GB -lt 1 ]; then
    print_warning "Low disk space: ${AVAILABLE_GB}GB available"
    echo "At least 1GB recommended for installation"
fi

# Define installation paths
INSTALL_DIR="/opt/pi-monitor"
SERVICE_USER="pi-monitor"
WEB_PORT="5000"

echo ""
print_info "Installation will create:"
echo "  - System service: pi-monitor.service"
echo "  - Installation directory: $INSTALL_DIR"
echo "  - Web interface on port: $WEB_PORT"
echo "  - Service user: $SERVICE_USER"
echo ""

read -p "Continue with installation? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 0
fi

echo ""
echo "Step 1: Installing system dependencies..."

# Update package list
sudo apt update

# Install Python and pip if not present
if ! command -v python3 &> /dev/null; then
    sudo apt install -y python3 python3-pip
    print_status 0 "Python3 installed"
else
    print_status 0 "Python3 already installed"
fi

# Install system packages
sudo apt install -y python3-venv git curl

echo ""
echo "Step 2: Creating system user and directories..."

# Create system user for the service
if ! id "$SERVICE_USER" &>/dev/null; then
    sudo useradd --system --shell /bin/false --home-dir $INSTALL_DIR --create-home $SERVICE_USER
    # Add pi-monitor user to necessary groups
    sudo usermod -a -G gpio,i2c,spi $SERVICE_USER
    print_status 0 "Created system user: $SERVICE_USER"
else
    print_status 0 "System user already exists: $SERVICE_USER"
fi

# Create installation directory
sudo mkdir -p $INSTALL_DIR
sudo chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR

# Create subdirectories
sudo -u $SERVICE_USER mkdir -p $INSTALL_DIR/{templates,static,logs}
sudo -u $SERVICE_USER mkdir -p /home/$SERVICE_USER/pi_monitor_results

print_status 0 "Created directory structure"

echo ""
echo "Step 3: Setting up Python virtual environment..."

# Create virtual environment
sudo -u $SERVICE_USER python3 -m venv $INSTALL_DIR/venv
print_status 0 "Created virtual environment"

# Install Python packages
sudo -u $SERVICE_USER $INSTALL_DIR/venv/bin/pip install --upgrade pip
sudo -u $SERVICE_USER $INSTALL_DIR/venv/bin/pip install flask vcgencmd

print_status 0 "Installed Python dependencies"

echo ""
echo "Step 4: Creating application files..."

# Create the main Python application
sudo -u $SERVICE_USER tee $INSTALL_DIR/app.py > /dev/null << 'EOF'
#!/usr/bin/env python3

import os
import sys
import time
import json
import subprocess
import threading
from datetime import datetime
from flask import Flask, render_template, jsonify, request, redirect, url_for
from vcgencmd import Vcgencmd

app = Flask(__name__)
vcgm = Vcgencmd()

# Global variables for monitoring
monitoring_active = False
monitoring_thread = None
stress_process = None
current_data = {
    'temperature': 0,
    'clock_speed': 0,
    'throttled': False,
    'voltage': 0,
    'elapsed_time': 0
}

class PiMonitor:
    def __init__(self):
        self.start_time = time.time()
        self.data_file = "/home/pi-monitor/readings.txt"
        self.results_dir = "/home/pi-monitor/pi_monitor_results"
        self.ensure_directories()
        
    def ensure_directories(self):
        os.makedirs(self.results_dir, exist_ok=True)
        
    def get_current_readings(self):
        try:
            temp = float(str(vcgm.measure_temp()).replace('°C', ''))
            clock = int(vcgm.measure_clock('arm') / 1000000)
            throttled = vcgm.get_throttled()['breakdown']['2']
            voltage = float(str(vcgm.measure_volts('core')).replace('V', ''))
            elapsed = time.time() - self.start_time
            
            return {
                'temperature': temp,
                'clock_speed': clock,
                'throttled': throttled,
                'voltage': voltage,
                'elapsed_time': elapsed
            }
        except Exception as e:
            print(f"Error reading sensors: {e}")
            return current_data
    
    def start_monitoring(self):
        global monitoring_active, current_data
        monitoring_active = True
        
        with open(self.data_file, 'a+') as fb:
            fb.write(f"\n# Session started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            fb.write("Elapsed Time (s),Temperature (°C),Clock Speed (MHz),Throttled,Voltage (V)\n")
            
            while monitoring_active:
                try:
                    data = self.get_current_readings()
                    current_data = data
                    
                    line = f"{data['elapsed_time']:.0f},{data['temperature']},{data['clock_speed']},{data['throttled']},{data['voltage']:.4f}\n"
                    fb.write(line)
                    fb.flush()
                    time.sleep(1)
                except Exception as e:
                    print(f"Monitoring error: {e}")
                    time.sleep(1)

monitor = PiMonitor()

def check_stress_installed():
    try:
        result = subprocess.run(['which', 'stress'], capture_output=True, text=True)
        return result.returncode == 0
    except:
        return False

def install_stress():
    try:
        subprocess.run(['sudo', 'apt', 'update'], check=True)
        subprocess.run(['sudo', 'apt', 'install', '-y', 'stress'], check=True)
        return True
    except subprocess.CalledProcessError:
        return False

def get_current_overclock_settings():
    config_file = "/boot/firmware/config.txt"
    settings = {
        'arm_freq': 2400,
        'gpu_freq': 800,
        'over_voltage_delta': 0
    }
    
    try:
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('arm_freq='):
                    settings['arm_freq'] = int(line.split('=')[1])
                elif line.startswith('gpu_freq='):
                    settings['gpu_freq'] = int(line.split('=')[1])
                elif line.startswith('over_voltage_delta='):
                    settings['over_voltage_delta'] = int(line.split('=')[1])
    except Exception as e:
        print(f"Error reading config: {e}")
    
    return settings

def apply_overclock_settings(arm_freq, gpu_freq, voltage_delta):
    config_file = "/boot/firmware/config.txt"
    backup_file = f"{config_file}.backup.{int(time.time())}"
    
    try:
        # Create backup
        subprocess.run(['sudo', 'cp', config_file, backup_file], check=True)
        
        # Read current config
        with open(config_file, 'r') as f:
            lines = f.readlines()
        
        # Remove existing overclock settings
        lines = [line for line in lines if not any(
            line.strip().startswith(setting) for setting in 
            ['arm_freq=', 'gpu_freq=', 'over_voltage_delta=']
        )]
        
        # Add new settings
        lines.append(f"\n# Overclock settings applied {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        if arm_freq != 2400:
            lines.append(f"arm_freq={arm_freq}\n")
        if gpu_freq != 800:
            lines.append(f"gpu_freq={gpu_freq}\n")
        if voltage_delta != 0:
            lines.append(f"over_voltage_delta={voltage_delta}\n")
        
        # Write back
        temp_file = f"{config_file}.tmp"
        with open(temp_file, 'w') as f:
            f.writelines(lines)
        
        subprocess.run(['sudo', 'mv', temp_file, config_file], check=True)
        return True
        
    except Exception as e:
        print(f"Error applying overclock settings: {e}")
        return False

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/results')
def results():
    results_files = []
    try:
        for filename in os.listdir(monitor.results_dir):
            if filename.endswith('.json'):
                filepath = os.path.join(monitor.results_dir, filename)
                with open(filepath, 'r') as f:
                    data = json.load(f)
                results_files.append({
                    'filename': filename,
                    'timestamp': data.get('timestamp', ''),
                    'notes': data.get('notes', ''),
                    'settings': data.get('overclock_settings', {}),
                    'peak_temp': data.get('peak_temp', 0),
                    'avg_temp': data.get('avg_temp', 0)
                })
    except Exception as e:
        print(f"Error loading results: {e}")
    
    return render_template('results.html', results=results_files)

@app.route('/api/status')
def api_status():
    global monitoring_active, stress_process
    return jsonify({
        'monitoring_active': monitoring_active,
        'stress_active': stress_process is not None and stress_process.poll() is None,
        'stress_installed': check_stress_installed(),
        'current_data': current_data,
        'overclock_settings': get_current_overclock_settings()
    })

@app.route('/api/start_monitoring', methods=['POST'])
def start_monitoring():
    global monitoring_thread, monitoring_active
    
    if not monitoring_active:
        monitor.start_time = time.time()
        monitoring_thread = threading.Thread(target=monitor.start_monitoring)
        monitoring_thread.daemon = True
        monitoring_thread.start()
    
    return jsonify({'success': True})

@app.route('/api/stop_monitoring', methods=['POST'])
def stop_monitoring():
    global monitoring_active
    monitoring_active = False
    return jsonify({'success': True})

@app.route('/api/start_stress', methods=['POST'])
def start_stress():
    global stress_process
    
    if not check_stress_installed():
        if not install_stress():
            return jsonify({'success': False, 'error': 'Failed to install stress'})
    
    if stress_process is None or stress_process.poll() is not None:
        try:
            stress_process = subprocess.Popen(['stress', '--cpu', '4'])
            return jsonify({'success': True})
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)})
    
    return jsonify({'success': True, 'message': 'Stress test already running'})

@app.route('/api/stop_stress', methods=['POST'])
def stop_stress():
    global stress_process
    
    if stress_process and stress_process.poll() is None:
        stress_process.terminate()
        stress_process.wait()
        stress_process = None
    
    return jsonify({'success': True})

@app.route('/api/apply_overclock', methods=['POST'])
def apply_overclock():
    data = request.json
    
    try:
        arm_freq = int(data.get('arm_freq', 2400))
        gpu_freq = int(data.get('gpu_freq', 800))
        voltage_delta = int(data.get('voltage_delta', 0))
        restart = data.get('restart', False)
        
        # Validate ranges
        if not (1000 <= arm_freq <= 3200):
            return jsonify({'success': False, 'error': 'ARM frequency must be between 1000-3200 MHz'})
        if not (400 <= gpu_freq <= 1200):
            return jsonify({'success': False, 'error': 'GPU frequency must be between 400-1200 MHz'})
        if not (-100000 <= voltage_delta <= 100000):
            return jsonify({'success': False, 'error': 'Voltage delta must be between -100000 to 100000 μV'})
        
        if apply_overclock_settings(arm_freq, gpu_freq, voltage_delta):
            if restart:
                subprocess.Popen(['sudo', 'reboot'])
                return jsonify({'success': True, 'message': 'Settings applied, rebooting...'})
            else:
                return jsonify({'success': True, 'message': 'Settings applied, reboot required to take effect'})
        else:
            return jsonify({'success': False, 'error': 'Failed to apply settings'})
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/save_snapshot', methods=['POST'])
def save_snapshot():
    data = request.json
    notes = data.get('notes', '')
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filename = f"snapshot_{timestamp}.json"
    filepath = os.path.join(monitor.results_dir, filename)
    
    # Calculate some statistics from recent data
    try:
        with open(monitor.data_file, 'r') as f:
            lines = f.readlines()
        
        # Get last 60 readings (1 minute)
        recent_temps = []
        for line in lines[-60:]:
            if line.startswith('#') or 'Elapsed' in line:
                continue
            try:
                parts = line.strip().split(',')
                if len(parts) >= 2:
                    recent_temps.append(float(parts[1]))
            except:
                continue
        
        peak_temp = max(recent_temps) if recent_temps else current_data['temperature']
        avg_temp = sum(recent_temps) / len(recent_temps) if recent_temps else current_data['temperature']
        
    except:
        peak_temp = current_data['temperature']
        avg_temp = current_data['temperature']
    
    snapshot_data = {
        'timestamp': datetime.now().isoformat(),
        'notes': notes,
        'current_data': current_data,
        'overclock_settings': get_current_overclock_settings(),
        'peak_temp': round(peak_temp, 1),
        'avg_temp': round(avg_temp, 1)
    }
    
    try:
        with open(filepath, 'w') as f:
            json.dump(snapshot_data, f, indent=2)
        return jsonify({'success': True, 'filename': filename})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Create templates directory structure and files
sudo -u $SERVICE_USER tee $INSTALL_DIR/templates/base.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Pi Monitor{% endblock %}</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
</head>
<body>
    <nav class="navbar">
        <div class="nav-container">
            <h1 class="nav-title">Raspberry Pi Monitor</h1>
            <div class="nav-links">
                <a href="{{ url_for('index') }}" class="nav-link {% if request.endpoint == 'index' %}active{% endif %}">Monitor</a>
                <a href="{{ url_for('results') }}" class="nav-link {% if request.endpoint == 'results' %}active{% endif %}">Results</a>
            </div>
        </div>
    </nav>

    <main class="container">
        {% block content %}{% endblock %}
    </main>

    <script src="{{ url_for('static', filename='app.js') }}"></script>
</body>
</html>
EOF

sudo -u $SERVICE_USER tee $INSTALL_DIR/templates/index.html > /dev/null << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="dashboard">
    <!-- Status Cards -->
    <div class="status-grid">
        <div class="status-card">
            <h3>Temperature</h3>
            <div class="status-value" id="temperature">--°C</div>
            <div class="status-indicator" id="temp-indicator"></div>
        </div>
        
        <div class="status-card">
            <h3>Clock Speed</h3>
            <div class="status-value" id="clock-speed">-- MHz</div>
        </div>
        
        <div class="status-card">
            <h3>Voltage</h3>
            <div class="status-value" id="voltage">-- V</div>
        </div>
        
        <div class="status-card">
            <h3>Throttled</h3>
            <div class="status-value" id="throttled">--</div>
            <div class="status-indicator" id="throttle-indicator"></div>
        </div>
    </div>

    <!-- Control Panel -->
    <div class="control-panel">
        <div class="section">
            <h2>Monitoring Control</h2>
            <div class="button-group">
                <button id="start-monitor" class="btn btn-primary">Start Monitoring</button>
                <button id="stop-monitor" class="btn btn-secondary">Stop Monitoring</button>
                <span id="monitor-status" class="status-text">Stopped</span>
            </div>
        </div>

        <div class="section">
            <h2>Stress Testing</h2>
            <div class="button-group">
                <button id="start-stress" class="btn btn-warning">Start Stress Test</button>
                <button id="stop-stress" class="btn btn-secondary">Stop Stress Test</button>
                <span id="stress-status" class="status-text">Stopped</span>
                <span id="stress-install-status" class="status-text"></span>
            </div>
        </div>
    </div>

    <!-- Overclocking Controls -->
    <div class="overclock-panel">
        <h2>Overclock Settings</h2>
        <div class="warning-box">
            <strong>⚠️ Warning:</strong> Overclocking can damage your Pi. Ensure adequate cooling and power supply.
            Settings require reboot to take effect.
        </div>
        
        <form id="overclock-form">
            <div class="form-grid">
                <div class="form-group">
                    <label for="arm-freq">CPU Frequency (MHz)</label>
                    <input type="number" id="arm-freq" min="1000" max="3200" value="2400">
                    <small>Default: 2400 MHz (Range: 1000-3200)</small>
                </div>
                
                <div class="form-group">
                    <label for="gpu-freq">GPU Frequency (MHz)</label>
                    <input type="number" id="gpu-freq" min="400" max="1200" value="800">
                    <small>Default: 800 MHz (Range: 400-1200)</small>
                </div>
                
                <div class="form-group">
                    <label for="voltage-delta">Voltage Delta (μV)</label>
                    <input type="number" id="voltage-delta" min="-100000" max="100000" value="0" step="1000">
                    <small>Default: 0 μV (Range: -100,000 to +100,000)</small>
                </div>
            </div>
            
            <div class="button-group">
                <button type="button" id="apply-settings" class="btn btn-primary">Apply Settings</button>
                <button type="button" id="apply-restart" class="btn btn-danger">Apply & Restart</button>
            </div>
        </form>
    </div>

    <!-- Snapshot Section -->
    <div class="snapshot-panel">
        <h2>Save Snapshot</h2>
        <div class="form-group">
            <label for="notes">Notes</label>
            <textarea id="notes" placeholder="Add notes about current test conditions..."></textarea>
        </div>
        <button id="save-snapshot" class="btn btn-primary">Save Snapshot</button>
    </div>
</div>

<!-- Message Toast -->
<div id="toast" class="toast"></div>
{% endblock %}
EOF

sudo -u $SERVICE_USER tee $INSTALL_DIR/templates/results.html > /dev/null << 'EOF'
{% extends "base.html" %}
{% block title %}Results - Pi Monitor{% endblock %}
{% block content %}
<div class="results-page">
    <h2>Test Results</h2>
    
    {% if results %}
    <div class="results-grid">
        {% for result in results %}
        <div class="result-card">
            <div class="result-header">
                <h3>{{ result.timestamp[:19] | replace('T', ' ') }}</h3>
                <div class="result-stats">
                    <span class="stat">Peak: {{ result.peak_temp }}°C</span>
                    <span class="stat">Avg: {{ result.avg_temp }}°C</span>
                </div>
            </div>
            
            {% if result.notes %}
            <div class="result-notes">
                <strong>Notes:</strong> {{ result.notes }}
            </div>
            {% endif %}
            
            <div class="result-settings">
                <strong>Settings:</strong>
                CPU: {{ result.settings.arm_freq or 2400 }}MHz, 
                GPU: {{ result.settings.gpu_freq or 800 }}MHz, 
                Voltage: {{ result.settings.over_voltage_delta or 0 }}μV
            </div>
        </div>
        {% endfor %}
    </div>
    {% else %}
    <div class="empty-results">
        <p>No test results saved yet.</p>
        <a href="{{ url_for('index') }}" class="btn btn-primary">Start Monitoring</a>
    </div>
    {% endif %}
</div>
{% endblock %}
EOF

print_status 0 "Created HTML templates"

echo ""
echo "Step 5: Creating static files (CSS and JavaScript)..."

# Create CSS file - Note: This is a simplified version due to length constraints
sudo -u $SERVICE_USER tee $INSTALL_DIR/static/style.css > /dev/null << 'EOF'
:root {
    --bg-primary: #1a1a1a;
    --bg-secondary: #2d2d2d;
    --bg-tertiary: #3a3a3a;
    --text-primary: #e0e0e0;
    --text-secondary: #b0b0b0;
    --text-muted: #808080;
    --accent-primary: #4a9eff;
    --success: #4caf50;
    --warning: #ff9800;
    --danger: #f44336;
    --border: #404040;
    --shadow: rgba(0, 0, 0, 0.3);
}

* { margin: 0; padding: 0; box-sizing: border-box; }

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background-color: var(--bg-primary);
    color: var(--text-primary);
    line-height: 1.6;
    min-height: 100vh;
}

.navbar {
    background-color: var(--bg-secondary);
    border-bottom: 1px solid var(--border);
    padding: 1rem 0;
    position: sticky;
    top: 0;
    z-index: 100;
}

.nav-container {
    max-width: 1200px;
    margin: 0 auto;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 2rem;
}

.nav-title {
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--accent-primary);
}

.nav-links {
    display: flex;
    gap: 2rem;
}

.nav-link {
    color: var(--text-secondary);
    text-decoration: none;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    transition: all 0.2s ease;
}

.nav-link:hover, .nav-link.active {
    color: var(--text-primary);
    background-color: var(--bg-tertiary);
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 2rem;
}

.dashboard {
    display: flex;
    flex-direction: column;
    gap: 2rem;
}

.status-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
}

.status-card {
    background-color: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1.5rem;
    text-align: center;
    position: relative;
    box-shadow: 0 2px 4px var(--shadow);
}

.status-card h3 {
    font-size: 0.9rem;
    color: var(--text-secondary);
    margin-bottom: 0.5rem;
    text-transform: uppercase;
}

.status-value {
    font-size: 1.8rem;
    font-weight: 600;
    color: var(--text-primary);
}

.status-indicator {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    position: absolute;
    top: 1rem;
    right: 1rem;
    background-color: var(--text-muted);
}

.status-indicator.good { background-color: var(--success); }
.status-indicator.warning { background-color: var(--warning); }
.status-indicator.danger { background-color: var(--danger); }

.control-panel, .overclock-panel, .snapshot-panel {
    background-color: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1.5rem;
    box-shadow: 0 2px 4px var(--shadow);
}

.control-panel h2, .overclock-panel h2, .snapshot-panel h2 {
    color: var(--text-primary);
    margin-bottom: 1rem;
    font-size: 1.3rem;
}

.section {
    margin-bottom: 1.5rem;
}

.button-group {
    display: flex;
    gap: 1rem;
    align-items: center;
    flex-wrap: wrap;
}

.btn {
    padding: 0.75rem 1.5rem;
    border: none;
    border-radius: 4px;
    font-size: 0.9rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
}

.btn:disabled { opacity: 0.5; cursor: not-allowed; }
.btn-primary { background-color: var(--accent-primary); color: white; }
.btn-secondary { background-color: var(--bg-tertiary); color: var(--text-primary); }
.btn-warning { background-color: var(--warning); color: white; }
.btn-danger { background-color: var(--danger); color: white; }

.warning-box {
    background-color: rgba(255, 152, 0, 0.1);
    border: 1px solid var(--warning);
    border-radius: 4px;
    padding: 1rem;
    margin-bottom: 1.5rem;
    color: var(--warning);
}

.form-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1.5rem;
    margin-bottom: 1.5rem;
}

.form-group {
    display: flex;
    flex-direction: column;
}

.form-group label {
    color: var(--text-secondary);
    margin-bottom: 0.5rem;
    font-weight: 500;
}

.form-group input, .form-group textarea {
    background-color: var(--bg-tertiary);
    border: 1px solid var(--border);
    border-radius: 4px;
    padding: 0.75rem;
    color: var(--text-primary);
}

.form-group small {
    color: var(--text-muted);
    font-size: 0.8rem;
    margin-top: 0.25rem;
}

.toast {
    position: fixed;
    top: 20px;
    right: 20px;
    padding: 1rem 1.5rem;
    border-radius: 4px;
    color: white;
    z-index: 1000;
    opacity: 0;
    transform: translateY(-20px);
    transition: all 0.3s ease;
}

.toast.show { opacity: 1; transform: translateY(0); }
.toast.success { background-color: var(--success); }
.toast.warning { background-color: var(--warning); }
.toast.error { background-color: var(--danger); }

.results-grid {
    display: grid;
    gap: 1.5rem;
}

.result-card {
    background-color: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1.5rem;
}

.result-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
}

.status-text {
    color: var(--text-secondary);
    font-size: 0.9rem;
}

@media (max-width: 768px) {
    .container { padding: 1rem; }
    .status-grid { grid-template-columns: 1fr; }
    .form-grid { grid-template-columns: 1fr; }
    .button-group { flex-direction: column; align-items: stretch; }
}
EOF

# Create JavaScript file - Simplified version
sudo -u $SERVICE_USER tee $INSTALL_DIR/static/app.js > /dev/null << 'EOF'
class PiMonitor {
    constructor() {
        this.updateInterval = null;
        this.init();
    }

    init() {
        this.bindEvents();
        this.loadCurrentSettings();
        this.startStatusUpdates();
    }

    bindEvents() {
        document.getElementById('start-monitor')?.addEventListener('click', () => this.startMonitoring());
        document.getElementById('stop-monitor')?.addEventListener('click', () => this.stopMonitoring());
        document.getElementById('start-stress')?.addEventListener('click', () => this.startStress());
        document.getElementById('stop-stress')?.addEventListener('click', () => this.stopStress());
        document.getElementById('apply-settings')?.addEventListener('click', () => this.applyOverclock(false));
        document.getElementById('apply-restart')?.addEventListener('click', () => this.applyOverclock(true));
        document.getElementById('save-snapshot')?.addEventListener('click', () => this.saveSnapshot());
    }

    async apiCall(endpoint, method = 'GET', data = null) {
        const options = { method, headers: { 'Content-Type': 'application/json' } };
        if (data) options.body = JSON.stringify(data);

        try {
            const response = await fetch(`/api${endpoint}`, options);
            return await response.json();
        } catch (error) {
            console.error('API call failed:', error);
            this.showToast('Network error', 'error');
            return { success: false, error: 'Network error' };
        }
    }

    async startMonitoring() {
        const result = await this.apiCall('/start_monitoring', 'POST');
        this.showToast(result.success ? 'Monitoring started' : 'Failed to start monitoring', result.success ? 'success' : 'error');
    }

    async stopMonitoring() {
        const result = await this.apiCall('/stop_monitoring', 'POST');
        this.showToast(result.success ? 'Monitoring stopped' : 'Failed to stop monitoring', result.success ? 'success' : 'error');
    }

    async startStress() {
        const result = await this.apiCall('/start_stress', 'POST');
        this.showToast(result.success ? 'Stress test started' : result.error, result.success ? 'success' : 'error');
    }

    async stopStress() {
        const result = await this.apiCall('/stop_stress', 'POST');
        this.showToast(result.success ? 'Stress test stopped' : 'Failed to stop stress test', result.success ? 'success' : 'error');
    }

    async applyOverclock(restart = false) {
        const armFreq = document.getElementById('arm-freq')?.value;
        const gpuFreq = document.getElementById('gpu-freq')?.value;
        const voltageDelta = document.getElementById('voltage-delta')?.value;

        if (!armFreq || !gpuFreq || voltageDelta === '') {
            this.showToast('Please fill in all fields', 'error');
            return;
        }

        if (parseInt(armFreq) > 3000 || parseInt(voltageDelta) > 50000 || restart) {
            if (!confirm(`Are you sure? This can damage your Pi!\n\nCPU: ${armFreq}MHz\nGPU: ${gpuFreq}MHz\nVoltage: ${voltageDelta}μV`)) {
                return;
            }
        }

        const result = await this.apiCall('/apply_overclock', 'POST', {
            arm_freq: parseInt(armFreq),
            gpu_freq: parseInt(gpuFreq),
            voltage_delta: parseInt(voltageDelta),
            restart: restart
        });

        this.showToast(result.success ? result.message : result.error, result.success ? 'success' : 'error');
    }

    async saveSnapshot() {
        const notes = document.getElementById('notes')?.value || '';
        const result = await this.apiCall('/save_snapshot', 'POST', { notes });
        
        if (result.success) {
            this.showToast('Snapshot saved', 'success');
            document.getElementById('notes').value = '';
        } else {
            this.showToast(result.error, 'error');
        }
    }

    async loadCurrentSettings() {
        const result = await this.apiCall('/status');
        if (result.success !== false && result.overclock_settings) {
            const s = result.overclock_settings;
            document.getElementById('arm-freq').value = s.arm_freq || 2400;
            document.getElementById('gpu-freq').value = s.gpu_freq || 800;
            document.getElementById('voltage-delta').value = s.over_voltage_delta || 0;
        }
    }

    startStatusUpdates() {
        this.updateStatus();
        this.updateInterval = setInterval(() => this.updateStatus(), 2000);
    }

    async updateStatus() {
        const result = await this.apiCall('/status');
        if (result.success === false) return;

        this.updateMonitoringStatus(result.monitoring_active);
        this.updateStressStatus(result.stress_active, result.stress_installed);
        
        if (result.current_data) {
            this.updateSensorReadings(result.current_data);
        }
    }

    updateMonitoringStatus(active) {
        const status = document.getElementById('monitor-status');
        const startBtn = document.getElementById('start-monitor');
        const stopBtn = document.getElementById('stop-monitor');

        if (status) {
            status.textContent = active ? 'Running' : 'Stopped';
            status.style.color = active ? 'var(--success)' : 'var(--text-secondary)';
        }
        if (startBtn) startBtn.disabled = active;
        if (stopBtn) stopBtn.disabled = !active;
    }

    updateStressStatus(active, installed) {
        const status = document.getElementById('stress-status');
        const startBtn = document.getElementById('start-stress');
        const stopBtn = document.getElementById('stop-stress');

        if (status) {
            status.textContent = active ? 'Running' : 'Stopped';
            status.style.color = active ? 'var(--warning)' : 'var(--text-secondary)';
        }
        if (startBtn) {
            startBtn.disabled = active;
            startBtn.textContent = installed ? 'Start Stress Test' : 'Install & Start Stress Test';
        }
        if (stopBtn) stopBtn.disabled = !active;
    }

    updateSensorReadings(data) {
        const temp = document.getElementById('temperature');
        const tempIndicator = document.getElementById('temp-indicator');
        const clock = document.getElementById('clock-speed');
        const voltage = document.getElementById('voltage');
        const throttled = document.getElementById('throttled');
        const throttleIndicator = document.getElementById('throttle-indicator');

        if (temp) {
            temp.textContent = `${data.temperature.toFixed(1)}°C`;
            if (tempIndicator) {
                tempIndicator.className = 'status-indicator ' + 
                    (data.temperature < 60 ? 'good' : data.temperature < 75 ? 'warning' : 'danger');
            }
        }
        
        if (clock) clock.textContent = `${data.clock_speed} MHz`;
        if (voltage) voltage.textContent = `${data.voltage.toFixed(4)} V`;
        
        if (throttled) {
            throttled.textContent = data.throttled ? 'YES' : 'NO';
            if (throttleIndicator) {
                throttleIndicator.className = 'status-indicator ' + (data.throttled ? 'danger' : 'good');
            }
        }
    }

    showToast(message, type = 'success') {
        const toast = document.getElementById('toast');
        if (!toast) return;

        toast.textContent = message;
        toast.className = `toast ${type}`;
        
        setTimeout(() => toast.classList.add('show'), 10);
        setTimeout(() => toast.classList.remove('show'), 4000);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    window.piMonitor = new PiMonitor();
});
EOF

print_status 0 "Created static files (CSS/JS)"

echo ""
echo "Step 6: Setting up permissions and sudoers..."

# Add the pi-monitor user to sudoers for specific commands
sudo tee /etc/sudoers.d/pi-monitor > /dev/null << EOF
# Pi Monitor service permissions
pi-monitor ALL=(ALL) NOPASSWD: /usr/bin/apt update
pi-monitor ALL=(ALL) NOPASSWD: /usr/bin/apt install -y stress
pi-monitor ALL=(ALL) NOPASSWD: /bin/cp /boot/firmware/config.txt /boot/firmware/config.txt.backup.*
pi-monitor ALL=(ALL) NOPASSWD: /bin/mv /boot/firmware/config.txt.tmp /boot/firmware/config.txt
pi-monitor ALL=(ALL) NOPASSWD: /sbin/reboot
EOF

print_status 0 "Configured sudoers permissions"

echo ""
echo "Step 7: Creating systemd service..."

# Create systemd service file
sudo tee /etc/systemd/system/pi-monitor.service > /dev/null << EOF
[Unit]
Description=Raspberry Pi Monitor Web Interface
After=network.target

[Service]
Type=simple
User=pi-monitor
Group=pi-monitor
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/app.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_DIR /home/pi-monitor /boot/firmware
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

[Install]
WantedBy=multi-user.target
EOF

print_status 0 "Created systemd service"

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable pi-monitor.service

print_status 0 "Enabled service for boot start"

echo ""
echo "Step 8: Configuring firewall (if present)..."

# Configure UFW firewall if present
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status | head -1)
    if echo "$UFW_STATUS" | grep -q "active"; then
        sudo ufw allow $WEB_PORT
        print_status 0 "Opened port $WEB_PORT in firewall"
    else
        print_info "UFW firewall is inactive"
    fi
else
    print_info "UFW firewall not installed"
fi

echo ""
echo "Step 9: Starting service..."

# Start the service
sudo systemctl start pi-monitor.service
sleep 3

# Check service status
if systemctl is-active --quiet pi-monitor.service; then
    print_status 0 "Service started successfully"
else
    print_status 1 "Service failed to start"
    echo "Check logs with: sudo journalctl -u pi-monitor.service -f"
fi

echo ""
echo "Step 10: Creating management scripts..."

# Create management script
tee ~/pi-monitor-control.sh > /dev/null << 'EOF'
#!/bin/bash
# Pi Monitor Control Script

SERVICE_NAME="pi-monitor"
WEB_PORT="5000"
PI_IP=$(hostname -I | awk '{print $1}')

case $1 in
    start)
        echo "Starting Pi Monitor..."
        sudo systemctl start $SERVICE_NAME
        ;;
    stop)
        echo "Stopping Pi Monitor..."
        sudo systemctl stop $SERVICE_NAME
        ;;
    restart)
        echo "Restarting Pi Monitor..."
        sudo systemctl restart $SERVICE_NAME
        ;;
    status)
        sudo systemctl status $SERVICE_NAME
        ;;
    logs)
        sudo journalctl -u $SERVICE_NAME -f
        ;;
    open)
        echo "Pi Monitor Web Interface:"
        echo "  Local:   http://localhost:$WEB_PORT"
        echo "  Network: http://$PI_IP:$WEB_PORT"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|open}"
        echo ""
        echo "Pi Monitor Web Interface:"
        echo "  Local:   http://localhost:$WEB_PORT"
        echo "  Network: http://$PI_IP:$WEB_PORT"
        ;;
esac
EOF

chmod +x ~/pi-monitor-control.sh

print_status 0 "Created management script: ~/pi-monitor-control.sh"

echo ""
echo "=========================================="
echo "INSTALLATION COMPLETE!"
echo "=========================================="

PI_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "Pi Monitor Web Interface is now available at:"
echo "  Local access:   http://localhost:$WEB_PORT"
echo "  Network access: http://$PI_IP:$WEB_PORT"
echo ""

echo "Service Management:"
echo "  Control script: ~/pi-monitor-control.sh"
echo "  Start service:  sudo systemctl start pi-monitor"
echo "  Stop service:   sudo systemctl stop pi-monitor"
echo "  View logs:      sudo journalctl -u pi-monitor -f"
echo ""

echo "Features Available:"
echo "  • Real-time temperature, clock speed, and voltage monitoring"
echo "  • CPU stress testing with automatic package installation"
echo "  • Overclock/underclock configuration with Jeff Geerling methodology"
echo "  • Snapshot saving with notes for test results"
echo "  • Dark mode interface optimized for Pi displays"
echo ""

echo "Safety Notes:"
echo "  • Always ensure adequate cooling before overclocking"
echo "  • Use the official Pi 5 power supply (5V 5A)"
echo "  • Monitor temperatures during stress testing"
echo "  • Backup your SD card before extreme overclocking"
echo ""

if systemctl is-active --quiet pi-monitor.service; then
    print_status 0 "Service is running and ready to use!"
else
    print_status 1 "Service not running - check logs for issues"
    echo "Debug: sudo journalctl -u pi-monitor.service"
fi

echo ""
echo "Installation log saved to: /var/log/pi-monitor-install.log"
echo "Happy monitoring!"
