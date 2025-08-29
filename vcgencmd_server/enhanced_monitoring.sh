#!/bin/bash

echo "=========================================="
echo "Pi Monitor Enhanced Monitoring Update"
echo "=========================================="

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "\033[0;32m✓\033[0m $2"
    else
        echo -e "\033[0;31m✗\033[0m $2"
    fi
}

echo "Enhancement 1: Adding stress test session management..."

# Update Python app with stress test session management and enhanced data tracking
sudo -u pi-monitor tee /opt/pi-monitor/app.py > /dev/null << 'EOF'
#!/usr/bin/env python3

import os
import sys
import time
import json
import subprocess
import threading
import psutil
import signal
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
        self.stress_pid_file = "/home/pi-monitor/stress.pid"
        self.ensure_directories()
        self.check_existing_stress()
        
    def ensure_directories(self):
        os.makedirs(self.results_dir, exist_ok=True)
        
    def check_existing_stress(self):
        """Check for existing stress processes and clean up orphaned PID file"""
        global stress_process
        
        # Check if PID file exists
        if os.path.exists(self.stress_pid_file):
            try:
                with open(self.stress_pid_file, 'r') as f:
                    old_pid = int(f.read().strip())
                
                # Check if process is still running
                if psutil.pid_exists(old_pid):
                    proc = psutil.Process(old_pid)
                    if 'stress' in proc.name():
                        self.log_message(f"Found existing stress process (PID: {old_pid})")
                        stress_process = subprocess.Popen(['echo'], shell=True)  # Dummy process
                        stress_process.pid = old_pid
                        return
                
                # Remove stale PID file
                os.remove(self.stress_pid_file)
                self.log_message("Removed stale stress PID file")
                
            except (ValueError, FileNotFoundError, psutil.NoSuchProcess):
                try:
                    os.remove(self.stress_pid_file)
                except:
                    pass
        
        # Check for any running stress processes by name
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if proc.info['name'] == 'stress' and any('--cpu' in str(arg) for arg in proc.info['cmdline']):
                    self.log_message(f"Found orphaned stress process (PID: {proc.info['pid']}), tracking it")
                    stress_process = subprocess.Popen(['echo'], shell=True)
                    stress_process.pid = proc.info['pid']
                    self.save_stress_pid(proc.info['pid'])
                    break
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        
    def save_stress_pid(self, pid):
        """Save stress process PID for session management"""
        try:
            with open(self.stress_pid_file, 'w') as f:
                f.write(str(pid))
        except Exception as e:
            self.log_message(f"Failed to save stress PID: {e}")
    
    def remove_stress_pid(self):
        """Remove stress PID file when stress test stops"""
        try:
            if os.path.exists(self.stress_pid_file):
                os.remove(self.stress_pid_file)
        except Exception as e:
            self.log_message(f"Failed to remove stress PID file: {e}")
        
    def log_message(self, message):
        try:
            with open(self.log_file, 'a') as f:
                f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")
        except:
            pass
            
    def get_current_readings(self):
        global current_data
        try:
            # Hardware metrics
            temp = float(str(vcgm.measure_temp()).replace('°C', ''))
            clock = int(vcgm.measure_clock('arm') / 1000000)
            throttled = vcgm.get_throttled()['breakdown']['2']
            voltage = float(str(vcgm.measure_volts('core')).replace('V', ''))
            elapsed = time.time() - self.start_time
            
            # System metrics
            boot_time = psutil.boot_time()
            uptime_seconds = time.time() - boot_time
            cpu_percent = psutil.cpu_percent(interval=0.1)
            memory = psutil.virtual_memory()
            load_avg = os.getloadavg()
            
            data = {
                'temperature': temp,
                'clock_speed': clock,
                'throttled': throttled,
                'voltage': voltage,
                'elapsed_time': elapsed,
                'uptime': uptime_seconds,
                'cpu_percent': cpu_percent,
                'memory_percent': memory.percent,
                'load_avg': list(load_avg)
            }
            
            # Update global current_data
            current_data.update(data)
            return data
            
        except Exception as e:
            self.log_message(f"Error reading sensors: {e}")
            # Ensure system metrics are still available even if hardware sensors fail
            try:
                boot_time = psutil.boot_time()
                uptime_seconds = time.time() - boot_time
                cpu_percent = psutil.cpu_percent()
                memory = psutil.virtual_memory()
                load_avg = os.getloadavg()
                
                current_data.update({
                    'uptime': uptime_seconds,
                    'cpu_percent': cpu_percent,
                    'memory_percent': memory.percent,
                    'load_avg': list(load_avg)
                })
            except:
                pass
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
    temp_file = f"/tmp/config.txt.{int(time.time())}"
    
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
        
        # Write to temp file in /tmp
        with open(temp_file, 'w') as f:
            f.writelines(lines)
        
        # Use sudo to copy temp file to final location
        subprocess.run(['sudo', 'cp', temp_file, config_file], check=True)
        subprocess.run(['rm', temp_file], check=True)
        
        monitor.log_message("Overclock settings applied successfully")
        return True
        
    except Exception as e:
        monitor.log_message(f"Error applying overclock settings: {e}")
        return False

