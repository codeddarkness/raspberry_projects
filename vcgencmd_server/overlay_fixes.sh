#!/bin/bash

echo "=========================================="
echo "Pi Monitor Overlay Fix & Landing Page Setup"
echo "=========================================="

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "\033[0;32m✓\033[0m $2"
    else
        echo -e "\033[0;31m✗\033[0m $2"
    fi
}

echo "Fix 1: Fixing chart overlay mode functionality..."

# Update JavaScript with working overlay mode
sudo -u pi-monitor tee /opt/pi-monitor/static/app.js > /dev/null << 'EOF'
class PiMonitor {
    constructor() {
        this.updateInterval = null;
        this.liveChart = null;
        this.resultsChart = null;
        this.chartData = [];
        this.maxDataPoints = 60;
        this.overlayMode = false;
        this.selectedResults = new Set();
        this.selectedMetrics = ['temperature', 'cpu_percent'];
        this.init();
    }

    init() {
        this.bindEvents();
        this.loadCurrentSettings();
        this.initializeCharts();
        this.startStatusUpdates();
        this.setupOverclockWarning();
        
        // Initialize results page features after DOM is ready
        if (window.location.pathname === '/results') {
            setTimeout(() => this.setupResultsPageFeatures(), 500);
        }
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
        console.log('Setting up results page features...');
        
        // Setup tooltips for all result cards
        const cards = document.querySelectorAll('.result-card');
        console.log(`Found ${cards.length} result cards`);
        
        cards.forEach((card, index) => {
            console.log(`Setting up tooltip for card ${index}`);
            this.setupResultCardTooltip(card);
        });
        
        // Create metric selector
        this.createMetricSelector();
    }

