#!/bin/bash

echo "=========================================="
echo "Pi Monitor UI Enhancement - Live Charts & Mobile Layout"
echo "=========================================="

# Update the main HTML template with live chart area
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

    <!-- Compact Snapshot Section -->
    <div class="snapshot-panel compact">
        <h2>Save Snapshot</h2>
        <textarea id="notes" placeholder="Add notes..." rows="2"></textarea>
        <button id="save-snapshot" class="btn btn-primary btn-sm">Save Snapshot</button>
    </div>
</div>
<div id="toast" class="toast"></div>
{% endblock %}
EOF

# Update results page with chart capability
sudo -u pi-monitor tee /opt/pi-monitor/templates/results.html > /dev/null << 'EOF'
{% extends "base.html" %}
{% block title %}Results - Pi Monitor{% endblock %}
{% block content %}
<div class="results-page">
    <div class="results-header">
        <h2>Test Results</h2>
        <button id="chart-view-toggle" class="btn btn-secondary btn-sm">Chart View</button>
    </div>
    
    <div id="chart-container" class="chart-container" style="display:none;">
        <canvas id="resultsChart" width="400" height="300"></canvas>
    </div>
    
    {% if results %}
    <div class="results-grid" id="results-grid">
        {% for result in results %}
        <div class="result-card" data-timestamp="{{ result.timestamp }}" data-peak="{{ result.peak_temp }}" data-avg="{{ result.avg_temp }}" data-settings="{{ result.settings.arm_freq or 2400 }}/{{ result.settings.gpu_freq or 800 }}">
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

# Update base template to include Chart.js CDN
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

# Update CSS for compact mobile-friendly design
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
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 0.75rem;
}

.status-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    text-align: center;
    position: relative;
}

.status-card h3 {
    font-size: 0.75rem;
    color: var(--text-secondary);
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

.status-value {
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--text-primary);
}

.status-indicator {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    position: absolute;
    top: 0.75rem;
    right: 0.75rem;
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

.overclock-panel h2, .snapshot-panel h2 {
    font-size: 1rem;
    margin-bottom: 0.75rem;
    color: var(--text-primary);
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

.chart-container {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    margin-bottom: 1rem;
}

.results-grid { display: grid; gap: 1rem; }

.result-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
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
    
    .chart-section {
        height: 200px;
    }
    
    .overclock-grid { grid-template-columns: 1fr; }
    .button-group { justify-content: center; }
    .results-header { flex-direction: column; gap: 0.5rem; }
    .result-header { flex-direction: column; align-items: flex-start; gap: 0.25rem; }
}

@media (max-width: 480px) {
    .status-grid { grid-template-columns: 1fr; }
    .controls-section { flex-direction: column; }
    .nav-links { gap: 0.5rem; }
    .nav-link { padding: 0.4rem 0.6rem; font-size: 0.8rem; }
}
EOF

# Update JavaScript with charting functionality
sudo -u pi-monitor tee /opt/pi-monitor/static/app.js > /dev/null << 'EOF'
class PiMonitor {
    constructor() {
        this.updateInterval = null;
        this.liveChart = null;
        this.resultsChart = null;
        this.chartData = [];
        this.maxDataPoints = 60;
        this.init();
    }

    init() {
        this.bindEvents();
        this.loadCurrentSettings();
        this.initializeCharts();
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
        document.getElementById('chart-view-toggle')?.addEventListener('click', () => this.toggleResultsChart());
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
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { labels: { color: '#e0e0e0' } }
                    },
                    scales: {
                        x: { ticks: { color: '#b0b0b0' }, grid: { color: '#404040' } },
                        y: { 
                            ticks: { color: '#b0b0b0' }, 
                            grid: { color: '#404040' },
                            title: { display: true, text: 'Temperature (°C)', color: '#b0b0b0' }
                        },
                        y1: {
                            type: 'linear',
                            position: 'right',
                            ticks: { color: '#b0b0b0' },
                            title: { display: true, text: 'Clock (GHz)', color: '#b0b0b0' },
                            grid: { drawOnChartArea: false }
                        }
                    }
                }
            });
        }

        // Initialize results chart
        const resultsCtx = document.getElementById('resultsChart');
        if (resultsCtx) {
            this.resultsChart = new Chart(resultsCtx, {
                type: 'bar',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Peak Temp (°C)',
                        data: [],
                        backgroundColor: 'rgba(255, 152, 0, 0.7)',
                        borderColor: '#ff9800',
                        borderWidth: 1
                    }, {
                        label: 'Avg Temp (°C)',
                        data: [],
                        backgroundColor: 'rgba(74, 158, 255, 0.7)',
                        borderColor: '#4a9eff',
                        borderWidth: 1
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { labels: { color: '#e0e0e0' } }
                    },
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
        
        if (container.style.display === 'none') {
            container.style.display = 'block';
            grid.style.display = 'none';
            button.textContent = 'List View';
            this.loadResultsChart();
        } else {
            container.style.display = 'none';
            grid.style.display = 'grid';
            button.textContent = 'Chart View';
        }
    }

    loadResultsChart() {
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
            this.resultsChart.data.datasets[0].data = peakData;
            this.resultsChart.data.datasets[1].data = avgData;
            this.resultsChart.update();
        }
    }

    updateLiveChart(data) {
        if (!this.liveChart) return;

        const now = new Date().toLocaleTimeString();
        this.chartData.push({
            time: now,
            temp: data.temperature,
            clock: data.clock_speed / 1000
        });

        if (this.chartData.length > this.maxDataPoints) {
            this.chartData.shift();
        }

        this.liveChart.data.labels = this.chartData.map(d => d.time);
        this.liveChart.data.datasets[0].data = this.chartData.map(d => d.temp);
        this.liveChart.data.datasets[1].data = this.chartData.map(d => d.clock);
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
                if (ind) ind.className = `status-indicator ${indicator.includes('temp') ? 
                    (data.temperature < 60 ? 'good' : data.temperature < 75 ? 'warning' : 'danger') :
                    (data.throttled ? 'danger' : 'good')}`;
            }
        };

        updateElement('temperature', `${data.temperature.toFixed(1)}°C`, 'temp-indicator');
        updateElement('clock-speed', `${data.clock_speed} MHz`);
        updateElement('voltage', `${data.voltage.toFixed(4)} V`);
        updateElement('throttled', data.throttled ? 'YES' : 'NO', 'throttle-indicator');
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

document.addEventListener('DOMContentLoaded', () => {
    window.piMonitor = new PiMonitor();
});
EOF

# Restart the service to apply changes
sudo systemctl restart pi-monitor.service

echo "✓ UI Enhanced - Live charts and mobile-friendly layout added"
echo "✓ Chart.js CDN integrated for real-time graphing"
echo "✓ Compact layout optimized for mobile devices"
echo "✓ Historical results chart view added"
echo ""
echo "New Features:"
echo "  • Live temperature and clock speed chart in monitoring panel"
echo "  • Chart view toggle on results page for historical data visualization"
echo "  • Compact mobile-friendly layout with responsive design"
echo "  • Enhanced touch-friendly controls for mobile devices"
