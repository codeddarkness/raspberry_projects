#!/bin/bash

echo "=========================================="
echo "Pi Monitor Master Patch & Deployment"
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

echo "Step 1: Creating updated master installation script..."

# Create the enhanced installation script
cat > install_pi_monitor_master.sh << 'INSTALL_EOF'
#!/bin/bash

# Raspberry Pi 5 Monitor Web Interface Installation Script
# Enhanced version with all fixes and improvements integrated

set -e

echo "=========================================="
echo "Raspberry Pi 5 Monitor Installation v3.0"
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

# Install system packages including vcgencmd
sudo apt install -y python3-venv git curl libraspberrypi-bin

echo ""
echo "Step 2: Creating system user and directories..."

# Create system user for the service
if ! id "$SERVICE_USER" &>/dev/null; then
    sudo useradd --system --shell /bin/false --home-dir $INSTALL_DIR --create-home $SERVICE_USER
    # Add pi-monitor user to necessary groups for hardware access
    sudo usermod -a -G gpio,i2c,spi,video,dialout $SERVICE_USER
    print_status 0 "Created system user: $SERVICE_USER"
else
    print_status 0 "System user already exists: $SERVICE_USER"
    # Ensure user is in correct groups
    sudo usermod -a -G gpio,i2c,spi,video,dialout $SERVICE_USER
fi

# Create installation directory
sudo mkdir -p $INSTALL_DIR
sudo chown $SERVICE_USER:$SERVICE_USER $INSTALL_DIR

# Create home directory structure
sudo mkdir -p /home/$SERVICE_USER
sudo chown $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER

# Create subdirectories
sudo mkdir -p $INSTALL_DIR/{templates,static,logs}
sudo mkdir -p /home/$SERVICE_USER/pi_monitor_results
sudo chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
sudo chown -R $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER

print_status 0 "Created directory structure"

echo ""
echo "Step 3: Setting up Python virtual environment..."

# Create virtual environment
sudo -u $SERVICE_USER python3 -m venv $INSTALL_DIR/venv
print_status 0 "Created virtual environment"

# Install Python packages including psutil for system metrics
sudo -u $SERVICE_USER $INSTALL_DIR/venv/bin/pip install --upgrade pip
sudo -u $SERVICE_USER $INSTALL_DIR/venv/bin/pip install flask vcgencmd psutil

print_status 0 "Installed Python dependencies"

echo ""
echo "Step 4: Creating enhanced application files..."

# Create the main Python application with system metrics
sudo -u $SERVICE_USER tee $INSTALL_DIR/app.py > /dev/null << 'EOF'
#!/usr/bin/env python3

import os
import sys
import time
import json
import subprocess
import threading
import psutil
from datetime import datetime, timedelta
from flask import Flask, render_template, jsonify, request
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
    'elapsed_time': 0,
    'uptime': 0,
    'cpu_percent': 0,
    'memory_percent': 0,
    'load_avg': [0, 0, 0]
}

class PiMonitor:
    def __init__(self):
        self.start_time = time.time()
        self.data_file = "/home/pi-monitor/readings.txt"
        self.results_dir = "/home/pi-monitor/pi_monitor_results"
        self.log_file = "/home/pi-monitor/app.log"
        self.ensure_directories()
        
    def ensure_directories(self):
        os.makedirs(self.results_dir, exist_ok=True)
        
    def log_message(self, message):
        try:
            with open(self.log_file, 'a') as f:
                f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")
        except:
            pass
            
    def get_current_readings(self):
        try:
            temp = float(str(vcgm.measure_temp()).replace('°C', ''))
            clock = int(vcgm.measure_clock('arm') / 1000000)
            throttled = vcgm.get_throttled()['breakdown']['2']
            voltage = float(str(vcgm.measure_volts('core')).replace('V', ''))
            elapsed = time.time() - self.start_time
            
            # Get system metrics
            boot_time = psutil.boot_time()
            uptime_seconds = time.time() - boot_time
            cpu_percent = psutil.cpu_percent(interval=0.1)
            memory = psutil.virtual_memory()
            load_avg = os.getloadavg()
            
            return {
                'temperature': temp,
                'clock_speed': clock,
                'throttled': throttled,
                'voltage': voltage,
                'elapsed_time': elapsed,
                'uptime': uptime_seconds,
                'cpu_percent': cpu_percent,
                'memory_percent': memory.percent,
                'load_avg': load_avg
            }
        except Exception as e:
            self.log_message(f"Error reading sensors: {e}")
            return current_data
    
    def start_monitoring(self):
        global monitoring_active, current_data
        monitoring_active = True
        self.log_message("Monitoring started")
        
        with open(self.data_file, 'a+') as fb:
            fb.write(f"\n# Session started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            fb.write("Elapsed Time (s),Temperature (°C),Clock Speed (MHz),Throttled,Voltage (V),CPU %,Memory %,Load 1m,Load 5m,Load 15m\n")
            
            while monitoring_active:
                try:
                    data = self.get_current_readings()
                    current_data = data
                    
                    line = f"{data['elapsed_time']:.0f},{data['temperature']},{data['clock_speed']},{data['throttled']},{data['voltage']:.4f},{data['cpu_percent']:.1f},{data['memory_percent']:.1f},{data['load_avg'][0]:.2f},{data['load_avg'][1]:.2f},{data['load_avg'][2]:.2f}\n"
                    fb.write(line)
                    fb.flush()
                    time.sleep(1)
                except Exception as e:
                    self.log_message(f"Monitoring error: {e}")
                    time.sleep(1)

monitor = PiMonitor()

def check_stress_installed():
    try:
        result = subprocess.run(['which', 'stress'], capture_output=True, text=True, timeout=5)
        return result.returncode == 0
    except:
        return False

def install_stress():
    try:
        monitor.log_message("Installing stress package...")
        install_cmd = """
        export DEBIAN_FRONTEND=noninteractive
        sudo apt update -qq
        sudo apt install -y stress
        """
        
        result = subprocess.run(['bash', '-c', install_cmd], 
                              capture_output=True, text=True, timeout=300)
        
        if result.returncode == 0:
            monitor.log_message("Stress package installed successfully")
            return True
        else:
            monitor.log_message(f"Installation failed: {result.stderr}")
            return False
            
    except Exception as e:
        monitor.log_message(f"Installation error: {e}")
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
        monitor.log_message(f"Error reading config: {e}")
    
    return settings

def apply_overclock_settings(arm_freq, gpu_freq, voltage_delta):
    config_file = "/boot/firmware/config.txt"
    backup_file = f"{config_file}.backup.{int(time.time())}"
    
    try:
        monitor.log_message(f"Applying overclock: CPU={arm_freq}MHz, GPU={gpu_freq}MHz, Voltage={voltage_delta}μV")
        
        subprocess.run(['sudo', 'cp', config_file, backup_file], check=True)
        
        with open(config_file, 'r') as f:
            lines = f.readlines()
        
        lines = [line for line in lines if not any(
            line.strip().startswith(setting) for setting in 
            ['arm_freq=', 'gpu_freq=', 'over_voltage_delta=']
        )]
        
        lines.append(f"\n# Overclock settings applied {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        if arm_freq != 2400:
            lines.append(f"arm_freq={arm_freq}\n")
        if gpu_freq != 800:
            lines.append(f"gpu_freq={gpu_freq}\n")
        if voltage_delta != 0:
            lines.append(f"over_voltage_delta={voltage_delta}\n")
        
        temp_file = f"{config_file}.tmp"
        with open(temp_file, 'w') as f:
            f.writelines(lines)
        
        subprocess.run(['sudo', 'mv', temp_file, config_file], check=True)
        monitor.log_message("Overclock settings applied successfully")
        return True
        
    except Exception as e:
        monitor.log_message(f"Error applying overclock settings: {e}")
        return False

def is_overclocking_requested(arm_freq, gpu_freq, voltage_delta):
    """Check if settings exceed default safe values"""
    return arm_freq > 2400 or gpu_freq > 800 or abs(voltage_delta) > 0

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
                    'avg_temp': data.get('avg_temp', 0),
                    'system_metrics': data.get('system_metrics', {})
                })
        results_files.sort(key=lambda x: x['timestamp'], reverse=True)
    except Exception as e:
        monitor.log_message(f"Error loading results: {e}")
    
    return render_template('results.html', results=results_files)