def is_stress_running():
    """Check if any stress process is currently running"""
    global stress_process
    
    # Check our tracked process first
    if stress_process and stress_process.poll() is None:
        return True
    
    # Check system-wide for stress processes
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if proc.info['name'] == 'stress' and any('--cpu' in str(arg) for arg in proc.info['cmdline']):
                # Update our tracked process
                stress_process = subprocess.Popen(['echo'], shell=True)
                stress_process.pid = proc.info['pid']
                monitor.save_stress_pid(proc.info['pid'])
                return True
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    
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
                    'avg_temp': data.get('avg_temp', 0),
                    'system_metrics': data.get('system_metrics', {}),
                    'current_data': data.get('current_data', {})
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
    
    # Always get fresh system metrics for status endpoint
    fresh_data = monitor.get_current_readings()
    
    # Check stress status using enhanced detection
    stress_active = is_stress_running()
    
    return jsonify({
        'monitoring_active': monitoring_active,
        'stress_active': stress_active,
        'stress_installed': check_stress_installed(),
        'current_data': fresh_data,
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
    
    # Check if stress is already running
    if is_stress_running():
        return jsonify({'success': True, 'message': 'Stress test already running'})
    
    if not check_stress_installed():
        monitor.log_message("Stress not installed, attempting installation...")
        if not install_stress():
            return jsonify({'success': False, 'error': 'Failed to install stress package'})
    
    try:
        monitor.log_message("Starting new stress test...")
        stress_process = subprocess.Popen(['stress', '--cpu', '4'])
        monitor.save_stress_pid(stress_process.pid)
        return jsonify({'success': True})
    except Exception as e:
        monitor.log_message(f"Failed to start stress test: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/stop_stress', methods=['POST'])
def stop_stress():
    global stress_process
    
    try:
        # Kill all stress processes
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if proc.info['name'] == 'stress':
                    proc.terminate()
                    monitor.log_message(f"Terminated stress process PID: {proc.info['pid']}")
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        
        # Clean up our tracking
        if stress_process:
            try:
                stress_process.terminate()
                stress_process.wait(timeout=5)
            except:
                pass
            stress_process = None
        
        monitor.remove_stress_pid()
        monitor.log_message("Stress test stopped")
        return jsonify({'success': True})
        
    except Exception as e:
        monitor.log_message(f"Error stopping stress test: {e}")
        return jsonify({'success': False, 'error': str(e)})

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
        # Get recent temperature data for peak/avg calculation
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
        
        # Include complete system metrics in snapshot
        snapshot_data = {
            'timestamp': datetime.now().isoformat(),
            'notes': notes,
            'current_data': dict(current_data),
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
        
        with open(filepath, 'w') as f:
            json.dump(snapshot_data, f, indent=2)
        monitor.log_message(f"Snapshot saved: {filename}")
        return jsonify({'success': True, 'filename': filename})
    except Exception as e:
        monitor.log_message(f"Failed to save snapshot: {e}")
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    # Initialize system metrics on startup
    monitor.get_current_readings()
    monitor.log_message("Pi Monitor started with enhanced session management")
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

print_status 0 "Enhanced Python app with stress test session management"

echo ""
echo "Enhancement 2: Adding enhanced live charting with memory and load metrics..."

# Update JavaScript with enhanced charting and overlay features
sudo -u pi-monitor tee /opt/pi-monitor/static/app.js > /dev/null << 'EOF'
class PiMonitor {
    constructor() {
        this.updateInterval = null;
        self.liveChart = null;
        this.resultsChart = null;
        this.chartData = [];
        this.maxDataPoints = 60;
        this.overlayMode = false;
        this.selectedResults = [];
        this.selectedMetrics = ['temperature', 'cpu_percent']; // Default metrics to show
        this.init();
    }

    init() {
        this.bindEvents();
        this.loadCurrentSettings();
        this.initializeCharts();
        this.startStatusUpdates();
        this.setupOverclockWarning();
        this.setupResultsPageFeatures();
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
            }
        });
    }

    setupResultsPageFeatures() {
        if (window.location.pathname !== '/results') return;
        
        // Setup hover tooltips for result cards
        document.querySelectorAll('.result-card').forEach(card => {
            this.setupResultCardTooltip(card);
        });
        
        // Setup metric selection checkboxes
        this.createMetricSelector();
    }

    createMetricSelector() {
        const chartContainer = document.getElementById('chart-container');
        if (!chartContainer) return;
        
        const selectorHTML = `
            <div class="metric-selector">
                <h4>Select Metrics to Display:</h4>
                <div class="checkbox-grid">
                    <label><input type="checkbox" value="temperature" checked> Temperature</label>
                    <label><input type="checkbox" value="cpu_percent" checked> CPU Load</label>
                    <label><input type="checkbox" value="memory_percent"> Memory</label>
                    <label><input type="checkbox" value="load_avg"> Load Average</label>
                    <label><input type="checkbox" value="clock_speed"> Clock Speed</label>
                    <label><input type="checkbox" value="voltage"> Voltage</label>
                </div>
            </div>
        `;
        
        chartContainer.insertAdjacentHTML('afterbegin', selectorHTML);
        
        // Bind checkbox events
        chartContainer.querySelectorAll('input[type="checkbox"]').forEach(checkbox => {
            checkbox.addEventListener('change', () => {
                this.selectedMetrics = Array.from(chartContainer.querySelectorAll('input[type="checkbox"]:checked'))
                    .map(cb => cb.value);
                this.updateOverlayChart();
            });
        });
    }

    setupResultCardTooltip(card) {
        const tooltip = document.createElement('div');
        tooltip.className = 'result-tooltip';
        tooltip.style.display = 'none';
        document.body.appendChild(tooltip);

        card.addEventListener('mouseenter', (e) => {
            const data = this.getCardData(card);
            tooltip.innerHTML = this.generateTooltipContent(data);
            tooltip.style.display = 'block';
            this.positionTooltip(tooltip, e);
        });

        card.addEventListener('mousemove', (e) => {
            this.positionTooltip(tooltip, e);
        });

        card.addEventListener('mouseleave', () => {
            tooltip.style.display = 'none';
        });
    }

    getCardData(card) {
        return {
            timestamp: card.dataset.timestamp,
            notes: card.dataset.notes || 'No notes',
            peak: parseFloat(card.dataset.peak),
            avg: parseFloat(card.dataset.avg),
            cpu: parseFloat(card.dataset.cpu || 0),
            memory: parseFloat(card.dataset.memory || 0),
            settings: card.dataset.settings
        };
    }

    generateTooltipContent(data) {
        const timestamp = new Date(data.timestamp).toLocaleString();
        return `
            <div class="tooltip-header">${timestamp}</div>
            <div class="tooltip-content">
                <div class="tooltip-row">
                    <span>Peak Temp:</span> <strong>${data.peak}°C</strong>
                </div>
                <div class="tooltip-row">
                    <span>Avg Temp:</span> <strong>${data.avg}°C</strong>
                </div>
                <div class="tooltip-row">
                    <span>CPU Load:</span> <strong>${data.cpu.toFixed(1)}%</strong>
                </div>
                <div class="tooltip-row">
                    <span>Memory:</span> <strong>${data.memory.toFixed(1)}%</strong>
                </div>
                <div class="tooltip-row">
                    <span>Settings:</span> <strong>${data.settings}</strong>
                </div>
                ${data.notes !== 'No notes' ? `<div class="tooltip-notes"><em>"${data.notes}"</em></div>` : ''}
            </div>
        `;
    }

    positionTooltip(tooltip, event) {
        const rect = tooltip.getBoundingClientRect();
        let x = event.pageX + 10;
        let y = event.pageY - rect.height - 10;
        
        // Keep tooltip in viewport
        if (x + rect.width > window.innerWidth) {
            x = event.pageX - rect.width - 10;
        }
        if (y < 0) {
            y = event.pageY + 10;
        }
        
        tooltip.style.left = x + 'px';
        tooltip.style.top = y + 'px';
    }

    formatUptime(seconds) {
        if (!seconds || seconds <= 0) return '--';
        
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const mins = Math.floor((seconds % 3600) / 60);
        
        if (days > 0) return `${days}d ${hours}h`;
        if (hours > 0) return `${hours}h ${mins}m`;
        return `${mins}m`;
    }

    initializeCharts() {
        // Enhanced live chart with memory and load metrics
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
                        tension: 0.4,
                        yAxisID: 'y'
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
                    }, {
                        label: 'Memory %',
                        data: [],
                        borderColor: '#9c27b0',
                        backgroundColor: 'rgba(156, 39, 176, 0.1)',
                        tension: 0.4,
                        yAxisID: 'y2'
                    }, {
                        label: 'Load Avg',
                        data: [],
                        borderColor: '#607d8b',
                        backgroundColor: 'rgba(96, 125, 139, 0.1)',
                        tension: 0.4,
                        yAxisID: 'y3'
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { labels: { color: '#e0e0e0', font: { size: 10 } } }
                    },
                    scales: {
                        x: { ticks: { color: '#b0b0b0', font: { size: 9 } }, grid: { color: '#404040' } },
                        y: { 
                            ticks: { color: '#b0b0b0', font: { size: 9 } }, 
                            grid: { color: '#404040' },
                            title: { display: true, text: 'Temp (°C)', color: '#b0b0b0', font: { size: 9 } }
                        },
                        y1: {
                            type: 'linear',
                            position: 'right',
                            ticks: { color: '#b0b0b0', font: { size: 9 } },
                            title: { display: true, text: 'Clock (GHz)', color: '#b0b0b0', font: { size: 9 } },
                            grid: { drawOnChartArea: false }
                        },
                        y2: {
                            type: 'linear',
                            position: 'right',
                            ticks: { color: '#b0b0b0', font: { size: 9 } },
                            title: { display: true, text: 'CPU/Mem %', color: '#b0b0b0', font: { size: 9 } },
                            grid: { drawOnChartArea: false }
                        },
                        y3: {
                            type: 'linear',
                            position: 'right',
                            ticks: { color: '#b0b0b0', font: { size: 9 } },
                            title: { display: true, text: 'Load', color: '#b0b0b0', font: { size: 9 } },
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
                    plugins: { 
                        legend: { labels: { color: '#e0e0e0' } },
                        tooltip: {
                            mode: 'index',
                            intersect: false,
                        }
                    },
                    scales: {
                        x: { ticks: { color: '#b0b0b0' }, grid: { color: '#404040' } },
                        y: { ticks: { color: '#b0b0b0' }, grid: { color: '#404040' } }
                    }
                }
            });
        }
    }

    updateLiveChart(data) {
        if (!this.liveChart) return;

        const now = new Date().toLocaleTimeString();
        this.chartData.push({
            time: now,
            temp: data.temperature || 0,
            clock: (data.clock_speed || 0) / 1000,
            cpu: data.cpu_percent || 0,
            memory: data.memory_percent || 0,
            load: (data.load_avg && data.load_avg[0]) ? data.load_avg[0] : 0
        });

        if (this.chartData.length > this.maxDataPoints) {
            this.chartData.shift();
        }

        this.liveChart.data.labels = this.chartData.map(d => d.time);
        this.liveChart.data.datasets[0].data = this.chartData.map(d => d.temp);
        this.liveChart.data.datasets[1].data = this.chartData.map(d => d.clock);
        this.liveChart.data.datasets[2].data = this.chartData.map(d => d.cpu);
        this.liveChart.data.datasets[3].data = this.chartData.map(d => d.memory);
        this.liveChart.data.datasets[4].data = this.chartData.map(d => d.load);
        this.liveChart.update('none');
    }

    toggleResultsChart() {
        const container = document.getElementById('chart-container');
        const grid = document.getElementById('results-grid');
        const button = document.getElementById('chart-view-toggle');
        const overlayBtn = document.getElementById('overlay-toggle');
        
        if (container && container.style.display === 'none') {
            container.style.display = 'block';
            if (grid) grid.style.display = 'none';
            button.textContent = 'List View';
            if (overlayBtn) overlayBtn.style.display = 'inline-block';
            this.loadResultsChart();
        } else if (container) {
            container.style.display = 'none';
            if (grid) grid.style.display = 'grid';
            button.textContent = 'Chart View';
            if (overlayBtn) overlayBtn.style.display = 'none';
            const clearBtn = document.getElementById('clear-overlay');
            if (clearBtn) clearBtn.style.display = 'none';
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

        const datasets = [];
        const colors = ['#ff9800', '#4a9eff', '#4caf50', '#f44336', '#9c27b0', '#607d8b'];
        
        this.selectedResults.forEach((card, index) => {
            const data = this.getCardData(card);
            const baseColor = colors[index % colors.length];
            
            this.selectedMetrics.forEach((metric, metricIndex) => {
                const value = this.getMetricValue(data, metric);
                if (value !== null) {
                    datasets.push({
                        label: `${data.timestamp.substring(5, 16)} - ${this.getMetricLabel(metric)}`,
                        data: [value],
                        backgroundColor: this.adjustColor(baseColor, metricIndex * 20),
                        borderColor: baseColor,
                        borderWidth: 1
                    });
                }
            });
        });

        this.resultsChart.data.labels = ['Comparison'];
        this.resultsChart.data.datasets = datasets;
        this.resultsChart.update();
    }

    getMetricValue(data, metric) {
        switch (metric) {
            case 'temperature': return data.peak;
            case 'cpu_percent': return data.cpu;
            case 'memory_percent': return data.memory;
            case 'load_avg': return data.load || 0;
            case 'clock_speed': return (data.clock || 2400) / 1000; // Convert to GHz
            case 'voltage': return data.voltage || 0;
            default: return null;
        }
    }

    getMetricLabel(metric) {
        const labels = {
            'temperature': 'Temp (°C)',
            'cpu_percent': 'CPU %',
            'memory_percent': 'Memory %',
            'load_avg': 'Load Avg',
            'clock_speed': 'Clock (GHz)',
            'voltage': 'Voltage (V)'
        };
        return labels[metric] || metric;
    }

    adjustColor(color, offset) {
        // Simple color adjustment for multiple metrics from same session
        const hex = color.replace('#', '');
        const r = Math.min(255, parseInt(hex.substr(0, 2), 16) + offset);
        const g = Math.min(255, parseInt(hex.substr(2, 2), 16) + offset);
        const b = Math.min(255, parseInt(hex.substr(4, 2), 16) + offset);
        return `rgb(${r}, ${g}, ${b})`;
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
        if (result.message && result.message.includes('already running')) {
            this.showToast('Stress test already active', 'warning');
        } else {
            this.showToast(result.success ? 'Stress test started' : result.error, result.success ? 'success' : 'error');
        }
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
                
                // Trigger warning check
                setTimeout(() => {
                    const event = new Event('input');
                    document.getElementById('arm-freq').dispatchEvent(event);
                }, 100);
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
        // Hardware metrics
        this.updateElement('temperature', `${(data.temperature || 0).toFixed(1)}°C`);
        this.updateElement('clock-speed', `${data.clock_speed || 0} MHz`);
        this.updateElement('voltage', `${(data.voltage || 0).toFixed(4)} V`);
        this.updateElement('throttled', data.throttled ? 'YES' : 'NO');
        
        // System metrics with proper handling
        this.updateElement('uptime', this.formatUptime(data.uptime));
        this.updateElement('cpu-load', `${(data.cpu_percent || 0).toFixed(1)}%`);
        this.updateElement('memory-usage', `${(data.memory_percent || 0).toFixed(1)}%`);
        
        // Load average - handle array properly
        if (data.load_avg && Array.isArray(data.load_avg) && data.load_avg.length >= 1) {
            this.updateElement('load-avg', `${data.load_avg[0].toFixed(2)}`);
        } else {
            this.updateElement('load-avg', '--');
        }
        
        // Update indicators
        this.updateIndicator('temp-indicator', data.temperature < 60 ? 'good' : data.temperature < 75 ? 'warning' : 'danger');
        this.updateIndicator('throttle-indicator', data.throttled ? 'danger' : 'good');
    }

    updateElement(id, value) {
        const el = document.getElementById(id);
        if (el) el.textContent = value;
    }

    updateIndicator(id, status) {
        const ind = document.getElementById(id);
        if (ind) ind.className = `status-indicator ${status}`;
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
                appLogsDiv.scrollTop = appLogsDiv.scrollHeight;
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
                systemLogsDiv.scrollTop = systemLogsDiv.scrollHeight;
            } else {
                systemLogsDiv.innerHTML = '<div class="loading">No system logs found</div>';
            }

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

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    window.piMonitor = new PiMonitor();
    
    // Auto-load logs if on logs page
    if (window.location.pathname === '/logs') {
        setTimeout(() => window.piMonitor.loadLogs(), 500);
        setInterval(() => window.piMonitor.loadLogs(), 30000);
    }
});
EOF

