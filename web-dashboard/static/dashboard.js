/**
 * IGEL M250C Router Dashboard JavaScript
 * Handles real-time updates, VPN management, and system interactions
 */

class IgelDashboard {
    constructor() {
        this.updateInterval = 30000; // 30 seconds
        this.isUpdating = false;
        this.init();
    }

    init() {
        this.startAutoUpdate();
        this.bindEvents();
        this.updateTime();
        setInterval(() => this.updateTime(), 1000);
        console.log('IGEL Dashboard initialized');
    }

    bindEvents() {
        // Bind modal events
        document.querySelectorAll('[data-bs-toggle="modal"]').forEach(element => {
            element.addEventListener('click', (e) => {
                e.preventDefault();
            });
        });
    }

    updateTime() {
        const now = new Date();
        const timeString = now.toLocaleString();
        const timeElement = document.getElementById('current-time');
        if (timeElement) {
            timeElement.textContent = timeString;
        }
    }

    startAutoUpdate() {
        this.autoUpdateTimer = setInterval(() => {
            this.refreshAllData();
        }, this.updateInterval);
    }

    stopAutoUpdate() {
        if (this.autoUpdateTimer) {
            clearInterval(this.autoUpdateTimer);
        }
    }

    async refreshAllData() {
        if (this.isUpdating) return;
        
        this.isUpdating = true;
        try {
            await Promise.all([
                this.updateSystemStatus(),
                this.updateVpnStatus()
            ]);
        } catch (error) {
            console.error('Error refreshing data:', error);
            this.showAlert('Error refreshing data', 'danger');
        } finally {
            this.isUpdating = false;
        }
    }

    async updateSystemStatus() {
        try {
            const response = await fetch('/api/system/status');
            if (!response.ok) throw new Error('Failed to fetch system status');
            
            const data = await response.json();
            
            // Update CPU usage
            const cpuElement = document.getElementById('cpu-usage');
            if (cpuElement && data.cpu_percent !== undefined) {
                cpuElement.textContent = `${data.cpu_percent.toFixed(1)}%`;
                this.updateStatColor(cpuElement, data.cpu_percent, 80, 90);
            }
            
            // Update memory usage
            const memoryElement = document.getElementById('memory-usage');
            if (memoryElement && data.memory_percent !== undefined) {
                memoryElement.textContent = `${data.memory_percent.toFixed(1)}%`;
                this.updateStatColor(memoryElement, data.memory_percent, 80, 90);
            }
            
            // Update disk usage
            const diskElement = document.getElementById('disk-usage');
            if (diskElement && data.disk_percent !== undefined) {
                diskElement.textContent = `${data.disk_percent.toFixed(1)}%`;
                this.updateStatColor(diskElement, data.disk_percent, 85, 95);
            }
            
            // Update temperature
            const tempElement = document.getElementById('temperature');
            if (tempElement && data.temperature !== undefined && data.temperature !== null) {
                tempElement.textContent = `${data.temperature.toFixed(1)}°C`;
                this.updateStatColor(tempElement, data.temperature, 70, 80);
            }
            
        } catch (error) {
            console.error('Error updating system status:', error);
        }
    }

    async updateVpnStatus() {
        try {
            const [tailscaleResponse, headscaleResponse] = await Promise.all([
                fetch('/api/tailscale/status'),
                fetch('/api/headscale/status')
            ]);
            
            if (tailscaleResponse.ok) {
                const tailscaleData = await tailscaleResponse.json();
                this.updateTailscaleDisplay(tailscaleData);
            }
            
            if (headscaleResponse.ok) {
                const headscaleData = await headscaleResponse.json();
                this.updateHeadscaleDisplay(headscaleData);
            }
            
        } catch (error) {
            console.error('Error updating VPN status:', error);
        }
    }

    updateTailscaleDisplay(data) {
        // This would update the Tailscale status in the UI
        // Implementation depends on the specific UI elements
        console.log('Tailscale status:', data);
    }

    updateHeadscaleDisplay(data) {
        // This would update the Headscale status in the UI
        console.log('Headscale status:', data);
    }

    updateStatColor(element, value, warningThreshold, dangerThreshold) {
        element.classList.remove('text-success', 'text-warning', 'text-danger');
        
        if (value >= dangerThreshold) {
            element.classList.add('text-danger');
        } else if (value >= warningThreshold) {
            element.classList.add('text-warning');
        } else {
            element.classList.add('text-success');
        }
    }