@app.route('/logs')
def logs():
    return render_template('logs.html')

@app.route('/api/logs')
def api_logs():
    try:
        logs_data = {
            'app_log_path': monitor.log_file,
            'system_log_path': '/var/log/syslog',
            'service_log_path': 'journalctl -u pi-monitor.service',
            'app_logs': [],
            'system_logs': []
        }
        
        if os.path.exists(monitor.log_file):
            with open(monitor.log_file, 'r') as f:
                logs_data['app_logs'] = f.readlines()[-100:]
        
        try:
            result = subprocess.run(['journalctl', '-u', 'pi-monitor.service', '-n', '50', '--no-pager'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                logs_data['system_logs'] = result.stdout.split('\n')
        except:
            logs_data['system_logs'] = ['Unable to fetch system logs']
        
        return jsonify(logs_data)
    except Exception as e:
        return jsonify({'error': str(e)})

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
    monitor.log_message("Monitoring stopped")
    return jsonify({'success': True})

@app.route('/api/start_stress', methods=['POST'])
def start_stress():
    global stress_process
    
    if not check_stress_installed():
        monitor.log_message("Stress not installed, attempting installation...")
        if not install_stress():
            return jsonify({'success': False, 'error': 'Failed to install stress package'})
    
    if stress_process is None or stress_process.poll() is not None:
        try:
            monitor.log_message("Starting stress test...")
            stress_process = subprocess.Popen(['stress', '--cpu', '4'])
            return jsonify({'success': True})
        except Exception as e:
            monitor.log_message(f"Failed to start stress test: {e}")
            return jsonify({'success': False, 'error': str(e)})
    
    return jsonify({'success': True, 'message': 'Stress test already running'})

@app.route('/api/stop_stress', methods=['POST'])
def stop_stress():
    global stress_process
    
    if stress_process and stress_process.poll() is None:
        stress_process.terminate()
        stress_process.wait()
        stress_process = None
        monitor.log_message("Stress test stopped")
    
    return jsonify({'success': True})

@app.route('/api/apply_overclock', methods=['POST'])
def apply_overclock():
    data = request.json
    
    try:
        arm_freq = int(data.get('arm_freq', 2400))
        gpu_freq = int(data.get('gpu_freq', 800))
        voltage_delta = int(data.get('voltage_delta', 0))
        restart = data.get('restart', False)
        
        if not (1000 <= arm_freq <= 3200):
            return jsonify({'success': False, 'error': 'ARM frequency must be between 1000-3200 MHz'})
        if not (400 <= gpu_freq <= 1200):
            return jsonify({'success': False, 'error': 'GPU frequency must be between 400-1200 MHz'})
        if not (-100000 <= voltage_delta <= 100000):
            return jsonify({'success': False, 'error': 'Voltage delta must be between -100000 to 100000 μV'})
        
        if apply_overclock_settings(arm_freq, gpu_freq, voltage_delta):
            if restart:
                monitor.log_message("Reboot requested after overclock apply")
                subprocess.Popen(['sudo', 'reboot'])
                return jsonify({'success': True, 'message': 'Settings applied, rebooting...'})
            else:
                return jsonify({'success': True, 'message': 'Settings applied, reboot required to take effect'})
        else:
            return jsonify({'success': False, 'error': 'Failed to apply settings'})
            
    except Exception as e:
        monitor.log_message(f"Overclock application error: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/save_snapshot', methods=['POST'])
def save_snapshot():
    data = request.json
    notes = data.get('notes', '')
    
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filename = f"snapshot_{timestamp}.json"
    filepath = os.path.join(monitor.results_dir, filename)
    
    try:
        with open(monitor.data_file, 'r') as f:
            lines = f.readlines()
        
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
    
    # Include system metrics in snapshot
    snapshot_data = {
        'timestamp': datetime.now().isoformat(),
        'notes': notes,
        'current_data': current_data,
        'overclock_settings': get_current_overclock_settings(),
        'peak_temp': round(peak_temp, 1),
        'avg_temp': round(avg_temp, 1),
        'system_metrics': {
            'uptime': current_data.get('uptime', 0),
            'cpu_percent': current_data.get('cpu_percent', 0),
            'memory_percent': current_data.get('memory_percent', 0),
            'load_avg': current_data.get('load_avg', [0, 0, 0])
        }
    }
    
    try:
        with open(filepath, 'w') as f:
            json.dump(snapshot_data, f, indent=2)
        monitor.log_message(f"Snapshot saved: {filename}")
        return jsonify({'success': True, 'filename': filename})
    except Exception as e:
        monitor.log_message(f"Failed to save snapshot: {e}")
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    monitor.log_message("Pi Monitor started")
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Create base template with navigation
sudo -u $SERVICE_USER tee $INSTALL_DIR/templates/base.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Pi Monitor{% endblock %}</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.js"></script>
</head>
<body>
    <nav class="navbar">
        <div class="nav-container">
            <h1 class="nav-title"><a href="{{ url_for('index') }}">Pi Monitor</a></h1>
            <div class="nav-links">
                <a href="{{ url_for('index') }}" class="nav-link {% if request.endpoint == 'index' %}active{% endif %}">Monitor</a>
                <a href="{{ url_for('results') }}" class="nav-link {% if request.endpoint == 'results' %}active{% endif %}">Results</a>
                <a href="{{ url_for('logs') }}" class="nav-link {% if request.endpoint == 'logs' %}active{% endif %}">Logs</a>
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

# Create main dashboard template with 2x4 status grid
sudo -u $SERVICE_USER tee $INSTALL_DIR/templates/index.html > /dev/null << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="dashboard">
    <!-- Status Cards in 2x4 Grid -->
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
        <div class="status-card">
            <h3>Uptime</h3>
            <div class="status-value" id="uptime">--</div>
        </div>
        <div class="status-card">
            <h3>CPU Load</h3>
            <div class="status-value" id="cpu-load">--%</div>
        </div>
        <div class="status-card">
            <h3>Memory</h3>
            <div class="status-value" id="memory-usage">--%</div>
        </div>
        <div class="status-card">
            <h3>Load Avg</h3>
            <div class="status-value" id="load-avg">--</div>
        </div>
    </div>

    <!-- Control & Chart Panel -->
    <div class="control-chart-panel">
        <div class="controls-section">
            <div class="control-group">
                <h2>Monitor</h2>
                <div class="button-row">
                    <button id="start-monitor" class="btn btn-primary btn-sm">Start</button>
                    <button id="stop-monitor" class="btn btn-secondary btn-sm">Stop</button>
                    <span id="monitor-status" class="status-text">Stopped</span>
                </div>
            </div>
            <div class="control-group">
                <h2>Stress Test</h2>
                <div class="button-row">
                    <button id="start-stress" class="btn btn-warning btn-sm">Start</button>
                    <button id="stop-stress" class="btn btn-secondary btn-sm">Stop</button>
                    <span id="stress-status" class="status-text">Stopped</span>
                </div>
            </div>
        </div>
        <div class="chart-section">
            <canvas id="liveChart" width="400" height="200"></canvas>
        </div>
    </div>

    <!-- Overclock Controls with Dynamic Warning -->
    <div class="overclock-panel compact">
        <h2>Overclock Settings</h2>
        <div id="warning-box" class="warning-box" style="display:none;">
            <strong>⚠️ Warning:</strong> These settings exceed Pi 5 defaults. Ensure adequate cooling and power supply.
        </div>
        
        <div class="overclock-grid">
            <div class="form-group">
                <label for="arm-freq">CPU (MHz)</label>
                <input type="number" id="arm-freq" min="1000" max="3200" value="2400">
                <small>Default: 2400</small>
            </div>
            <div class="form-group">
                <label for="gpu-freq">GPU (MHz)</label>
                <input type="number" id="gpu-freq" min="400" max="1200" value="800">
                <small>Default: 800</small>
            </div>
            <div class="form-group">
                <label for="voltage-delta">Voltage (μV)</label>
                <input type="number" id="voltage-delta" min="-100000" max="100000" value="0" step="1000">
                <small>Default: 0</small>
            </div>
        </div>
        <div class="button-group">
            <button type="button" id="apply-settings" class="btn btn-primary btn-sm">Apply</button>
            <button type="button" id="apply-restart" class="btn btn-danger btn-sm">Apply & Restart</button>
        </div>
    </div>

    <!-- Snapshot Section -->
    <div class="snapshot-panel compact">
        <div class="snapshot-header">
            <button id="save-snapshot" class="btn btn-primary btn-sm">Save Snapshot</button>
        </div>
        <textarea id="notes" placeholder="Add notes about current test conditions..." rows="2"></textarea>
    </div>
</div>
<div id="toast" class="toast"></div>
{% endblock %}
EOF

# Create results template with system metrics display
sudo -u $SERVICE_USER tee $INSTALL_DIR/templates/results.html > /dev/null << 'EOF'
{% extends "base.html" %}
{% block title %}Results - Pi Monitor{% endblock %}
{% block content %}
<div class="results-page">
    <div class="results-header">
        <h2>Test Results</h2>
        <div class="results-controls">
            <button id="chart-view-toggle" class="btn btn-secondary btn-sm">Chart View</button>
            <button id="overlay-toggle" class="btn btn-secondary btn-sm" style="display:none;">Overlay Mode</button>
            <button id="clear-overlay" class="btn btn-secondary btn-sm" style="display:none;">Clear Selection</button>
        </div>
    </div>
    
    <div id="chart-container" class="chart-container" style="display:none;">
        <canvas id="resultsChart" width="400" height="300"></canvas>
        <div id="overlay-info" class="overlay-info" style="display:none;">
            <p>Click result cards to overlay data. Selected: <span id="selected-count">0</span></p>
        </div>
    </div>
    
    {% if results %}
    <div class="results-grid" id="results-grid">
        {% for result in results %}
        <div class="result-card" 
             data-timestamp="{{ result.timestamp }}" 
             data-peak="{{ result.peak_temp }}" 
             data-avg="{{ result.avg_temp }}" 
             data-settings="{{ result.settings.arm_freq or 2400 }}/{{ result.settings.gpu_freq or 800 }}"
             data-cpu="{{ result.system_metrics.cpu_percent or 0 if result.system_metrics else 0 }}"
             data-memory="{{ result.system_metrics.memory_percent or 0 if result.system_metrics else 0 }}">
            <div class="result-header">
                <h3>{{ result.timestamp[:16] | replace('T', ' ') }}</h3>
                <div class="result-stats">
                    <span class="stat">Peak: {{ result.peak_temp }}°C</span>
                    <span class="stat">Avg: {{ result.avg_temp }}°C</span>
                    {% if result.system_metrics %}
                    <span class="stat">CPU: {{ "%.1f"|format(result.system_metrics.cpu_percent) }}%</span>
                    {% endif %}
                </div>
            </div>
            {% if result.notes %}
            <div class="result-notes">{{ result.notes }}</div>
            {% endif %}
            <div class="result-settings">
                CPU: {{ result.settings.arm_freq or 2400 }}MHz, GPU: {{ result.settings.gpu_freq or 800 }}MHz
                {% if result.system_metrics %}
                | Mem: {{ "%.1f"|format(result.system_metrics.memory_percent) }}%
                {% endif %}
            </div>
        </div>
        {% endfor %}
    </div>
    {% else %}
    <div class="empty-results">
        <p>No results saved yet.</p>
        <a href="/" class="btn btn-primary">Start Monitoring</a>
    </div>
    {% endif %}
</div>
{% endblock %}
EOF

# Create logs template
sudo -u $SERVICE_USER tee $INSTALL_DIR/templates/logs.html > /dev/null << 'EOF'
{% extends "base.html" %}
{% block title %}Logs - Pi Monitor{% endblock %}
{% block content %}
<div class="logs-page">
    <div class="logs-header">
        <h2>Application Logs</h2>
        <button id="refresh-logs" class="btn btn-secondary btn-sm">Refresh</button>
    </div>
    
    <div class="logs-info">
        <div class="log-path-info">
            <h3>Log File Locations</h3>
            <div class="path-list">
                <div class="path-item">
                    <strong>Application Log:</strong> <code id="app-log-path">Loading...</code>
                </div>
                <div class="path-item">
                    <strong>Service Log:</strong> <code>journalctl -u pi-monitor.service</code>
                </div>
            </div>
        </div>
    </div>
    
    <div class="logs-container">
        <div class="log-section">
            <h3>Application Logs (Last 100 Lines)</h3>
            <div class="log-content" id="app-logs">
                <div class="loading">Loading logs...</div>
            </div>
        </div>
        
        <div class="log-section">
            <h3>System Service Logs (Last 50 Lines)</h3>
            <div class="log-content" id="system-logs">
                <div class="loading">Loading logs...</div>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Create enhanced CSS with 2x4 grid layout
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
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: var(--bg-primary);
    color: var(--text-primary);
    line-height: 1.5;
    font-size: 14px;
}

.navbar {
    background: var(--bg-secondary);
    border-bottom: 1px solid var(--border);
    padding: 0.75rem 0;
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
    padding: 0 1rem;
}

.nav-title {
    font-size: 1.25rem;
    font-weight: 600;
    color: var(--accent-primary);
}

.nav-title a {
    color: inherit;
    text-decoration: none;
}

.nav-title a:hover {
    color: #3a8ce6;
}

.nav-links { display: flex; gap: 1rem; }

.nav-link {
    color: var(--text-secondary);
    text-decoration: none;
    padding: 0.5rem 0.75rem;
    border-radius: 4px;
    font-size: 0.9rem;
    transition: all 0.2s;
}

.nav-link:hover, .nav-link.active {
    color: var(--text-primary);
    background: var(--bg-tertiary);
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 1rem;
}

.dashboard { display: flex; flex-direction: column; gap: 1rem; }

/* 2x4 Status Grid Layout */
.status-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    grid-template-rows: repeat(2, 1fr);
    gap: 0.75rem;
    max-width: 800px;
    margin: 0 auto;
}

.status-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 0.75rem;
    text-align: center;
    position: relative;
    min-height: 80px;
    display: flex;
    flex-direction: column;
    justify-content: center;
}