print_status 0 "Enhanced Python app with stress session management"

echo ""
echo "Enhancement 2: Updating results template with enhanced data attributes..."

# Update results template to include all necessary data for tooltips and overlay
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
        <div class="result-card" 
             data-timestamp="{{ result.timestamp }}" 
             data-peak="{{ result.peak_temp }}" 
             data-avg="{{ result.avg_temp }}" 
             data-settings="{{ result.settings.arm_freq or 2400 }}/{{ result.settings.gpu_freq or 800 }}"
             data-notes="{{ result.notes or 'No notes' }}"
             data-cpu="{{ result.system_metrics.cpu_percent or 0 if result.system_metrics else 0 }}"
             data-memory="{{ result.system_metrics.memory_percent or 0 if result.system_metrics else 0 }}"
             data-load="{{ result.system_metrics.load_avg[0] or 0 if result.system_metrics and result.system_metrics.load_avg else 0 }}"
             data-clock="{{ result.current_data.clock_speed or 2400 if result.current_data else 2400 }}"
             data-voltage="{{ result.current_data.voltage or 0 if result.current_data else 0 }}">
            <div class="result-header">
                <h3>{{ result.timestamp[:16] | replace('T', ' ') }}</h3>
                <div class="result-stats">
                    <span class="stat">Peak: {{ result.peak_temp }}°C</span>
                    <span class="stat">Avg: {{ result.avg_temp }}°C</span>
                    {% if result.system_metrics %}
                    <span class="stat">CPU: {{ "%.1f"|format(result.system_metrics.cpu_percent) }}%</span>
                    <span class="stat">Load: {{ "%.2f"|format(result.system_metrics.load_avg[0]) if result.system_metrics.load_avg else "0.00" }}</span>
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

