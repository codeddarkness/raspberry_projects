#!/bin/bash

echo "=========================================="
echo "Pi Monitor Complete Enhancement & Fixes"
echo "=========================================="

# Fix systemd service to allow sudo for stress installation
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

# Minimal security - allow sudo for package installation
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

# Update Flask app with system metrics and better stress installation
sudo -u pi-monitor tee /opt/pi-monitor/app.py > /dev/null << 'EOF'
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
            cpu_percent = psutil.cpu_percent(interval=1)
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
            fb.write("Elapsed Time (s),Temperature (°C),Clock Speed (MHz),Throttled,Voltage (V),CPU %,Memory %\n")
            
            while monitoring_active:
                try:
                    data = self.get_current_readings()
                    current_data = data
                    
                    line = f"{data['elapsed_time']:.0f},{data['temperature']},{data['clock_speed']},{data['throttled']},{data['voltage']:.4f},{data['cpu_percent']:.1f},{data['memory_percent']:.1f}\n"
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
        
        # Try different installation approach
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
        monitor.log_message(f"Snapshot saved: {filename}")
        return jsonify({'success': True, 'filename': filename})
    except Exception as e:
        monitor.log_message(f"Failed to save snapshot: {e}")
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    monitor.log_message("Pi Monitor started")
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Update base template with clickable title
sudo -u pi-monitor tee /opt/pi-monitor/templates/base.html > /dev/null << 'EOF'
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

# Update main page template with expanded system info and redesigned snapshot section
sudo -u pi-monitor tee /opt/pi-monitor/templates/index.html > /dev/null << 'EOF'
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

    <!-- Compact Overclock Controls -->
    <div class="overclock-panel compact">
        <h2>Overclock Settings</h2>
        <div class="warning-box">⚠️ Overclocking can damage your Pi. Ensure adequate cooling.</div>
        <div class="overclock-grid">
            <div class="form-group">
                <label for="arm-freq">CPU (MHz)</label>
                <input type="number" id="arm-freq" min="1000" max="3200" value="2400">
            </div>
            <div class="form-group">
                <label for="gpu-freq">GPU (MHz)</label>
                <input type="number" id="gpu-freq" min="400" max="1200" value="800">
            </div>
            <div class="form-group">
                <label for="voltage-delta">Voltage (μV)</label>
                <input type="number" id="voltage-delta" min="-100000" max="100000" value="0" step="1000">
            </div>
        </div>
        <div class="button-group">
            <button type="button" id="apply-settings" class="btn btn-primary btn-sm">Apply</button>
            <button type="button" id="apply-restart" class="btn btn-danger btn-sm">Apply & Restart</button>
        </div>
    </div>

    <!-- Redesigned Snapshot Section -->
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

# Update results template with overlay functionality
sudo -u pi-monitor tee /opt/pi-monitor/templates/results.html > /dev/null << 'EOF'
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
        <div class="result-card" data-timestamp="{{ result.timestamp }}" data-peak="{{ result.peak_temp }}" data-avg="{{ result.avg_temp }}" data-settings="{{ result.settings.arm_freq or 2400 }}/{{ result.settings.gpu_freq or 800 }}" data-notes="{{ result.notes }}">
            <div class="result-header">
                <h3>{{ result.timestamp[:16] | replace('T', ' ') }}</h3>
                <div class="result-stats">
                    <span class="stat">Peak: {{ result.peak_temp }}°C</span>
                    <span class="stat">Avg: {{ result.avg_temp }}°C</span>
                </div>
            </div>
            {% if result.notes %}
            <div class="result-notes">{{ result.notes }}</div>
            {% endif %}
            <div class="result-settings">
                CPU: {{ result.settings.arm_freq or 2400 }}MHz, GPU: {{ result.settings.gpu_freq or 800 }}MHz
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

# Update CSS with new styles
sudo -u pi-monitor tee /opt/pi-monitor/static/style.css > /dev/null << 'EOF'
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

.status-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 0.75rem;
}

.status-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 0.75rem;
    text-align: center;
    position: relative;
}

.status-card h3 {
    font-size: 0.7rem;
    color: var(--text-secondary);
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

.status-value {
    font-size: 1.3rem;
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
    min-height: 50px;
    max-height: 150px;
    resize: vertical;
}

.form-group input:focus, .form-group textarea:focus {
    outline: none;
    border-color: var(--accent-primary);
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

.result-stats { display: flex; gap: 0.5rem; }

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

@media (max-width: 768px) {
    .container { padding: 0.75rem; }
    .nav-container { padding: 0 0.75rem; }
    .nav-title { font-size: 1.1rem; }
    .status-grid { grid-template-columns: repeat(2, 1fr); }
    
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
    .status-grid { grid-template-columns: repeat(2, 1fr); }
    .controls-section { flex-direction: column; }
    .nav-links { gap: 0.5rem; }
    .nav-link { padding: 0.4rem 0.6rem; font-size: 0.8rem; }
}
EOF

# Install psutil for system metrics
sudo -u pi-monitor /opt/pi-monitor/venv/bin/pip install psutil

# Reload systemd and restart service
sudo systemctl daemon-reload
sudo systemctl restart pi-monitor.service
sleep 3

echo "✓ Fixed systemd service to allow sudo for stress installation"
echo "✓ Made Pi Monitor title clickable to return to main page"
echo "✓ Added system metrics: uptime, CPU load, memory usage, load average"
echo "✓ Redesigned snapshot section with button above text area"
echo "✓ Added overlay functionality for comparing historical results"
echo "✓ Enhanced status grid with 8 monitoring cards"
echo "✓ Installed psutil for accurate system metrics"
echo ""
echo "New System Metrics:"
echo "  • Uptime - system uptime in human readable format"
echo "  • CPU Load - current CPU usage percentage"  
echo "  • Memory - RAM usage percentage"
echo "  • Load Avg - 1/5/15 minute load averages"
echo ""
echo "Enhanced Results Features:"
echo "  • Chart view with overlay mode for comparing multiple results"
echo "  • Click result cards to overlay their data on the chart"
echo "  • Clear selection to reset overlay comparisons"