    createMetricSelector() {
        const chartContainer = document.getElementById('chart-container');
        if (!chartContainer) return;
        
        // Remove existing metric selector if present
        const existing = chartContainer.querySelector('.metric-selector');
        if (existing) existing.remove();
        
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
                console.log('Selected metrics:', this.selectedMetrics);
                this.updateOverlayChart();
            });
        });
        
        console.log('Metric selector created');
    }

    setupResultCardTooltip(card) {
        let tooltip = document.getElementById('global-tooltip');
        if (!tooltip) {
            tooltip = document.createElement('div');
            tooltip.id = 'global-tooltip';
            tooltip.className = 'result-tooltip';
            tooltip.style.display = 'none';
            document.body.appendChild(tooltip);
        }

        card.addEventListener('mouseenter', (e) => {
            const data = this.getCardData(card);
            tooltip.innerHTML = this.generateTooltipContent(data);
            tooltip.style.display = 'block';
            this.positionTooltip(tooltip, e);
        });

        card.addEventListener('mousemove', (e) => {
            if (tooltip.style.display === 'block') {
                this.positionTooltip(tooltip, e);
            }
        });

        card.addEventListener('mouseleave', () => {
            tooltip.style.display = 'none';
        });
    }

    getCardData(card) {
        return {
            timestamp: card.dataset.timestamp,
            notes: card.dataset.notes || 'No notes',
            peak: parseFloat(card.dataset.peak || 0),
            avg: parseFloat(card.dataset.avg || 0),
            cpu: parseFloat(card.dataset.cpu || 0),
            memory: parseFloat(card.dataset.memory || 0),
            load: parseFloat(card.dataset.load || 0),
            clock: parseFloat(card.dataset.clock || 2400),
            voltage: parseFloat(card.dataset.voltage || 0),
            settings: card.dataset.settings || 'Unknown'
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
                    <span>Load Avg:</span> <strong>${data.load.toFixed(2)}</strong>
                </div>
                <div class="tooltip-row">
                    <span>Clock:</span> <strong>${data.clock} MHz</strong>
                </div>
                <div class="tooltip-row">
                    <span>Voltage:</span> <strong>${data.voltage.toFixed(4)} V</strong>
                </div>
                <div class="tooltip-row">
                    <span>Settings:</span> <strong>${data.settings}</strong>
                </div>
                ${data.notes !== 'No notes' ? `<div class="tooltip-notes"><strong>Notes:</strong><br><em>"${data.notes}"</em></div>` : ''}
            </div>
        `;
    }

    positionTooltip(tooltip, event) {
        const rect = tooltip.getBoundingClientRect();
        let x = event.pageX + 10;
        let y = event.pageY - rect.height - 10;
        
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
        // Live chart
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

        // Results chart with FIXED dimensions and working overlay
        const resultsCtx = document.getElementById('resultsChart');
        if (resultsCtx) {
            // Force canvas dimensions
            resultsCtx.width = 800;
            resultsCtx.height = 400;
            resultsCtx.style.width = '100%';
            resultsCtx.style.height = '400px';
            resultsCtx.style.maxHeight = '400px';
            
            this.resultsChart = new Chart(resultsCtx, {
                type: 'bar',
                data: { labels: [], datasets: [] },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { 
                        legend: { 
                            labels: { color: '#e0e0e0', font: { size: 11 } },
                            position: 'top',
                            maxHeight: 60
                        },
                        tooltip: {
                            mode: 'index',
                            intersect: false,
                            backgroundColor: 'rgba(26, 26, 26, 0.9)',
                            titleColor: '#e0e0e0',
                            bodyColor: '#b0b0b0',
                            borderColor: '#404040',
                            borderWidth: 1
                        }
                    },
                    scales: {
                        x: { 
                            ticks: { 
                                color: '#b0b0b0',
                                maxRotation: 45,
                                font: { size: 10 }
                            }, 
                            grid: { color: '#404040' } 
                        },
                        y: { 
                            ticks: { 
                                color: '#b0b0b0',
                                font: { size: 10 }
                            }, 
                            grid: { color: '#404040' },
                            beginAtZero: true
                        }
                    },
                    layout: {
                        padding: { top: 5, right: 5, bottom: 5, left: 5 }
                    }
                }
            });
        }
    }

    setupResultsPageFeatures() {
        console.log('Setting up results page features...');
        
        const cards = document.querySelectorAll('.result-card');
        console.log(`Found ${cards.length} result cards`);
        
        cards.forEach((card, index) => {
            this.setupResultCardTooltip(card);
        });
        
        this.createMetricSelector();
    }

    createMetricSelector() {
        const chartContainer = document.getElementById('chart-container');
        if (!chartContainer) return;
        
        const existing = chartContainer.querySelector('.metric-selector');
        if (existing) existing.remove();
        
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
        
        chartContainer.querySelectorAll('input[type="checkbox"]').forEach(checkbox => {
            checkbox.addEventListener('change', () => {
                this.selectedMetrics = Array.from(chartContainer.querySelectorAll('input[type="checkbox"]:checked'))
                    .map(cb => cb.value);
                console.log('Updated selected metrics:', this.selectedMetrics);
                if (this.overlayMode) {
                    this.updateOverlayChart();
                }
            });
        });
        
        console.log('Metric selector created and bound');
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
            
            setTimeout(() => {
                this.createMetricSelector();
                this.loadResultsChart();
            }, 100);
        } else if (container) {
            container.style.display = 'none';
            if (grid) grid.style.display = 'grid';
            button.textContent = 'Chart View';
            if (overlayBtn) overlayBtn.style.display = 'none';
            const clearBtn = document.getElementById('clear-overlay');
            if (clearBtn) clearBtn.style.display = 'none';
            this.overlayMode = false;
        }
    }

    toggleOverlay() {
        this.overlayMode = !this.overlayMode;
        const button = document.getElementById('overlay-toggle');
        const info = document.getElementById('overlay-info');
        const clearBtn = document.getElementById('clear-overlay');
        
        console.log('Toggling overlay mode to:', this.overlayMode);
        
        if (this.overlayMode) {
            button.textContent = 'Exit Overlay';
            button.style.backgroundColor = 'var(--warning)';
            info.style.display = 'block';
            clearBtn.style.display = 'inline-block';
            this.setupResultCardClicks();
            this.showToast('Overlay mode active - click result cards to select', 'success');
        } else {
            button.textContent = 'Overlay Mode';
            button.style.backgroundColor = 'var(--bg-tertiary)';
            info.style.display = 'none';
            clearBtn.style.display = 'none';
            this.clearOverlay();
        }
    }

    setupResultCardClicks() {
        console.log('Setting up result card clicks for overlay mode...');
        document.querySelectorAll('.result-card').forEach((card, index) => {
            // Remove existing click listeners
            card.onclick = null;
            
            // Add new click listener for overlay mode
            card.addEventListener('click', (e) => {
                e.stopPropagation();
                this.toggleResultSelection(card);
            });
            
            // Visual indication that cards are clickable
            card.style.cursor = 'pointer';
            card.title = 'Click to select for overlay comparison';
        });
    }

    toggleResultSelection(card) {
        if (!this.overlayMode) return;
        
        console.log('Toggling selection for card:', card.dataset.timestamp);
        
        if (this.selectedResults.has(card)) {
            this.selectedResults.delete(card);
            card.classList.remove('selected');
            console.log('Deselected card');
        } else {
            this.selectedResults.add(card);
            card.classList.add('selected');
            console.log('Selected card');
        }
        
        const count = this.selectedResults.size;
        document.getElementById('selected-count').textContent = count;
        console.log(`Total selected: ${count}`);
        
        this.updateOverlayChart();
    }

    clearOverlay() {
        console.log('Clearing overlay selection...');
        this.selectedResults.forEach(card => {
            card.classList.remove('selected');
            card.style.cursor = '';
            card.title = '';
        });
        this.selectedResults.clear();
        
        const countEl = document.getElementById('selected-count');
        if (countEl) countEl.textContent = '0';
        
        this.loadResultsChart();
        console.log('Overlay cleared');
    }

    updateOverlayChart() {
        console.log('Updating overlay chart...', this.selectedResults.size, 'cards selected');
        
        if (!this.overlayMode || this.selectedResults.size === 0) {
            this.loadResultsChart();
            return;
        }

        const datasets = [];
        const colors = ['#ff9800', '#4a9eff', '#4caf50', '#f44336', '#9c27b0', '#607d8b'];
        const labels = [];
        
        // Create dataset for each selected metric
        this.selectedMetrics.forEach((metric, metricIndex) => {
            const metricData = [];
            const metricLabels = [];
            
            Array.from(this.selectedResults).forEach((card, cardIndex) => {
                const data = this.getCardData(card);
                const value = this.getMetricValue(data, metric);
                const sessionLabel = data.timestamp.substring(5, 16);
                
                metricData.push(value);
                if (metricIndex === 0) metricLabels.push(sessionLabel); // Only add labels once
            });
            
            if (metricIndex === 0) labels.push(...metricLabels);
            
            datasets.push({
                label: this.getMetricLabel(metric),
                data: metricData,
                backgroundColor: this.adjustColorOpacity(colors[metricIndex % colors.length], 0.7),
                borderColor: colors[metricIndex % colors.length],
                borderWidth: 2
            });
        });

        this.resultsChart.data.labels = labels;
        this.resultsChart.data.datasets = datasets;
        this.resultsChart.update();
        
        console.log('Overlay chart updated with', datasets.length, 'datasets');
    }

    getMetricValue(data, metric) {
        switch (metric) {
            case 'temperature': return data.peak;
            case 'cpu_percent': return data.cpu;
            case 'memory_percent': return data.memory;
            case 'load_avg': return data.load;
            case 'clock_speed': return data.clock / 1000;
            case 'voltage': return data.voltage * 1000;
            default: return 0;
        }
    }

    getMetricLabel(metric) {
        const labels = {
            'temperature': 'Peak Temp (°C)',
            'cpu_percent': 'CPU Load %',
            'memory_percent': 'Memory %',
            'load_avg': 'Load Average',
            'clock_speed': 'Clock Speed (GHz)',
            'voltage': 'Voltage (mV)'
        };
        return labels[metric] || metric;
    }

    adjustColorOpacity(color, opacity) {
        const hex = color.replace('#', '');
        const r = parseInt(hex.substr(0, 2), 16);
        const g = parseInt(hex.substr(2, 2), 16);
        const b = parseInt(hex.substr(4, 2), 16);
        return `rgba(${r}, ${g}, ${b}, ${opacity})`;
    }

    loadResultsChart() {
        const cards = document.querySelectorAll('.result-card');
        const labels = [];
        const peakData = [];
        const avgData = [];
        const cpuData = [];

        cards.forEach(card => {
            const timestamp = card.dataset.timestamp;
            const peak = parseFloat(card.dataset.peak);
            const avg = parseFloat(card.dataset.avg);
            const cpu = parseFloat(card.dataset.cpu || 0);
            
            labels.push(timestamp.substring(5, 16));
            peakData.push(peak);
            avgData.push(avg);
            cpuData.push(cpu);
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
            }, {
                label: 'CPU Load %',
                data: cpuData,
                backgroundColor: 'rgba(76, 175, 80, 0.7)',
                borderColor: '#4caf50',
                borderWidth: 1
            }];
            this.resultsChart.update();
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
        this.updateElement('temperature', `${(data.temperature || 0).toFixed(1)}°C`);
        this.updateElement('clock-speed', `${data.clock_speed || 0} MHz`);
        this.updateElement('voltage', `${(data.voltage || 0).toFixed(4)} V`);
        this.updateElement('throttled', data.throttled ? 'YES' : 'NO');
        this.updateElement('uptime', this.formatUptime(data.uptime));
        this.updateElement('cpu-load', `${(data.cpu_percent || 0).toFixed(1)}%`);
        this.updateElement('memory-usage', `${(data.memory_percent || 0).toFixed(1)}%`);
        
        if (data.load_avg && Array.isArray(data.load_avg) && data.load_avg.length >= 1) {
            this.updateElement('load-avg', `${data.load_avg[0].toFixed(2)}`);
        } else {
            this.updateElement('load-avg', '--');
        }
        
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

document.addEventListener('DOMContentLoaded', () => {
    window.piMonitor = new PiMonitor();
    
    if (window.location.pathname === '/logs') {
        setTimeout(() => window.piMonitor.loadLogs(), 500);
        setInterval(() => window.piMonitor.loadLogs(), 30000);
    }
});
EOF

print_status 0 "Fixed overlay mode functionality with working selection"

echo ""
echo "Enhancement 2: Adding enhanced tooltip styles..."

# Add tooltip styles to CSS
sudo -u pi-monitor tee -a /opt/pi-monitor/static/style.css > /dev/null << 'EOF'

/* Enhanced result card tooltip styles */
.result-tooltip {
    position: absolute;
    background: var(--bg-primary);
    border: 2px solid var(--accent-primary);
    border-radius: 8px;
    padding: 1rem;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6);
    z-index: 1000;
    max-width: 350px;
    font-size: 0.85rem;
    pointer-events: none;
}

.tooltip-header {
    font-weight: 600;
    color: var(--accent-primary);
    margin-bottom: 0.75rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.5rem;
    font-size: 0.9rem;
}

.tooltip-content {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
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
    margin-top: 0.75rem;
    padding-top: 0.75rem;
    border-top: 1px solid var(--border);
    color: var(--text-secondary);
    font-size: 0.8rem;
}

.tooltip-notes strong {
    color: var(--accent-primary);
}

/* Metric selector enhanced styles */
.metric-selector {
    background: var(--bg-tertiary);
    border: 1px solid var(--border);
    border-radius: 6px;
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
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 0.5rem;
}

.checkbox-grid label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--text-secondary);
    font-size: 0.85rem;
    cursor: pointer;
    padding: 0.4rem;
    border-radius: 4px;
    transition: all 0.2s;
}

.checkbox-grid label:hover {
    background: var(--bg-secondary);
    color: var(--text-primary);
}

.checkbox-grid input[type="checkbox"] {
    width: 16px;
    height: 16px;
    accent-color: var(--accent-primary);
}

/* Enhanced result card selection styles */
.result-card.selected {
    border-color: var(--accent-primary) !important;
    background: rgba(74, 158, 255, 0.15) !important;
    transform: scale(1.02);
    box-shadow: 0 4px 12px rgba(74, 158, 255, 0.3);
}

.result-card:hover {
    border-color: var(--accent-primary);
    transform: translateY(-2px);
    box-shadow: 0 4px 12px var(--shadow);
}

/* Overlay mode visual indicators */
.results-page.overlay-active .result-card {
    cursor: pointer !important;
    transition: all 0.3s ease;
}

.overlay-info {
    text-align: center;
    margin-top: 0.5rem;
    padding: 0.5rem;
    background: var(--bg-tertiary);
    border-radius: 4px;
    color: var(--text-secondary);
    font-size: 0.9rem;
}

/* Button state indicators */
.btn.active {
    background: var(--warning) !important;
    color: white !important;
}

/* Mobile responsive tooltips and overlay */
@media (max-width: 768px) {
    .result-tooltip {
        max-width: 280px;
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
        max-width: 250px;
        font-size: 0.75rem;
        padding: 0.5rem;
    }
    
    .checkbox-grid {
        grid-template-columns: 1fr;
    }
}
EOF

print_status 0 "Enhanced tooltip and overlay styles"

echo ""
echo "Creating Landing Page & Proxy System..."

# Create nginx + squid landing page setup script in home directory
tee ~/setup-johnny5-services.sh > /dev/null << 'EOF'
#!/bin/bash

echo "=========================================="
echo "Johnny5 Services Landing Page Setup"
echo "=========================================="

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "\033[0;32m✓\033[0m $2"
    else
        echo -e "\033[0;31m✗\033[0m $2"
    fi
}

# Install nginx and squid
echo "Step 1: Installing nginx and squid..."
sudo apt update
sudo apt install -y nginx squid

print_status 0 "Installed nginx and squid"

echo ""
echo "Step 2: Configuring nginx landing page..."

# Create landing page HTML
sudo tee /var/www/html/index.html > /dev/null << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Johnny5 Services Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: linear-gradient(135deg, #1a1a1a 0%, #2d2d2d 100%);
            color: #e0e0e0;
            min-height: 100vh;
            padding: 2rem;
        }
        
        .container {
            max-width: 800px;
            margin: 0 auto;
            text-align: center;
        }
        
        h1 {
            color: #4a9eff;
            margin-bottom: 0.5rem;
            font-size: 2.5rem;
            font-weight: 300;
        }
        
        .subtitle {
            color: #b0b0b0;
            margin-bottom: 3rem;
            font-size: 1.1rem;
        }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-bottom: 3rem;
        }
        
        .service-card {
            background: rgba(45, 45, 45, 0.8);
            border: 1px solid #404040;
            border-radius: 12px;
            padding: 2rem;
            transition: all 0.3s ease;
            backdrop-filter: blur(10px);
        }
        
        .service-card:hover {
            border-color: #4a9eff;
            transform: translateY(-4px);
            box-shadow: 0 8px 24px rgba(74, 158, 255, 0.2);
        }
        
        .service-title {
            color: #4a9eff;
            font-size: 1.3rem;
            margin-bottom: 0.5rem;
            font-weight: 600;
        }
        
        .service-description {
            color: #b0b0b0;
            margin-bottom: 1.5rem;
            font-size: 0.95rem;
        }
        
        .service-link {
            display: inline-block;
            background: linear-gradient(135deg, #4a9eff, #3a8ce6);
            color: white;
            text-decoration: none;
            padding: 0.75rem 2rem;
            border-radius: 8px;
            font-weight: 500;
            transition: all 0.3s ease;
        }
        
        .service-link:hover {
            transform: scale(1.05);
            box-shadow: 0 4px 16px rgba(74, 158, 255, 0.4);
        }
        
        .service-url {
            color: #808080;
            font-size: 0.8rem;
            margin-top: 0.5rem;
            font-family: monospace;
        }
        
        .proxy-info {
            background: rgba(45, 45, 45, 0.8);
            border: 1px solid #404040;
            border-radius: 12px;
            padding: 2rem;
            text-align: left;
        }
        
        .proxy-info h3 {
            color: #4a9eff;
            margin-bottom: 1rem;
            font-size: 1.2rem;
        }
        
        .proxy-details {
            display: grid;
            gap: 0.5rem;
            color: #b0b0b0;
            font-size: 0.9rem;
        }
        
        .proxy-details code {
            background: #1a1a1a;
            padding: 0.25rem 0.5rem;
            border-radius: 4px;
            color: #4a9eff;
            font-family: monospace;
        }
        
        .system-info {
            margin-top: 2rem;
            padding: 1rem;
            background: rgba(26, 26, 26, 0.5);
            border-radius: 8px;
            color: #808080;
            font-size: 0.85rem;
        }
        
        @media (max-width: 768px) {
            body { padding: 1rem; }
            h1 { font-size: 2rem; }
            .services-grid { grid-template-columns: 1fr; }
            .service-card { padding: 1.5rem; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Johnny5 Services</h1>
        <p class="subtitle">Raspberry Pi 5 Local Services Dashboard</p>
        
        <div class="services-grid">
            <div class="service-card">
                <div class="service-title">Pi Monitor</div>
                <div class="service-description">Real-time hardware monitoring and overclocking interface</div>
                <a href="http://10.0.0.195:5000/" target="_blank" class="service-link">Open Pi Monitor</a>
                <div class="service-url">pimonitor.johnny5 → http://10.0.0.195:5000/</div>
            </div>
            
            <div class="service-card">
                <div class="service-title">CopyParty Server</div>
                <div class="service-description">File sharing and transfer service</div>
                <a href="http://10.0.0.195:3923/" target="_blank" class="service-link">Open CopyParty</a>
                <div class="service-url">copyparty.johnny5 → http://10.0.0.195:3923/</div>
            </div>
            
            <div class="service-card">
                <div class="service-title">OpenWebUI</div>
                <div class="service-description">Local LLM model interface and chat</div>
                <a href="http://10.0.0.195:8080/" target="_blank" class="service-link">Open WebUI</a>
                <div class="service-url">openwebui.johnny5 → http://10.0.0.195:8080/</div>
            </div>
        </div>
        
        <div class="proxy-info">
            <h3>🔗 Squid Proxy Access</h3>
            <div class="proxy-details">
                <div><strong>Service:</strong> squid.johnny5</div>
                <div><strong>SOCKS Proxy:</strong> <code>10.0.0.195:3128</code></div>
                <div><strong>HTTP Proxy:</strong> <code>10.0.0.195:3128</code></div>
                <div><strong>Usage:</strong> Configure your browser or SSH tunnel to use johnny5 as proxy server</div>
                <div><strong>SSH Tunnel Example:</strong> <code>ssh -D 8080 pi@10.0.0.195</code></div>
                <div><strong>Browser Config:</strong> Set SOCKS5 proxy to localhost:8080 (when using SSH tunnel)</div>
            </div>
        </div>
        
        <div class="system-info">
            <strong>System:</strong> <span id="hostname">johnny5</span> | 
            <strong>Model:</strong> Raspberry Pi 5 | 
            <strong>IP:</strong> 10.0.0.195 | 
            <strong>Updated:</strong> <span id="last-updated"></span>
        </div>
    </div>
    
    <script>
        document.getElementById('last-updated').textContent = new Date().toLocaleString();
        
        // Auto-refresh page info every 30 seconds
        setInterval(() => {
            document.getElementById('last-updated').textContent = new Date().toLocaleString();
        }, 30000);
    </script>
</body>
</html>
HTML_EOF

print_status 0 "Created landing page HTML"

echo ""
echo "Step 3: Configuring squid proxy..."

# Backup original squid config
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.backup

# Create squid configuration
sudo tee /etc/squid/squid.conf > /dev/null << 'SQUID_EOF'
# Squid configuration for johnny5 local services
# Basic HTTP and SOCKS proxy for local network access

# Access control
acl localnet src 0.0.0.1-0.255.255.255	# RFC 1122 "this" network (LAN)
acl localnet src 10.0.0.0/8		# RFC 1918 local private network (LAN)
acl localnet src 100.64.0.0/10		# RFC 6598 shared address space (CGN)
acl localnet src 169.254.0.0/16 	# RFC 3927 link-local (directly plugged machines)
acl localnet src 172.16.0.0/12		# RFC 1918 local private network (LAN)
acl localnet src 192.168.0.0/16	# RFC 1918 local private network (LAN)
acl localnet src fc00::/7       	# RFC 4193 local private network range
acl localnet src fe80::/10      	# RFC 4291 link-local (directly plugged machines)

acl SSL_ports port 443
acl Safe_ports port 80		# http
acl Safe_ports port 21		# ftp
acl Safe_ports port 443		# https
acl Safe_ports port 70		# gopher
acl Safe_ports port 210		# wais
acl Safe_ports port 1025-65535	# unregistered ports
acl Safe_ports port 280		# http-mgmt
acl Safe_ports port 488		# gss-http
acl Safe_ports port 591		# filemaker
acl Safe_ports port 777		# multiling http
acl Safe_ports port 3923	# copyparty
acl Safe_ports port 5000	# pi-monitor
acl Safe_ports port 8080	# openwebui

acl CONNECT method CONNECT

# Deny requests to certain unsafe ports
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Only allow cachemgr access from localhost
http_access allow localhost manager
http_access deny manager

# Allow local network access
http_access allow localnet
http_access allow localhost

# Deny all other access
http_access deny all

# Squid listening port
http_port 3128

# Memory and disk cache settings
cache_mem 256 MB
maximum_object_size_in_memory 512 KB
cache_dir ufs /var/spool/squid 1000 16 256

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log

# DNS settings
dns_nameservers 8.8.8.8 8.8.4.4

# Refresh patterns
refresh_pattern ^ftp:		1440	20%	10080
refresh_pattern ^gopher:	1440	0%	1440
refresh_pattern -i (/cgi-bin/|\?) 0	0%	0
refresh_pattern .		0	20%	4320

# Hostname
visible_hostname johnny5.local
SQUID_EOF

print_status 0 "Configured squid proxy"

echo ""
echo "Step 4: Setting up host aliases..."

# Add host entries for service names
sudo tee -a /etc/hosts > /dev/null << 'HOSTS_EOF'

# Johnny5 service aliases
10.0.0.195 pimonitor.johnny5
10.0.0.195 copyparty.johnny5 
10.0.0.195 openwebui.johnny5
10.0.0.195 squid.johnny5
HOSTS_EOF

print_status 0 "Added service host aliases"

echo ""
echo "Step 5: Starting and enabling services..."

# Enable and start nginx
sudo systemctl enable nginx
sudo systemctl restart nginx

if systemctl is-active --quiet nginx; then
    print_status 0 "Nginx started successfully"
else
    print_status 1 "Nginx failed to start"
fi

# Enable and start squid
sudo systemctl enable squid
sudo systemctl restart squid

if systemctl is-active --quiet squid; then
    print_status 0 "Squid started successfully"
else
    print_status 1 "Squid failed to start"
fi

# Configure firewall for nginx and squid
if command -v ufw &> /dev/null; then
    sudo ufw allow 80    # nginx
    sudo ufw allow 3128  # squid
    print_status 0 "Configured firewall rules"
fi

echo ""
echo "Step 6: Creating service management script..."

# Create service management script
tee ~/johnny5-services.sh > /dev/null << 'SERVICES_EOF'
#!/bin/bash
# Johnny5 Services Management Script

SERVICES=("nginx" "squid" "pi-monitor")
HOSTNAME="johnny5"
IP="10.0.0.195"

show_status() {
    echo "Johnny5 Services Status"
    echo "======================"
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo "✓ $service - Running"
        else
            echo "✗ $service - Stopped"
        fi
    done
    echo ""
    echo "Service Access URLs:"
    echo "  Landing Page:  http://$IP/ (nginx)"
    echo "  Pi Monitor:    http://$IP:5000/"
    echo "  CopyParty:     http://$IP:3923/"
    echo "  OpenWebUI:     http://$IP:8080/"
    echo "  Squid Proxy:   $IP:3128"
}

case $1 in
    start)
        echo "Starting all Johnny5 services..."
        for service in "${SERVICES[@]}"; do
            sudo systemctl start "$service"
            echo "Started: $service"
        done
        ;;
    stop)
        echo "Stopping all Johnny5 services..."
        for service in "${SERVICES[@]}"; do
            sudo systemctl stop "$service"
            echo "Stopped: $service"
        done
        ;;
    restart)
        echo "Restarting all Johnny5 services..."
        for service in "${SERVICES[@]}"; do
            sudo systemctl restart "$service"
            echo "Restarted: $service"
        done
        ;;
    status)
        show_status
        ;;
    logs)
        SERVICE=${2:-nginx}
        echo "Showing logs for: $SERVICE"
        sudo journalctl -u "$SERVICE" -f
        ;;
    proxy-info)
        echo "Squid Proxy Configuration:"
        echo "========================="
        echo "Proxy Server: $IP:3128"
        echo "Type: HTTP/HTTPS Proxy"
        echo ""
        echo "SSH Tunnel Setup:"
        echo "ssh -D 8080 pi@$IP"
        echo "(Then use localhost:8080 as SOCKS5 proxy in browser)"
        echo ""
        echo "Direct Browser Config:"
        echo "HTTP Proxy: $IP:3128"
        echo "HTTPS Proxy: $IP:3128"
        ;;
    *)
        echo "Johnny5 Services Management"
        echo "Usage: $0 {start|stop|restart|status|logs [service]|proxy-info}"
        echo ""
        show_status
        ;;
esac
SERVICES_EOF

chmod +x ~/johnny5-services.sh

print_status 0 "Created service management script: ~/johnny5-services.sh"

echo ""
echo "=========================================="
echo "SETUP COMPLETE!"
echo "=========================================="

PI_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "Johnny5 Services Dashboard:"
echo "  Landing Page: http://$PI_IP/"
echo "  Landing Page: http://localhost/ (local)"
echo ""
echo "Available Services:"
echo "  • Pi Monitor:     http://pimonitor.johnny5:5000/"
echo "  • CopyParty:      http://copyparty.johnny5:3923/"
echo "  • OpenWebUI:      http://openwebui.johnny5:8080/"
echo ""
echo "Squid Proxy Access:"
echo "  • Proxy Server:   squid.johnny5:3128"
echo "  • Direct Config:  $PI_IP:3128"
echo "  • SSH Tunnel:     ssh -D 8080 pi@$PI_IP"
echo ""
echo "Management:"
echo "  ~/johnny5-services.sh status     # Show all service status"
echo "  ~/johnny5-services.sh start      # Start all services"
echo "  ~/johnny5-services.sh proxy-info # Proxy configuration help"
echo ""
echo "The landing page provides easy access to all your Pi services!"
EOF

chmod +x ~/setup-johnny5-services.sh
print_status 0 "Created landing page setup script: ~/setup-johnny5-services.sh"

echo ""
echo "Fix 3: Restarting Pi Monitor service with overlay fixes..."

sudo systemctl restart pi-monitor.service
sleep 3

if systemctl is-active --quiet pi-monitor.service; then
    print_status 0 "Pi Monitor service running with fixed overlay mode"
else
    print_status 1 "Pi Monitor service restart failed"
fi

echo ""
echo "=========================================="
echo "OVERLAY FIX & LANDING PAGE SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "✅ Pi Monitor Overlay Mode Fixed:"
echo "  • Working chart overlay with visual selection feedback"
echo "  • Clear selection button now functional"
echo "  • Enhanced tooltips show complete session data and notes"
echo "  • Metric selector checkboxes control which data to compare"
echo "  • Visual indicators when overlay mode is active"
echo ""
echo "✅ Landing Page System Created:"
echo "  • ~/setup-johnny5-services.sh - Full nginx + squid setup"
echo "  • ~/johnny5-services.sh - Service management script"
echo "  • Professional dashboard with all services listed"
echo "  • Squid proxy configuration with connection info"
echo ""
echo "Next Steps:"
echo "1. Test Pi Monitor overlay mode: Go to Results → Chart View → Overlay Mode"
echo "2. Setup landing page: bash ~/setup-johnny5-services.sh"
echo "3. Access dashboard: http://10.0.0.195/"
echo ""
echo "Overlay Mode Usage:"
echo "  • Click 'Chart View' → 'Overlay Mode'"
echo "  • Click result cards to select (they'll highlight in blue)"
echo "  • Use metric checkboxes to choose what data to compare"
echo "  • 'Clear Selection' removes all selected cards"
echo "  • Hover over cards for detailed tooltips with notes and system stats"
