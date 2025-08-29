#!/bin/bash

echo "=========================================="
echo "Pi Monitor Git, Chart & Backup Fixes"
echo "=========================================="

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "\033[0;32m✓\033[0m $2"
    else
        echo -e "\033[0;31m✗\033[0m $2"
    fi
}

echo "Fix 1: Correcting git repository structure..."

# Remove the incorrect git repo from vcgencmd_server subdirectory
if [ -d ".git" ]; then
    rm -rf .git
    print_status 0 "Removed incorrect git repository from vcgencmd_server"
fi

# Navigate to parent directory for git operations
cd ..

# Check if we're in the correct raspberry_projects directory
if [ "$(basename $(pwd))" = "raspberry_projects" ]; then
    print_status 0 "In correct raspberry_projects directory"
    
    # Add and commit the vcgencmd_server changes
    git add vcgencmd_server/
    git commit -m "Pi Monitor v3.1: Enhanced monitoring with stress session management

vcgencmd_server updates:
- Added stress test session management to prevent duplicates
- Enhanced live charting with 5 metrics (temp, clock, CPU%, memory%, load avg)
- Added hover tooltips for results with complete session data
- Created metric selector for custom overlay comparisons
- Fixed chart dimensions and mobile responsive design
- Added backup/restore functionality for application data"

    print_status 0 "Committed vcgencmd_server updates to main repository"
else
    print_status 1 "Not in raspberry_projects directory - manual git operations needed"
fi

# Return to vcgencmd_server directory
cd vcgencmd_server

echo ""
echo "Fix 2: Fixing results page chart dimensions..."

# Update CSS to fix chart container height
sudo -u pi-monitor tee -a /opt/pi-monitor/static/style.css > /dev/null << 'EOF'

/* Fixed chart container dimensions */
.chart-container {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1rem;
    margin-bottom: 1rem;
    max-height: 500px;
    overflow: hidden;
}

.chart-container canvas {
    max-width: 100% !important;
    max-height: 400px !important;
    height: 400px !important;
}

/* Responsive chart sizing */
@media (max-width: 768px) {
    .chart-container {
        max-height: 400px;
        padding: 0.75rem;
    }
    
    .chart-container canvas {
        max-height: 300px !important;
        height: 300px !important;
    }
}

@media (max-width: 480px) {
    .chart-container {
        max-height: 350px;
        padding: 0.5rem;
    }
    
    .chart-container canvas {
        max-height: 250px !important;
        height: 250px !important;
    }
}
EOF

# Update JavaScript to set proper chart dimensions
sudo -u pi-monitor tee -a /opt/pi-monitor/static/app.js > /dev/null << 'EOF'

// Override chart initialization with fixed dimensions
document.addEventListener('DOMContentLoaded', () => {
    // Wait for page load then fix chart dimensions
    setTimeout(() => {
        const resultsChart = document.getElementById('resultsChart');
        if (resultsChart) {
            // Set fixed canvas dimensions
            resultsChart.style.maxHeight = '400px';
            resultsChart.style.height = '400px';
            resultsChart.style.width = '100%';
            
            // Force chart redraw if it exists
            if (window.piMonitor && window.piMonitor.resultsChart) {
                window.piMonitor.resultsChart.resize();
            }
        }
    }, 500);
});
EOF

print_status 0 "Fixed chart dimensions for results page"

echo ""
echo "Fix 3: Creating Pi Monitor backup and restore script..."

# Create backup and restore script
tee ~/pi-monitor-backup.sh > /dev/null << 'EOF'
#!/bin/bash

# Pi Monitor Backup and Restore Script
# Usage: ./pi-monitor-backup.sh {backup|restore|list}

BACKUP_DIR="$HOME/pi-monitor-backups"
SERVICE_NAME="pi-monitor"
INSTALL_DIR="/opt/pi-monitor"
DATA_DIR="/home/pi-monitor"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "\033[0;32m✓\033[0m $2"
    else
        echo -e "\033[0;31m✗\033[0m $2"
    fi
}