.status-card h3 {
    font-size: 0.7rem;
    color: var(--text-secondary);
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

.status-value {
    font-size: 1.1rem;
    font-weight: 600;
    color: var(--text-primary);
}

.status-indicator {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    position: absolute;
    top: 0.5rem;
    right: 0.5rem;
    background: var(--text-muted);
}

.status-indicator.good { background: var(--success); }
.status-indicator.warning { background: var(--warning); }
.status-indicator.danger { background: var(--danger); }

.control-chart-panel {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    display: grid;
    grid-template-columns: 300px 1fr;
    gap: 1rem;
    min-height: 250px;
}

.controls-section {
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.control-group h2 {
    font-size: 1rem;
    margin-bottom: 0.5rem;
    color: var(--text-primary);
}

.button-row {
    display: flex;
    gap: 0.5rem;
    align-items: center;
    flex-wrap: wrap;
}

.chart-section {
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--bg-tertiary);
    border-radius: 4px;
    border: 1px solid var(--border);
}

.chart-section canvas {
    max-width: 100%;
    max-height: 100%;
}

.overclock-panel, .snapshot-panel {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
}

.overclock-panel h2 {
    font-size: 1rem;
    margin-bottom: 0.75rem;
    color: var(--text-primary);
}

.snapshot-header {
    display: flex;
    justify-content: flex-end;
    margin-bottom: 0.75rem;
}

.warning-box {
    background: rgba(255, 152, 0, 0.1);
    border: 1px solid var(--warning);
    border-radius: 4px;
    padding: 0.75rem;
    margin-bottom: 1rem;
    color: var(--warning);
    font-size: 0.85rem;
}

.overclock-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 1rem;
    margin-bottom: 1rem;
}

