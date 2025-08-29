#!/bin/bash

echo "=========================================="
echo "Pi Monitor UI Enhancements & Bug Fixes"
echo "=========================================="

# Update Flask app with logs page and fix stress test installation
sudo -u pi-monitor tee /opt/pi-monitor/app.py > /dev/null << 'EOF'
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
            
            return {
                'temperature': temp,
                'clock_speed': clock,
                'throttled': throttled,
                'voltage': voltage,
                'elapsed_time': elapsed
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
        # Update package list
        result1 = subprocess.run(['sudo', 'apt', 'update'], capture_output=True, text=True, timeout=120)
        if result1.returncode != 0:
            monitor.log_message(f"apt update failed: {result1.stderr}")
            return False
            
        # Install stress
        result2 = subprocess.run(['sudo', 'apt', 'install', '-y', 'stress'], capture_output=True, text=True, timeout=300)
        if result2.returncode != 0:
            monitor.log_message(f"stress installation failed: {result2.stderr}")
            return False
            
        monitor.log_message("Stress package installed successfully")
        return True
    except subprocess.TimeoutExpired:
        monitor.log_message("Installation timeout")
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
        # Sort by timestamp descending
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
        
        # Read application logs
        if os.path.exists(monitor.log_file):
            with open(monitor.log_file, 'r') as f:
                logs_data['app_logs'] = f.readlines()[-100:]  # Last 100 lines
        
        # Get system logs for pi-monitor service
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
        
        # Validate ranges
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
        monitor.log_message(f"Snapshot saved: {filename}")
        return jsonify({'success': True, 'filename': filename})
    except Exception as e:
        monitor.log_message(f"Failed to save snapshot: {e}")
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    monitor.log_message("Pi Monitor started")
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Update base template to include logs navigation
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
            <h1 class="nav-title">Pi Monitor</h1>
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

# Create logs page template
sudo -u pi-monitor tee /opt/pi-monitor/templates/logs.html > /dev/null << 'EOF'
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

# Update CSS with responsive text areas and logs styling
sudo -u pi-monitor tee -a /opt/pi-monitor/static/style.css > /dev/null << 'EOF'

/* Responsive text area scaling */
.form-group textarea {
    width: 100%;
    max-width: 800px;
    min-height: 60px;
    max-height: 200px;
    resize: vertical;
}

@media (min-width: 1200px) {
    .form-group textarea {
        max-width: 600px;
    }
}

@media (max-width: 768px) {
    .form-group textarea {
        max-width: 100%;
        min-height: 50px;
        max-height: 150px;
    }
}

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

.log-line.error {
    color: var(--danger);
}

.log-line.warning {
    color: var(--warning);
}

.log-line.info {
    color: var(--accent-primary);
}

.loading {
    text-align: center;
    color: var(--text-muted);
    font-style: italic;
}

/* Mobile responsive logs */
@media (max-width: 768px) {
    .logs-header {
        flex-direction: column;
        gap: 0.5rem;
        align-items: stretch;
    }
    
    .path-list {
        gap: 0.75rem;
    }
    
    .path-item {
        flex-direction: column;
        gap: 0.25rem;
    }
    
    .log-content {
        font-size: 0.75rem;
        max-height: 300px;
    }
}

/* Scrollbar styling for logs */
.log-content::-webkit-scrollbar {
    width: 8px;
}

.log-content::-webkit-scrollbar-track {
    background: var(--bg-tertiary);
    border-radius: 4px;
}

.log-content::-webkit-scrollbar-thumb {
    background: var(--border);
    border-radius: 4px;
}

.log-content::-webkit-scrollbar-thumb:hover {
    background: var(--text-muted);
}
EOF

# Update JavaScript to handle logs functionality
sudo -u pi-monitor tee -a /opt/pi-monitor/static/app.js > /dev/null << 'EOF'

// Logs page functionality
if (window.location.pathname === '/logs') {
    document.addEventListener('DOMContentLoaded', () => {
        const logsPage = new LogsPage();
    });
}

class LogsPage {
    constructor() {
        this.init();
    }

    init() {
        this.bindEvents();
        this.loadLogs();
        // Auto-refresh every 30 seconds
        setInterval(() => this.loadLogs(), 30000);
    }

    bindEvents() {
        document.getElementById('refresh-logs')?.addEventListener('click', () => this.loadLogs());
    }

    async loadLogs() {
        try {
            const response = await fetch('/api/logs');
            const data = await response.json();

            if (data.error) {
                this.showError('Failed to load logs: ' + data.error);
                return;
            }

            // Update log paths
            document.getElementById('app-log-path').textContent = data.app_log_path;

            // Update application logs
            const appLogsDiv = document.getElementById('app-logs');
            if (data.app_logs && data.app_logs.length > 0) {
                appLogsDiv.innerHTML = data.app_logs
                    .map(line => `<div class="log-line">${this.escapeHtml(line.trim())}</div>`)
                    .join('');
            } else {
                appLogsDiv.innerHTML = '<div class="loading">No application logs found</div>';
            }

            // Update system logs
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

            // Scroll to bottom of logs
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
        document.getElementById('app-logs').innerHTML = `<div class="loading error">${message}</div>`;
        document.getElementById('system-logs').innerHTML = `<div class="loading error">${message}</div>`;
    }
}
EOF

# Fix sudo permissions for stress installation
sudo tee -a /etc/sudoers.d/pi-monitor > /dev/null << 'EOF'
# Additional permissions for stress package installation
pi-monitor ALL=(ALL) NOPASSWD: /usr/bin/apt update
pi-monitor ALL=(ALL) NOPASSWD: /usr/bin/apt install -y stress
pi-monitor ALL=(ALL) NOPASSWD: /usr/bin/which stress
EOF

# Restart the service to apply all changes
sudo systemctl restart pi-monitor.service
sleep 3

echo "✓ Added responsive text area scaling with max-width constraints"
echo "✓ Created logs page with application and system log viewing"
echo "✓ Added log file path information for SSH access"
echo "✓ Fixed stress test installation with proper sudo permissions"
echo "✓ Enhanced application logging throughout the system"
echo ""
echo "New Features:"
echo "  • /logs page shows real-time application and system logs"
echo "  • Log file paths displayed for SSH console access" 
echo "  • Text areas scale responsively but won't break layout"
echo "  • Stress test installation should now work properly"
echo "  • Auto-refreshing logs every 30 seconds"
echo ""
echo "Log Locations:"
echo "  • Application: /home/pi-monitor/app.log"
echo "  • Service: journalctl -u pi-monitor.service"
echo "  • System: /var/log/syslog"