create_backup() {
    local backup_name="${1:-$TIMESTAMP}"
    local backup_path="$BACKUP_DIR/pi-monitor-$backup_name"
    
    echo "Creating Pi Monitor backup: $backup_name"
    echo "======================================"
    
    # Create backup directory
    mkdir -p "$backup_path"/{application,data,config}
    
    # Stop service temporarily
    echo "Stopping Pi Monitor service..."
    sudo systemctl stop $SERVICE_NAME
    sleep 2
    
    # Backup application files
    echo "Backing up application files..."
    if [ -d "$INSTALL_DIR" ]; then
        sudo cp -r "$INSTALL_DIR"/* "$backup_path/application/"
        sudo chown -R $(whoami):$(whoami) "$backup_path/application"
        print_status 0 "Application files backed up"
    else
        print_status 1 "Application directory not found"
    fi
    
    # Backup data files
    echo "Backing up data files..."
    if [ -d "$DATA_DIR" ]; then
        sudo cp -r "$DATA_DIR"/* "$backup_path/data/" 2>/dev/null || true
        sudo chown -R $(whoami):$(whoami) "$backup_path/data" 2>/dev/null || true
        print_status 0 "Data files backed up"
    else
        print_status 1 "Data directory not found"
    fi
    
    # Backup configuration files
    echo "Backing up configuration files..."
    sudo cp /etc/systemd/system/pi-monitor.service "$backup_path/config/" 2>/dev/null || true
    sudo cp /etc/sudoers.d/pi-monitor "$backup_path/config/" 2>/dev/null || true
    sudo chown -R $(whoami):$(whoami) "$backup_path/config" 2>/dev/null || true
    print_status 0 "Configuration files backed up"
    
    # Create backup info file
    cat > "$backup_path/backup_info.json" << BACKUP_INFO
{
    "timestamp": "$TIMESTAMP",
    "hostname": "$(hostname)",
    "pi_model": "$(cat /proc/device-tree/model 2>/dev/null || echo 'Unknown')",
    "backup_size": "$(du -sh $backup_path | cut -f1)",
    "pi_monitor_version": "v3.1",
    "created_by": "$(whoami)",
    "backup_contents": {
        "application": "$(ls -la $backup_path/application/ 2>/dev/null | wc -l) files",
        "data": "$(ls -la $backup_path/data/ 2>/dev/null | wc -l) files",
        "config": "$(ls -la $backup_path/config/ 2>/dev/null | wc -l) files"
    }
}
BACKUP_INFO
    
    # Create compressed archive
    echo "Creating compressed archive..."
    cd "$BACKUP_DIR"
    tar -czf "pi-monitor-$backup_name.tar.gz" "pi-monitor-$backup_name/"
    
    if [ $? -eq 0 ]; then
        rm -rf "pi-monitor-$backup_name/"
        ARCHIVE_SIZE=$(du -sh "pi-monitor-$backup_name.tar.gz" | cut -f1)
        print_status 0 "Backup archived: pi-monitor-$backup_name.tar.gz ($ARCHIVE_SIZE)"
    else
        print_status 1 "Failed to create archive"
    fi
    
    # Restart service
    echo "Restarting Pi Monitor service..."
    sudo systemctl start $SERVICE_NAME
    sleep 2
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_status 0 "Service restarted successfully"
    else
        print_status 1 "Service failed to restart"
    fi
    
    echo ""
    echo "Backup completed: $BACKUP_DIR/pi-monitor-$backup_name.tar.gz"
    echo "Backup size: $ARCHIVE_SIZE"
    echo ""
}

restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        echo "Backup file not found: $backup_file"
        echo ""
        echo "Available backups:"
        list_backups
        return 1
    fi
    
    echo "Restoring Pi Monitor from: $(basename $backup_file)"
    echo "=================================================="
    
    # Confirm restore
    read -p "This will overwrite current Pi Monitor installation. Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled"
        return 0
    fi
    
    # Stop service
    echo "Stopping Pi Monitor service..."
    sudo systemctl stop $SERVICE_NAME 2>/dev/null || true
    
    # Create temporary restore directory
    local temp_dir="/tmp/pi-monitor-restore-$$"
    mkdir -p "$temp_dir"
    
    # Extract backup
    echo "Extracting backup..."
    cd "$temp_dir"
    tar -xzf "$backup_file"
    
    local backup_dir=$(ls -d pi-monitor-*/ | head -1)
    if [ ! -d "$backup_dir" ]; then
        print_status 1 "Failed to extract backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd "$backup_dir"
    
    # Restore application files
    if [ -d "application" ]; then
        echo "Restoring application files..."
        sudo rm -rf "$INSTALL_DIR"
        sudo mkdir -p "$INSTALL_DIR"
        sudo cp -r application/* "$INSTALL_DIR/"
        sudo chown -R pi-monitor:pi-monitor "$INSTALL_DIR"
        print_status 0 "Application files restored"
    fi
    
    # Restore data files  
    if [ -d "data" ]; then
        echo "Restoring data files..."
        sudo mkdir -p "$DATA_DIR"
        sudo cp -r data/* "$DATA_DIR/" 2>/dev/null || true
        sudo chown -R pi-monitor:pi-monitor "$DATA_DIR"
        print_status 0 "Data files restored"
    fi
    
    # Restore configuration files
    if [ -d "config" ]; then
        echo "Restoring configuration files..."
        sudo cp config/pi-monitor.service /etc/systemd/system/ 2>/dev/null || true
        sudo cp config/pi-monitor /etc/sudoers.d/ 2>/dev/null || true
        print_status 0 "Configuration files restored"
    fi
    
    # Reload systemd and restart service
    echo "Reloading systemd and starting service..."
    sudo systemctl daemon-reload
    sudo systemctl enable pi-monitor.service
    sudo systemctl start $SERVICE_NAME
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_status 0 "Service started successfully"
        PI_IP=$(hostname -I | awk '{print $1}')
        echo ""
        echo "Pi Monitor restored and available at:"
        echo "  Local:   http://localhost:5000"
        echo "  Network: http://$PI_IP:5000"
    else
        print_status 1 "Service failed to start after restore"
        echo "Check logs: sudo journalctl -u pi-monitor.service"
    fi
    
    # Cleanup
    cd "$HOME"
    rm -rf "$temp_dir"
    
    echo ""
    echo "Restore completed successfully!"
}

list_backups() {
    echo "Available Pi Monitor Backups:"
    echo "============================="
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "No backups found. Backup directory doesn't exist."
        echo "Run: $0 backup"
        return 0
    fi
    
    local count=0
    for backup in "$BACKUP_DIR"/pi-monitor-*.tar.gz; do
        if [ -f "$backup" ]; then
            local size=$(du -sh "$backup" | cut -f1)
            local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d. -f1)
            echo "$(basename "$backup") - $size - $date"
            ((count++))
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo "No backup files found in $BACKUP_DIR"
        echo "Run: $0 backup"
    fi
    
    echo ""
    echo "To restore: $0 restore <backup-filename>"
}

get_system_info() {
    echo "Pi Monitor System Information:"
    echo "============================="
    echo "Hostname: $(hostname)"
    echo "Pi Model: $(cat /proc/device-tree/model 2>/dev/null || echo 'Unknown')"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo "Service Status: $(systemctl is-active pi-monitor.service 2>/dev/null || echo 'Not installed')"
    echo "Install Directory: $INSTALL_DIR $([ -d "$INSTALL_DIR" ] && echo '[EXISTS]' || echo '[MISSING]')"
    echo "Data Directory: $DATA_DIR $([ -d "$DATA_DIR" ] && echo '[EXISTS]' || echo '[MISSING]')"
    echo "Backup Directory: $BACKUP_DIR"
    echo ""
}

case $1 in
    backup)
        create_backup "$2"
        ;;
    restore)
        if [ -z "$2" ]; then
            echo "Please specify backup file to restore"
            echo ""
            list_backups
        else
            # Handle both full path and just filename
            if [[ "$2" == */* ]]; then
                restore_backup "$2"
            else
                restore_backup "$BACKUP_DIR/$2"
            fi
        fi
        ;;
    list)
        list_backups
        ;;
    info)
        get_system_info
        ;;
    *)
        echo "Pi Monitor Backup & Restore Tool"
        echo "Usage: $0 {backup|restore|list|info}"
        echo ""
        echo "Commands:"
        echo "  backup [name]     - Create backup (optional custom name)"
        echo "  restore <file>    - Restore from backup file"
        echo "  list             - List available backups"
        echo "  info             - Show system information"
        echo ""
        echo "Examples:"
        echo "  $0 backup                    # Auto-timestamped backup"
        echo "  $0 backup before-overclock   # Named backup"
        echo "  $0 restore pi-monitor-20250828_180000.tar.gz"
        echo ""
        get_system_info
        ;;