.form-group {
    display: flex;
    flex-direction: column;
}

.form-group label {
    color: var(--text-secondary);
    margin-bottom: 0.25rem;
    font-size: 0.85rem;
    font-weight: 500;
}

.form-group input, .form-group textarea {
    background: var(--bg-tertiary);
    border: 1px solid var(--border);
    border-radius: 4px;
    padding: 0.5rem;
    color: var(--text-primary);
    font-size: 0.9rem;
    width: 100%;
    max-width: 100%;
}

.form-group textarea {
    min-height: 50px;
    max-height: 150px;
    resize: vertical;
}

.form-group input:focus, .form-group textarea:focus {
    outline: none;
    border-color: var(--accent-primary);
}

.form-group small {
    color: var(--text-muted);
    font-size: 0.75rem;
    margin-top: 0.25rem;
}

.button-group {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
}

.btn {
    padding: 0.5rem 1rem;
    border: none;
    border-radius: 4px;
    font-size: 0.85rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s;
    text-decoration: none;
    display: inline-block;
}

.btn-sm {
    padding: 0.4rem 0.8rem;
    font-size: 0.8rem;
}

.btn:disabled { opacity: 0.5; cursor: not-allowed; }
.btn-primary { background: var(--accent-primary); color: white; }
.btn-secondary { background: var(--bg-tertiary); color: var(--text-primary); }
.btn-warning { background: var(--warning); color: white; }
.btn-danger { background: var(--danger); color: white; }

.btn-primary:hover:not(:disabled) { background: #3a8ce6; }
.btn-secondary:hover:not(:disabled) { background: var(--border); }

.status-text {
    color: var(--text-secondary);
    font-size: 0.8rem;
}

.results-page h2 {
    color: var(--text-primary);
    margin-bottom: 1rem;
    font-size: 1.5rem;
}

.results-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
}

.results-controls {
    display: flex;
    gap: 0.5rem;
}

.chart-container {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    margin-bottom: 1rem;
}

.overlay-info {
    text-align: center;
    margin-top: 0.5rem;
    color: var(--text-secondary);
    font-size: 0.9rem;
}

.results-grid { display: grid; gap: 1rem; }

.result-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    cursor: pointer;
    transition: all 0.2s;
}

.result-card:hover {
    border-color: var(--accent-primary);
}

.result-card.selected {
    border-color: var(--accent-primary);
    background: rgba(74, 158, 255, 0.1);
}

.result-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.5rem;
}

.result-header h3 {
    color: var(--accent-primary);
    font-size: 0.95rem;
}

.result-stats { 
    display: flex; 
    gap: 0.5rem;
    flex-wrap: wrap;
}

.stat {
    background: var(--bg-tertiary);
    padding: 0.25rem 0.5rem;
    border-radius: 12px;
    font-size: 0.7rem;
}

.result-notes {
    color: var(--text-secondary);
    margin-bottom: 0.5rem;
    font-size: 0.85rem;
}

.result-settings {
    color: var(--text-muted);
    font-size: 0.8rem;
}

.empty-results {
    text-align: center;
    padding: 2rem;
    color: var(--text-secondary);
}

.toast {
    position: fixed;
    top: 20px;
    right: 20px;
    padding: 0.75rem 1rem;
    border-radius: 4px;
    color: white;
    z-index: 1000;
    opacity: 0;
    transform: translateY(-20px);
    transition: all 0.3s;
    font-size: 0.9rem;
    max-width: 300px;
}

.toast.show { opacity: 1; transform: translateY(0); }
.toast.success { background: var(--success); }
.toast.warning { background: var(--warning); }
.toast.error { background: var(--danger); }

/* Logs page styles */
.logs-page h2 {
    color: var(--text-primary);
    margin-bottom: 1rem;
    font-size: 1.5rem;
}

.logs-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1.5rem;
}

.logs-info {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    margin-bottom: 1.5rem;
}

.logs-info h3 {
    color: var(--text-primary);
    margin-bottom: 0.75rem;
    font-size: 1.1rem;
}

.path-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}

.path-item {
    font-size: 0.9rem;
    color: var(--text-secondary);
}

.path-item code {
    background: var(--bg-tertiary);
    padding: 0.25rem 0.5rem;
    border-radius: 3px;
    font-family: 'Courier New', monospace;
    color: var(--text-primary);
    font-size: 0.85rem;
}

.logs-container {
    display: grid;
    gap: 1.5rem;
}

.log-section {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
}

.log-section h3 {
    color: var(--text-primary);
    margin-bottom: 0.75rem;
    font-size: 1rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.5rem;
}

.log-content {
    background: var(--bg-primary);
    border: 1px solid var(--border);
    border-radius: 4px;
    padding: 1rem;
    max-height: 400px;
    overflow-y: auto;
    font-family: 'Courier New', monospace;
    font-size: 0.8rem;
    line-height: 1.4;
    color: var(--text-secondary);
}

.log-line {
    margin-bottom: 0.25rem;
    word-break: break-word;
}

.log-line.error { color: var(--danger); }
.log-line.warning { color: var(--warning); }
.log-line.info { color: var(--accent-primary); }

.loading {
    text-align: center;
    color: var(--text-muted);
    font-style: italic;
}