print_status 0 "Updated results template with enhanced data attributes"

echo ""
echo "Enhancement 3: Adding enhanced CSS for tooltips and metric selector..."

# Add tooltip and metric selector styles to CSS
sudo -u pi-monitor tee -a /opt/pi-monitor/static/style.css > /dev/null << 'EOF'

/* Enhanced tooltip styles */
.result-tooltip {
    position: absolute;
    background: var(--bg-primary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.5);
    z-index: 1000;
    max-width: 300px;
    font-size: 0.85rem;
    pointer-events: none;
}

.tooltip-header {
    font-weight: 600;
    color: var(--accent-primary);
    margin-bottom: 0.5rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.5rem;
    font-size: 0.9rem;
}

.tooltip-content {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
}

.tooltip-row {
    display: flex;
    justify-content: space-between;
    color: var(--text-secondary);
}

.tooltip-row strong {
    color: var(--text-primary);
}

.tooltip-notes {
    margin-top: 0.5rem;
    padding-top: 0.5rem;
    border-top: 1px solid var(--border);
    color: var(--text-secondary);
    font-style: italic;
    font-size: 0.8rem;
}

/* Metric selector styles */
.metric-selector {
    background: var(--bg-tertiary);
    border: 1px solid var(--border);
    border-radius: 4px;
    padding: 1rem;
    margin-bottom: 1rem;
}