    showAlert(message, type = 'info', duration = 5000) {
        const alertContainer = document.getElementById('alert-container') || this.createAlertContainer();
        
        const alertElement = document.createElement('div');
        alertElement.className = `alert alert-${type} alert-dismissible fade show`;
        alertElement.innerHTML = `
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        
        alertContainer.appendChild(alertElement);
        
        // Auto-dismiss after duration
        setTimeout(() => {
            if (alertElement.parentNode) {
                alertElement.parentNode.removeChild(alertElement);
            }
        }, duration);
    }

    createAlertContainer() {
        const container = document.createElement('div');
        container.id = 'alert-container';
        container.className = 'position-fixed top-0 end-0 p-3';
        container.style.zIndex = '1050';
        document.body.appendChild(container);
        return container;
    }

    async makeApiCall(endpoint, method = 'GET', data = null) {
        const options = {
            method,
            headers: {
                'Content-Type': 'application/json',
            }
        };
        
        if (data) {
            options.body = JSON.stringify(data);
        }
        
        try {
            const response = await fetch(endpoint, options);
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            return await response.json();
        } catch (error) {
            console.error(`API call failed: ${endpoint}`, error);
            throw error;
        }
    }
}

// VPN Management Functions
async function toggleExitNode() {
    try {
        const button = event.target;
        const originalText = button.innerHTML;
        
        button.disabled = true;
        button.innerHTML = '<i class="bi bi-spinner spinner-border spinner-border-sm"></i> Processing...';
        
        const response = await fetch('/api/tailscale/toggle-exit-node', {
            method: 'POST'
        });
        
        if (response.ok) {
            const result = await response.json();
            dashboard.showAlert(result.message, 'success');
            // Refresh VPN status
            dashboard.updateVpnStatus();
        } else {
            const error = await response.json();
            dashboard.showAlert(error.message || 'Failed to toggle exit node', 'danger');
        }
    } catch (error) {
        console.error('Error toggling exit node:', error);
        dashboard.showAlert('Error toggling exit node', 'danger');
    } finally {
        const button = event.target;
        button.disabled = false;
        button.innerHTML = '<i class="bi bi-arrow-through-heart"></i> Toggle Exit Node';
    }
}

function showRouteManager() {
    const modal = new bootstrap.Modal(document.getElementById('routeModal'));
    
    // Load current routes
    fetch('/api/tailscale/routes')
        .then(response => response.json())
        .then(data => {
            const routeInput = document.getElementById('routeInput');
            if (data.routes) {
                routeInput.value = data.routes.join(',');
            }
        })
        .catch(error => {
            console.error('Error loading routes:', error);
        });
    
    modal.show();
}

async function updateRoutes() {
    const routeInput = document.getElementById('routeInput');
    const routes = routeInput.value.split(',').map(r => r.trim()).filter(r => r);
    
    try {
        const response = await fetch('/api/tailscale/routes', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ routes })
        });
        
        if (response.ok) {
            const result = await response.json();
            dashboard.showAlert(result.message, 'success');
            bootstrap.Modal.getInstance(document.getElementById('routeModal')).hide();
            dashboard.updateVpnStatus();
        } else {
            const error = await response.json();
            dashboard.showAlert(error.message || 'Failed to update routes', 'danger');
        }
    } catch (error) {
        console.error('Error updating routes:', error);
        dashboard.showAlert('Error updating routes', 'danger');
    }
}

function showKeyManager() {
    const modal = new bootstrap.Modal(document.getElementById('keyModal'));
    
    // Load current key status
    fetch('/api/tailscale/key-status')
        .then(response => response.json())
        .then(data => {
            const keyStatus = document.getElementById('keyStatus');
            keyStatus.innerHTML = `
                <div class="row">
                    <div class="col-6">
                        <strong>Machine Key:</strong>
                    </div>
                    <div class="col-6">
                        ${data.has_key ? '<span class="badge bg-success">Active</span>' : '<span class="badge bg-danger">Missing</span>'}
                    </div>
                </div>
                <div class="row mt-2">
                    <div class="col-6">
                        <strong>Auth Status:</strong>
                    </div>
                    <div class="col-6">
                        <span class="badge bg-${data.authenticated ? 'success' : 'warning'}">${data.authenticated ? 'Authenticated' : 'Pending'}</span>
                    </div>
                </div>
            `;
        })
        .catch(error => {
            console.error('Error loading key status:', error);
            document.getElementById('keyStatus').innerHTML = '<span class="text-danger">Error loading status</span>';
        });
    
    modal.show();
}

async function generatePreAuthKey() {
    try {
        const response = await fetch('/api/headscale/generate-key', {
            method: 'POST'
        });
        
        if (response.ok) {
            const result = await response.json();
            dashboard.showAlert(`Pre-auth key generated: ${result.key}`, 'success', 10000);
        } else {
            const error = await response.json();
            dashboard.showAlert(error.message || 'Failed to generate key', 'danger');
        }
    } catch (error) {
        console.error('Error generating pre-auth key:', error);
        dashboard.showAlert('Error generating pre-auth key', 'danger');
    }
}

async function rotateKey() {
    if (!confirm('Are you sure you want to rotate the machine key? This will require re-authentication.')) {
        return;
    }
    
    try {
        const response = await fetch('/api/tailscale/rotate-key', {
            method: 'POST'
        });
        
        if (response.ok) {
            const result = await response.json();
            dashboard.showAlert(result.message, 'success');
            dashboard.updateVpnStatus();
        } else {
            const error = await response.json();
            dashboard.showAlert(error.message || 'Failed to rotate key', 'danger');
        }
    } catch (error) {
        console.error('Error rotating key:', error);
        dashboard.showAlert('Error rotating key', 'danger');
    }
}

function refreshVpnStatus() {
    dashboard.updateVpnStatus();
    dashboard.showAlert('VPN status refreshed', 'info', 2000);
}

function refreshStatus() {
    dashboard.refreshAllData();
    dashboard.showAlert('Status refreshed', 'info', 2000);
}

// Initialize dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    window.dashboard = new IgelDashboard();
});

// Export for global access
window.toggleExitNode = toggleExitNode;
window.showRouteManager = showRouteManager;
window.showKeyManager = showKeyManager;
window.updateRoutes = updateRoutes;
window.generatePreAuthKey = generatePreAuthKey;
window.rotateKey = rotateKey;
window.refreshVpnStatus = refreshVpnStatus;
window.refreshStatus = refreshStatus;