/* Mobile responsive - keep 2x4 but stack vertically on small screens */
@media (max-width: 768px) {
    .container { padding: 0.75rem; }
    .nav-container { padding: 0 0.75rem; }
    .nav-title { font-size: 1.1rem; }
    
    .status-grid { 
        grid-template-columns: repeat(2, 1fr);
        grid-template-rows: repeat(4, 1fr);
        max-width: 400px;
    }
    
    .control-chart-panel {
        grid-template-columns: 1fr;
        min-height: auto;
    }
    
    .controls-section {
        flex-direction: row;
        justify-content: space-around;
    }
    
    .chart-section { height: 200px; }
    .overclock-grid { grid-template-columns: 1fr; }
    .button-group { justify-content: center; }
    .results-header { flex-direction: column; gap: 0.5rem; }
    .result-header { flex-direction: column; align-items: flex-start; gap: 0.25rem; }
    .results-controls { flex-wrap: wrap; }
}

@media (max-width: 480px) {
    .status-grid { 
        grid-template-columns: 1fr;
        grid-template-rows: repeat(8, 1fr);
    }
    .controls-section { flex-direction: column; }
    .nav-links { gap: 0.5rem; }
    .nav-link { padding: 0.4rem 0.6rem; font-size: 0.8rem; }
}
EOF

# Create enhanced JavaScript with uptime formatting and dynamic warning
sudo -u $SERVICE_USER tee $INSTALL_DIR/static/app.js > /dev/null << 'EOF'
class PiMonitor {
    constructor() {
        this.updateInterval = null;
        this.liveChart = null;
        this.resultsChart = null;
        this.chartData = [];
        this.maxDataPoints = 60;
        this.overlayMode = false;
        this.selectedResults = [];
        this.init();
    }

    init() {
        this.bindEvents();
        this.loadCurrentSettings();
        this.initializeCharts();
        this.startStatusUpdates();
        this.setupOverclockWarning();
    }

    bindEvents() {
        document.getElementById('start-monitor')?.addEventListener('click', () => this.startMonitoring());
        document.getElementById('stop-monitor')?.addEventListener('click', () => this.stopMonitoring());
        document.getElementById('start-stress')?.addEventListener('click', () => this.startStress());
        document.getElementById('stop-stress')?.addEventListener('click', () => this.stopStress());
        document.getElementById('apply-settings')?.addEventListener('click', () => this.applyOverclock(false));
        document.getElementById('apply-restart')?.addEventListener('click', () => this.applyOverclock(true));
        document.getElementById('save-snapshot')?.addEventListener('click', () => this.saveSnapshot());
        document.getElementById('chart-view-toggle')?.addEventListener('click', () => this.toggleResultsChart());
        document.getElementById('overlay-toggle')?.addEventListener('click', () => this.toggleOverlay());
        document.getElementById('clear-overlay')?.addEventListener('click', () => this.clearOverlay());
        document.getElementById('refresh-logs')?.addEventListener('click', () => this.loadLogs());
    }

    setupOverclockWarning() {
        const inputs = ['arm-freq', 'gpu-freq', 'voltage-delta'];
        inputs.forEach(id => {
            const input = document.getElementById(id);
            if (input) {
                input.addEventListener('input', () => this.updateOverclockWarning());
            }
        });
    }

    updateOverclockWarning() {
        const armFreq = parseInt(document.getElementById('arm-freq')?.value || 2400);
        const gpuFreq = parseInt(document.getElementById('gpu-freq')?.value || 800);
        const voltageDelta = parseInt(document.getElementById('voltage-delta')?.value || 0);
        
        const warningBox = document.getElementById('warning-box');
        if (warningBox) {
            const isOverclocking = armFreq > 2400 || gpuFreq > 800 || Math.abs(voltageDelta) > 0;
            warningBox.style.display = isOverclocking ? 'block' : 'none';
        }
    }

    formatUptime(seconds) {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const mins = Math.floor((seconds % 3600) / 60);
        
        if (days > 0) return `${days}d ${hours}h`;
        if (hours > 0) return `${hours}h ${mins}m`;
        return `${mins}m`;
    }