.metric-selector h4 {
    color: var(--text-primary);
    margin-bottom: 0.75rem;
    font-size: 0.9rem;
}

.checkbox-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 0.5rem;
}

.checkbox-grid label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--text-secondary);
    font-size: 0.85rem;
    cursor: pointer;
    padding: 0.25rem;
    border-radius: 3px;
    transition: background-color 0.2s;
}

.checkbox-grid label:hover {
    background: var(--bg-secondary);
}

.checkbox-grid input[type="checkbox"] {
    width: 16px;
    height: 16px;
    accent-color: var(--accent-primary);
}

/* Enhanced result card hover effects */
.result-card:hover .result-header h3 {
    color: #3a8ce6;
}

.result-card.selected .result-header h3 {
    color: var(--accent-primary);
}

/* Mobile responsive tooltips */
@media (max-width: 768px) {
    .result-tooltip {
        max-width: 250px;
        font-size: 0.8rem;
        padding: 0.75rem;
    }
    
    .checkbox-grid {
        grid-template-columns: repeat(2, 1fr);
    }
    
    .tooltip-header {
        font-size: 0.85rem;
    }
}

@media (max-width: 480px) {
    .result-tooltip {
        max-width: 200px;
        font-size: 0.75rem;
        padding: 0.5rem;
    }
    
    .checkbox-grid {
        grid-template-columns: 1fr;
    }
}
EOF