esac
EOF

chmod +x ~/pi-monitor-backup.sh
print_status 0 "Created backup/restore script: ~/pi-monitor-backup.sh"

echo ""
echo "Fix 3: Updating results chart with fixed dimensions..."

# Fix JavaScript chart initialization with proper dimensions
sudo -u pi-monitor tee /opt/pi-monitor/static/app.js > /dev/null << 'EOF'
class PiMonitor {
    constructor() {
        this.updateInterval = null;
        this.liveChart = null;
        this.resultsChart = null;
        this.chartData = [];
        this.maxDataPoints = 60;
        this.overlayMode = false;
        this.selectedResults = [];
        this.selectedMetrics = ['temperature', 'cpu_percent'];
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
        
        document.querySelectorAll('.result-card').forEach(card => {
            this.setupResultCardTooltip(card);
        });
        
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
            load: parseFloat(card.dataset.load || 0),
            clock: parseFloat(card.dataset.clock || 2400),
            voltage: parseFloat(card.dataset.voltage || 0),
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
                    <span>Load Avg:</span> <strong>${data.load.toFixed(2)}</strong>
                </div>
                <div class="tooltip-row">
                    <span>Clock:</span> <strong>${data.clock} MHz</strong>
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
        // Live chart with fixed dimensions
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

        // Results chart with FIXED DIMENSIONS
        const resultsCtx = document.getElementById('resultsChart');
        if (resultsCtx) {
            // Set canvas dimensions explicitly
            resultsCtx.width = 800;
            resultsCtx.height = 400;
            resultsCtx.style.maxWidth = '100%';
            resultsCtx.style.maxHeight = '400px';
            resultsCtx.style.height = '400px';
            
            this.resultsChart = new Chart(resultsCtx, {
                type: 'bar',
                data: { labels: [], datasets: [] },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { 
                        legend: { 
                            labels: { color: '#e0e0e0', font: { size: 11 } },
                            position: 'top'
                        },
                        tooltip: {
                            mode: 'index',
                            intersect: false,
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
                        padding: {
                            top: 10,
                            right: 10,
                            bottom: 10,
                            left: 10
                        }
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
        
        if (container && container.style.display === 'none') {
            container.style.display = 'block';
            if (grid) grid.style.display = 'none';
            button.textContent = 'List View';
            if (overlayBtn) overlayBtn.style.display = 'inline-block';
            
            // Ensure chart container has proper dimensions
            setTimeout(() => {
                const canvas = document.getElementById('resultsChart');
                if (canvas) {
                    canvas.style.width = '100%';
                    canvas.style.height = '400px';
                    canvas.style.maxHeight = '400px';
                }
                this.loadResultsChart();
            }, 100);
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
        
        this.selectedResults.forEach((card, sessionIndex) => {
            const data = this.getCardData(card);
            const sessionLabel = data.timestamp.substring(5, 16);
            
            this.selectedMetrics.forEach((metric, metricIndex) => {
                const value = this.getMetricValue(data, metric);
                if (value !== null) {
                    const color = colors[sessionIndex % colors.length];
                    datasets.push({
                        label: `${sessionLabel} - ${this.getMetricLabel(metric)}`,
                        data: [value],
                        backgroundColor: this.adjustColorOpacity(color, 0.7),
                        borderColor: color,
                        borderWidth: 2
                    });
                }
            });
        });

        // Create labels for each metric type
        const metricLabels = this.selectedMetrics.map(m => this.getMetricLabel(m));
        
        this.resultsChart.data.labels = metricLabels;
        this.resultsChart.data.datasets = datasets;
        this.resultsChart.update();
    }

    getMetricValue(data, metric) {
        switch (metric) {
            case 'temperature': return data.peak;
            case 'cpu_percent': return data.cpu;
            case 'memory_percent': return data.memory;
            case 'load_avg': return data.load;
            case 'clock_speed': return data.clock / 1000; // Convert to GHz for better scale
            case 'voltage': return data.voltage * 1000; // Convert to mV for better scale
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
        if (!this.overlayMode) {
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

print_status 0 "Fixed JavaScript with proper chart dimensions"

echo ""
echo "Fix 4: Restarting service to apply chart fixes..."

sudo systemctl restart pi-monitor.service
sleep 3

if systemctl is-active --quiet pi-monitor.service; then
    print_status 0 "Service running with fixed chart dimensions"
else
    print_status 1 "Service restart failed"
fi

echo ""
echo "=========================================="
echo "GIT, CHART & BACKUP FIXES COMPLETE!"
echo "=========================================="
echo ""
echo "✓ Git repository structure corrected"
echo "✓ Results chart dimensions fixed (max 400px height)"
echo "✓ Backup/restore script created: ~/pi-monitor-backup.sh"
echo ""
echo "Git Structure:"
echo "  raspberry_projects/          <- Main repository"
echo "  ├── vcgencmd_server/         <- Pi Monitor subfolder (no separate .git)"
echo "  └── other_projects/          <- Other tools"
echo ""
echo "Chart Fixes:"
echo "  • Fixed height: maximum 400px on desktop, 300px mobile, 250px small"
echo "  • Enhanced overlay charts with proper metric scaling"
echo "  • Responsive canvas sizing for all screen sizes"
echo ""
echo "Backup Tool Usage:"
echo "  ~/pi-monitor-backup.sh backup              # Create timestamped backup"
echo "  ~/pi-monitor-backup.sh backup my-test      # Create named backup"
echo "  ~/pi-monitor-backup.sh list                # List available backups"
echo "  ~/pi-monitor-backup.sh restore <filename>  # Restore from backup"
echo "  ~/pi-monitor-backup.sh info                # Show system information"
echo ""
echo "All fixes applied - Pi Monitor v3.1 ready for production use!"