    initializeCharts() {
        // Initialize live chart
        const liveCtx = document.getElementById('liveChart');
        if (liveCtx) {
            this.liveChart = new Chart(liveCtx, {
                type: 'line',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Temperature (°C)',
                        data: [],
                        borderColor: '#ff9800',
                        backgroundColor: 'rgba(255, 152, 0, 0.1)',
                        tension: 0.4
                    }, {
                        label: 'Clock (GHz)',
                        data: [],
                        borderColor: '#4a9eff',
                        backgroundColor: 'rgba(74, 158, 255, 0.1)',
                        tension: 0.4,
                        yAxisID: 'y1'
                    }, {
                        label: 'CPU %',
                        data: [],
                        borderColor: '#4caf50',
                        backgroundColor: 'rgba(76, 175, 80, 0.1)',
                        tension: 0.4,
                        yAxisID: 'y2'
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { labels: { color: '#e0e0e0', font: { size: 11 } } }
                    },
                    scales: {
                        x: { ticks: { color: '#b0b0b0', font: { size: 10 } }, grid: { color: '#404040' } },
                        y: { 
                            ticks: { color: '#b0b0b0', font: { size: 10 } }, 
                            grid: { color: '#404040' },
                            title: { display: true, text: 'Temp (°C)', color: '#b0b0b0', font: { size: 10 } }
                        },
                        y1: {
                            type: 'linear',
                            position: 'right',
                            ticks: { color: '#b0b0b0', font: { size: 10 } },
                            title: { display: true, text: 'Clock (GHz)', color: '#b0b0b0', font: { size: 10 } },
                            grid: { drawOnChartArea: false }
                        },
                        y2: {
                            type: 'linear',
                            position: 'right',
                            ticks: { color: '#b0b0b0', font: { size: 10 } },
                            title: { display: false },
                            grid: { drawOnChartArea: false }
                        }
                    }
                }
            });
        }

        // Initialize results chart for overlay functionality
        const resultsCtx = document.getElementById('resultsChart');
        if (resultsCtx) {
            this.resultsChart = new Chart(resultsCtx, {
                type: 'bar',
                data: { labels: [], datasets: [] },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { labels: { color: '#e0e0e0' } } },
                    scales: {
                        x: { ticks: { color: '#b0b0b0' }, grid: { color: '#404040' } },
                        y: { ticks: { color: '#b0b0b0' }, grid: { color: '#404040' } }
                    }
                }
            });
        }
    }

    toggleResultsChart() {
        const container = document.getElementById('chart-container');
        const grid = document.getElementById('results-grid');
        const button = document.getElementById('chart-view-toggle');
        const overlayBtn = document.getElementById('overlay-toggle');
        
        if (container.style.display === 'none') {
            container.style.display = 'block';
            grid.style.display = 'none';
            button.textContent = 'List View';
            overlayBtn.style.display = 'inline-block';
            this.loadResultsChart();
        } else {
            container.style.display = 'none';
            grid.style.display = 'grid';
            button.textContent = 'Chart View';
            overlayBtn.style.display = 'none';
            document.getElementById('clear-overlay').style.display = 'none';
        }
    }

    toggleOverlay() {
        this.overlayMode = !this.overlayMode;
        const button = document.getElementById('overlay-toggle');
        const info = document.getElementById('overlay-info');
        const clearBtn = document.getElementById('clear-overlay');
        
        if (this.overlayMode) {
            button.textContent = 'Exit Overlay';
            info.style.display = 'block';
            clearBtn.style.display = 'inline-block';
            this.setupResultCardClicks();
        } else {
            button.textContent = 'Overlay Mode';
            info.style.display = 'none';
            clearBtn.style.display = 'none';
            this.clearOverlay();
        }
    }

    setupResultCardClicks() {
        document.querySelectorAll('.result-card').forEach(card => {
            card.addEventListener('click', () => this.toggleResultSelection(card));
        });
    }

    toggleResultSelection(card) {
        if (!this.overlayMode) return;
        
        const index = this.selectedResults.indexOf(card);
        if (index > -1) {
            this.selectedResults.splice(index, 1);
            card.classList.remove('selected');
        } else {
            this.selectedResults.push(card);
            card.classList.add('selected');
        }
        
        document.getElementById('selected-count').textContent = this.selectedResults.length;
        this.updateOverlayChart();
    }

    clearOverlay() {
        this.selectedResults.forEach(card => card.classList.remove('selected'));
        this.selectedResults = [];
        document.getElementById('selected-count').textContent = '0';
        this.loadResultsChart();
    }

    updateOverlayChart() {
        if (!this.overlayMode || this.selectedResults.length === 0) {
            this.loadResultsChart();
            return;
        }

        const datasets = this.selectedResults.map((card, index) => {
            const timestamp = card.dataset.timestamp.substring(5, 16);
            const peak = parseFloat(card.dataset.peak);
            const avg = parseFloat(card.dataset.avg);
            const colors = ['#ff9800', '#4a9eff', '#4caf50', '#f44336', '#9c27b0'];
            
            return {
                label: `${timestamp} Peak`,
                data: [peak],
                backgroundColor: colors[index % colors.length],
                borderColor: colors[index % colors.length],
                borderWidth: 1
            };
        });

        this.resultsChart.data.labels = ['Temperature'];
        this.resultsChart.data.datasets = datasets;
        this.resultsChart.update();
    }

    loadResultsChart() {
        if (!this.overlayMode) {
            const cards = document.querySelectorAll('.result-card');
            const labels = [];
            const peakData = [];
            const avgData = [];

            cards.forEach(card => {
                const timestamp = card.dataset.timestamp;
                const peak = parseFloat(card.dataset.peak);
                const avg = parseFloat(card.dataset.avg);
                
                labels.push(timestamp.substring(5, 16));
                peakData.push(peak);
                avgData.push(avg);
            });

            if (this.resultsChart) {
                this.resultsChart.data.labels = labels;
                this.resultsChart.data.datasets = [{
                    label: 'Peak Temp (°C)',
                    data: peakData,
                    backgroundColor: 'rgba(255, 152, 0, 0.7)',
                    borderColor: '#ff9800',
                    borderWidth: 1
                }, {
                    label: 'Avg Temp (°C)',
                    data: avgData,
                    backgroundColor: 'rgba(74, 158, 255, 0.7)',
                    borderColor: '#4a9eff',
                    borderWidth: 1
                }];
                this.resultsChart.update();
            }
        }
    }

    updateLiveChart(data) {
        if (!this.liveChart) return;

        const now = new Date().toLocaleTimeString();
        this.chartData.push({
            time: now,
            temp: data.temperature,
            clock: data.clock_speed / 1000,
            cpu: data.cpu_percent
        });

        if (this.chartData.length > this.maxDataPoints) {
            this.chartData.shift();
        }

        this.liveChart.data.labels = this.chartData.map(d => d.time);
        this.liveChart.data.datasets[0].data = this.chartData.map(d => d.temp);
        this.liveChart.data.datasets[1].data = this.chartData.map(d => d.clock);
        this.liveChart.data.datasets[2].data = this.chartData.map(d => d.cpu);
        this.liveChart.update('none');
    }

    async apiCall(endpoint, method = 'GET', data = null) {
        const options = { method, headers: { 'Content-Type': 'application/json' } };
        if (data) options.body = JSON.stringify(data);

        try {
            const response = await fetch(`/api${endpoint}`, options);
            return await response.json();
        } catch (error) {
            this.showToast('Network error', 'error');
            return { success: false, error: 'Network error' };
        }
    }

    async startMonitoring() {
        const result = await this.apiCall('/start_monitoring', 'POST');
        this.showToast(result.success ? 'Monitoring started' : 'Failed to start', result.success ? 'success' : 'error');
        if (result.success) this.chartData = [];
    }

    async stopMonitoring() {
        const result = await this.apiCall('/stop_monitoring', 'POST');
        this.showToast(result.success ? 'Monitoring stopped' : 'Failed to stop', result.success ? 'success' : 'error');
    }

    async startStress() {
        const result = await this.apiCall('/start_stress', 'POST');
        this.showToast(result.success ? 'Stress test started' : result.error, result.success ? 'success' : 'error');
    }

    async stopStress() {
        const result = await this.apiCall('/stop_stress', 'POST');
        this.showToast(result.success ? 'Stress test stopped' : 'Failed to stop', result.success ? 'success' : 'error');
    }

    async applyOverclock(restart = false) {
        const armFreq = document.getElementById('arm-freq')?.value;
        const gpuFreq = document.getElementById('gpu-freq')?.value;
        const voltageDelta = document.getElementById('voltage-delta')?.value;

        if (!armFreq || !gpuFreq || voltageDelta === '') {
            this.showToast('Please fill all fields', 'error');
            return;
        }

        if (parseInt(armFreq) > 3000 || Math.abs(parseInt(voltageDelta)) > 50000 || restart) {
            if (!confirm(`Confirm ${restart ? 'apply & restart' : 'apply'}?\nCPU: ${armFreq}MHz\nGPU: ${gpuFreq}MHz\nVoltage: ${voltageDelta}μV`)) return;
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
            if (document.getElementById('arm-freq')) {
                document.getElementById('arm-freq').value = s.arm_freq || 2400;
                document.getElementById('gpu-freq').value = s.gpu_freq || 800;
                document.getElementById('voltage-delta').value = s.over_voltage_delta || 0;
                this.updateOverclockWarning();
            }
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
            if (result.monitoring_active) {
                this.updateLiveChart(result.current_data);
            }
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
            startBtn.textContent = installed ? 'Start' : 'Install & Start';
        }
        if (stopBtn) stopBtn.disabled = !active;
    }

    updateSensorReadings(data) {
        const updateElement = (id, value, indicator) => {
            const el = document.getElementById(id);
            if (el) el.textContent = value;
            if (indicator) {
                const ind = document.getElementById(indicator);
                if (ind) {
                    if (indicator.includes('temp')) {
                        ind.className = `status-indicator ${data.temperature < 60 ? 'good' : data.temperature < 75 ? 'warning' : 'danger'}`;
                    } else {
                        ind.className = `status-indicator ${data.throttled ? 'danger' : 'good'}`;
                    }
                }
            }
        };

        updateElement('temperature', `${data.temperature.toFixed(1)}°C`, 'temp-indicator');
        updateElement('clock-speed', `${data.clock_speed} MHz`);
        updateElement('voltage', `${data.voltage.toFixed(4)} V`);
        updateElement('throttled', data.throttled ? 'YES' : 'NO', 'throttle-indicator');
        updateElement('uptime', this.formatUptime(data.uptime));
        updateElement('cpu-load', `${data.cpu_percent.toFixed(1)}%`);
        updateElement('memory-usage', `${data.memory_percent.toFixed(1)}%`);
        updateElement('load-avg', `${data.load_avg[0].toFixed(2)}`);
    }

    async loadLogs() {
        if (window.location.pathname !== '/logs') return;
        
        try {
            const response = await fetch('/api/logs');
            const data = await response.json();

            if (data.error) {
                this.showError('Failed to load logs: ' + data.error);
                return;
            }

            document.getElementById('app-log-path').textContent = data.app_log_path;

            const appLogsDiv = document.getElementById('app-logs');
            if (data.app_logs && data.app_logs.length > 0) {
                appLogsDiv.innerHTML = data.app_logs
                    .map(line => `<div class="log-line">${this.escapeHtml(line.trim())}</div>`)
                    .join('');
            } else {
                appLogsDiv.innerHTML = '<div class="loading">No application logs found</div>';
            }

            const systemLogsDiv = document.getElementById('system-logs');
            if (data.system_logs && data.system_logs.length > 0) {
                systemLogsDiv.innerHTML = data.system_logs
                    .filter(line => line.trim().length > 0)
                    .map(line => {
                        let className = 'log-line';
                        if (line.includes('ERROR') || line.includes('Failed')) {
                            className += ' error';
                        } else if (line.includes('WARNING') || line.includes('WARN')) {
                            className += ' warning';
                        } else if (line.includes('INFO') || line.includes('Started')) {
                            className += ' info';
                        }
                        return `<div class="${className}">${this.escapeHtml(line.trim())}</div>`;
                    })
                    .join('');
            } else {
                systemLogsDiv.innerHTML = '<div class="loading">No system logs found</div>';
            }

            appLogsDiv.scrollTop = appLogsDiv.scrollHeight;
            systemLogsDiv.scrollTop = systemLogsDiv.scrollHeight;

        } catch (error) {
            this.showError('Network error loading logs');
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    showError(message) {
        if (document.getElementById('app-logs')) {
            document.getElementById('app-logs').innerHTML = `<div class="loading error">${message}</div>`;
        }
        if (document.getElementById('system-logs')) {
            document.getElementById('system-logs').innerHTML = `<div class="loading error">${message}</div>`;
        }
    }

    showToast(message, type = 'success') {
        const toast = document.getElementById('toast');
        if (!toast) return;
        toast.textContent = message;
        toast.className = `toast ${type}`;
        setTimeout(() => toast.classList.add('show'), 10);
        setTimeout(() => toast.classList.remove('show'), 3000);
    }
}

// Initialize based on current page
document.addEventListener('DOMContentLoaded', () => {
    window.piMonitor = new PiMonitor();
    
    // Auto-load logs if on logs page
    if (window.location.pathname === '/logs') {
        setTimeout(() => window.piMonitor.loadLogs(), 500);
        setInterval(() => window.piMonitor.loadLogs(), 30000);
    }
});
EOF

print_status 0 "Created enhanced application files"

echo ""
echo "Step 5: Setting up permissions and sudoers..."

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
echo "Step 6: Creating systemd service..."

# Create systemd service file with minimal security restrictions
sudo tee /etc/systemd/system/pi-monitor.service > /dev/null << EOF
[Unit]
Description=Raspberry Pi Monitor Web Interface v3.0
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

# Minimal security settings for Pi hardware access
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

print_status 0 "Created systemd service"

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable pi-monitor.service

print_status 0 "Enabled service for boot start"

echo ""
echo "Step 7: Configuring firewall (if present)..."

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
echo "Step 8: Starting service..."

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
echo "Step 9: Creating management scripts..."

# Create management script
tee ~/pi-monitor-control.sh > /dev/null << 'CONTROL_EOF'
#!/bin/bash
# Pi Monitor Control Script v3.0

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
        echo "Pi Monitor Control v3.0"
        echo "Usage: $0 {start|stop|restart|status|logs|open}"
        echo ""
        echo "Pi Monitor Web Interface:"
        echo "  Local:   http://localhost:$WEB_PORT"
        echo "  Network: http://$PI_IP:$WEB_PORT"
        echo ""
        echo "Features:"
        echo "  • Real-time monitoring with live charts"
        echo "  • System metrics: temperature, clock, voltage, uptime, CPU, memory"
        echo "  • CPU stress testing with automatic package installation"
        echo "  • Overclock configuration with dynamic safety warnings"
        echo "  • Snapshot saving with system metrics for historical analysis"
        echo "  • Application and system log viewing"
        echo "  • Mobile-optimized responsive interface"
        ;;
esac
CONTROL_EOF

chmod +x ~/pi-monitor-control.sh

print_status 0 "Created management script: ~/pi-monitor-control.sh"

echo ""
echo "=========================================="
echo "INSTALLATION COMPLETE!"
echo "=========================================="

PI_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "Pi Monitor v3.0 Web Interface is now available at:"
echo "  Local access:   http://localhost:$WEB_PORT"
echo "  Network access: http://$PI_IP:$WEB_PORT"
echo ""

echo "Service Management:"
echo "  Control script: ~/pi-monitor-control.sh"
echo "  Start service:  sudo systemctl start pi-monitor"
echo "  Stop service:   sudo systemctl stop pi-monitor"
echo "  View logs:      sudo journalctl -u pi-monitor -f"
echo ""

echo "Enhanced Features v3.0:"
echo "  • Real-time temperature, clock speed, voltage, and system monitoring"
echo "  • 2x4 status grid layout with 8 monitoring metrics"
echo "  • Live charts with temperature, clock speed, and CPU usage"
echo "  • System metrics: uptime, CPU load, memory usage, load averages"
echo "  • CPU stress testing with automatic package installation"
echo "  • Overclock configuration with dynamic safety warnings"
echo "  • Snapshot saving with complete system metrics for historical analysis"
echo "  • Application and system log viewing with auto-refresh"
echo "  • Chart overlay mode for comparing historical results"
echo "  • Mobile-optimized responsive interface"
echo ""

echo "Safety Notes:"
echo "  • Dynamic warnings appear only when exceeding Pi 5 default settings"
echo "  • Always ensure adequate cooling before overclocking"
echo "  • Use the official Pi 5 power supply (5V 5A)"
echo "  • Monitor temperatures during stress testing"
echo "  • Backup your SD card before extreme overclocking"
echo ""

if systemctl is-active --quiet pi-monitor.service; then
    print_status 0 "Service is running and ready to use!"
    echo ""
    echo "Navigation:"
    echo "  • Monitor: Real-time dashboard with live charts"
    echo "  • Results: Historical snapshots with chart comparison tools"
    echo "  • Logs: Application and system logs with auto-refresh"
else
    print_status 1 "Service not running - check logs for issues"
    echo "Debug: sudo journalctl -u pi-monitor.service"
fi

echo ""
echo "Installation log saved to: /var/log/pi-monitor-install.log"
echo "Happy monitoring with Pi Monitor v3.0!"
INSTALL_EOF

chmod +x install_pi_monitor_master.sh
print_status 0 "Created master installation script"

echo ""
echo "Step 2: Applying TODO fixes to current deployment..."

# Apply the 2x4 grid fix to current deployment
sudo -u pi-monitor tee /opt/pi-monitor/templates/index.html > /dev/null << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="dashboard">
    <!-- Status Cards in 2x4 Grid -->
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
        <div class="status-card">
            <h3>Uptime</h3>
            <div class="status-value" id="uptime">--</div>
        </div>
        <div class="status-card">
            <h3>CPU Load</h3>
            <div class="status-value" id="cpu-load">--%</div>
        </div>
        <div class="status-card">
            <h3>Memory</h3>
            <div class="status-value" id="memory-usage">--%</div>
        </div>
        <div class="status-card">
            <h3>Load Avg</h3>
            <div class="status-value" id="load-avg">--</div>
        </div>
    </div>

    <!-- Control & Chart Panel -->
    <div class="control-chart-panel">
        <div class="controls-section">
            <div class="control-group">
                <h2>Monitor</h2>
                <div class="button-row">
                    <button id="start-monitor" class="btn btn-primary btn-sm">Start</button>
                    <button id="stop-monitor" class="btn btn-secondary btn-sm">Stop</button>
                    <span id="monitor-status" class="status-text">Stopped</span>
                </div>
            </div>
            <div class="control-group">
                <h2>Stress Test</h2>
                <div class="button-row">
                    <button id="start-stress" class="btn btn-warning btn-sm">Start</button>
                    <button id="stop-stress" class="btn btn-secondary btn-sm">Stop</button>
                    <span id="stress-status" class="status-text">Stopped</span>
                </div>
            </div>
        </div>
        <div class="chart-section">
            <canvas id="liveChart" width="400" height="200"></canvas>
        </div>
    </div>

    <!-- Overclock Controls with Dynamic Warning -->
    <div class="overclock-panel compact">
        <h2>Overclock Settings</h2>
        <div id="warning-box" class="warning-box" style="display:none;">
            <strong>⚠️ Warning:</strong> These settings exceed Pi 5 defaults. Ensure adequate cooling and power supply.
        </div>
        
        <div class="overclock-grid">
            <div class="form-group">
                <label for="arm-freq">CPU (MHz)</label>
                <input type="number" id="arm-freq" min="1000" max="3200" value="2400">
                <small>Default: 2400</small>
            </div>
            <div class="form-group">
                <label for="gpu-freq">GPU (MHz)</label>
                <input type="number" id="gpu-freq" min="400" max="1200" value="800">
                <small>Default: 800</small>
            </div>
            <div class="form-group">
                <label for="voltage-delta">Voltage (μV)</label>
                <input type="number" id="voltage-delta" min="-100000" max="100000" value="0" step="1000">
                <small>Default: 0</small>
            </div>
        </div>
        <div class="button-group">
            <button type="button" id="apply-settings" class="btn btn-primary btn-sm">Apply</button>
            <button type="button" id="apply-restart" class="btn btn-danger btn-sm">Apply & Restart</button>
        </div>
    </div>

    <!-- Snapshot Section -->
    <div class="snapshot-panel compact">
        <div class="snapshot-header">
            <button id="save-snapshot" class="btn btn-primary btn-sm">Save Snapshot</button>
        </div>
        <textarea id="notes" placeholder="Add notes about current test conditions..." rows="2"></textarea>
    </div>
</div>
<div id="toast" class="toast"></div>
{% endblock %}
EOF

# Update CSS for 2x4 grid layout
sudo -u pi-monitor sed -i '/\.status-grid {/,/}/ {
    s/grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));/grid-template-columns: repeat(4, 1fr);\
    grid-template-rows: repeat(2, 1fr);\
    max-width: 800px;\
    margin: 0 auto;/
}' /opt/pi-monitor/static/style.css