print_status 0 "Added enhanced CSS for tooltips and metric selector"

echo ""
echo "Enhancement 4: Restarting service to apply all enhancements..."

sudo systemctl restart pi-monitor.service
sleep 3

if systemctl is-active --quiet pi-monitor.service; then
    print_status 0 "Service restarted with all enhancements"
    PI_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "Enhanced Pi Monitor v3.1 available at:"
    echo "  Local:   http://localhost:5000"
    echo "  Network: http://$PI_IP:5000"
else
    print_status 1 "Service failed to restart"
    echo "Check logs: sudo journalctl -u pi-monitor.service -n 10"
fi

echo ""
echo "=========================================="
echo "ENHANCED MONITORING UPDATE COMPLETE!"
echo "=========================================="
echo ""
echo "✅ Stress Test Session Management:"
echo "  • Prevents duplicate stress tests after page reload/crash"
echo "  • Tracks existing stress processes on startup"
echo "  • PID file management for session persistence"
echo "  • Enhanced process detection and cleanup"
echo ""
echo "✅ Enhanced Live Charting:"
echo "  • Added Memory % tracking to live chart"
echo "  • Added Load Average tracking to live chart"  
echo "  • 5 real-time metrics: Temperature, Clock, CPU%, Memory%, Load Avg"
echo "  • Optimized chart layout with multiple Y-axes"
echo ""
echo "✅ Results Page Overlay Enhancements:"
echo "  • Hover tooltips show complete session data and notes"
echo "  • Metric selector checkboxes for custom data visualization"
echo "  • Enhanced overlay comparison with selectable data points"
echo "  • System load information comparison across sessions"
echo ""
echo "New Features:"
echo "  • Hover over result cards to see detailed tooltip with notes and system stats"
echo "  • Select which metrics to display in overlay chart mode"
echo "  • Compare temperature, CPU load, memory, load average, clock speed, and voltage"
echo "  • Stress test session persistence prevents duplicates"
echo "  • Live chart now shows 5 simultaneous metrics with proper scaling"
echo ""
echo "The Pi Monitor now provides comprehensive system analysis with advanced"
echo "visualization tools for comparing performance across different configurations!"