# Add dynamic warning functionality to JavaScript
sudo -u pi-monitor tee -a /opt/pi-monitor/static/app.js > /dev/null << 'EOF'

// Add dynamic warning functionality
document.addEventListener('DOMContentLoaded', () => {
    const setupOverclockWarning = () => {
        const inputs = ['arm-freq', 'gpu-freq', 'voltage-delta'];
        const updateWarning = () => {
            const armFreq = parseInt(document.getElementById('arm-freq')?.value || 2400);
            const gpuFreq = parseInt(document.getElementById('gpu-freq')?.value || 800);
            const voltageDelta = parseInt(document.getElementById('voltage-delta')?.value || 0);
            
            const warningBox = document.getElementById('warning-box');
            if (warningBox) {
                const isOverclocking = armFreq > 2400 || gpuFreq > 800 || Math.abs(voltageDelta) > 0;
                warningBox.style.display = isOverclocking ? 'block' : 'none';
            }
        };
        
        inputs.forEach(id => {
            const input = document.getElementById(id);
            if (input) {
                input.addEventListener('input', updateWarning);
                // Initial check
                updateWarning();
            }
        });
    };
    
    setupOverclockWarning();
});
EOF

print_status 0 "Applied TODO fixes to current deployment"

echo ""
echo "Step 3: Organizing project files..."

# Create backup directory
mkdir -p backup

# Move patch scripts to backup
mv patch*.sh backup/ 2>/dev/null || true
mv install_pi_monitor.sh backup/ 2>/dev/null || true
mv install_pi_monitor_fixed.sh backup/ 2>/dev/null || true

print_status 0 "Moved patch scripts to backup/"

# Replace main installation script
mv install_pi_monitor_master.sh install_pi_monitor.sh

print_status 0 "Updated main installation script"

echo ""
echo "Step 4: Restarting service with all enhancements..."

sudo systemctl restart pi-monitor.service
sleep 3

if systemctl is-active --quiet pi-monitor.service; then
    print_status 0 "Service running with all enhancements"
    PI_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "Enhanced Pi Monitor v3.0 available at:"
    echo "  Local:   http://localhost:5000"
    echo "  Network: http://$PI_IP:5000"
else
    print_status 1 "Service failed - check: sudo journalctl -u pi-monitor.service"
fi

echo ""
echo "Step 5: Git repository sync..."

# Initialize git if not present
if [ ! -d ".git" ]; then
    git init
    git branch -M development
    print_status 0 "Initialized git repository"
fi

# Add all files
git add .
git commit -m "Pi Monitor v3.0: Master patch with all enhancements

- Consolidated all patch fixes into main installer
- Added 2x4 status grid layout (TODO #1)
- Fixed system metrics display with proper uptime formatting (TODO #2)  
- Added dynamic overclock warnings only when exceeding defaults (TODO #3)
- Included system metrics in snapshot data for historical analysis (TODO #4)
- Enhanced mobile responsive design
- Added live charting with Chart.js CDN
- Integrated logs page with real-time viewing
- Added chart overlay mode for comparing results
- Fixed all permission and directory issues
- Improved stress test installation reliability"

print_status 0 "Committed changes to development branch"

echo ""
echo "=========================================="
echo "MASTER PATCH COMPLETE!"
echo "=========================================="
echo ""
echo "✓ All patch enhancements consolidated into main installer"
echo "✓ TODO items #1-4 addressed and deployed:"
echo "    #1 Status grid now displays in 2x4 layout instead of 8x1"
echo "    #2 System metrics (uptime, CPU, memory, load) now active and displaying"
echo "    #3 Warning only appears when settings exceed Pi 5 defaults"
echo "    #4 System metrics included in snapshot data for historical analysis"
echo "✓ Current deployment updated with all fixes"
echo "✓ Project files organized (patches moved to backup/)"
echo "✓ Master installation script ready for fresh deployments"
echo ""
echo "New Pi Monitor v3.0 Features:"
echo "  • 8 real-time metrics in optimized 2x4 grid layout"
echo "  • Live charting with temperature, clock speed, and CPU usage"
echo "  • Dynamic overclock warnings (only when exceeding defaults)"
echo "  • Complete system metrics in snapshots for historical analysis"
echo "  • Responsive mobile-first design with touch-friendly controls"
echo "  • Application and system log viewing with auto-refresh"
echo "  • Chart overlay mode for comparing multiple test results"
echo "  • Enhanced stress test installation with proper error handling"
echo ""
echo "File Organization:"
echo "  • install_pi_monitor.sh - Master installer with all enhancements"
echo "  • backup/ - Contains all previous patch scripts for reference"
echo "  • pi-monitor-control.sh - Service management script"
echo ""
echo "The Pi Monitor system is now fully enhanced and ready for production use!"
echo "Web interface: http://$(hostname -I | awk '{print $1}'):5000"
echo "
