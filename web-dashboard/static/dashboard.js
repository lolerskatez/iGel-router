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
        this.setupNavigation();
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

    setupNavigation() {
        // Handle navigation between sections
        const navLinks = document.querySelectorAll('.navbar-nav .nav-link');
        const sections = document.querySelectorAll('.section-content');
        
        navLinks.forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                
                // Remove active class from all nav links
                navLinks.forEach(nl => nl.classList.remove('active'));
                
                // Add active class to clicked link
                link.classList.add('active');
                
                // Hide all sections
                sections.forEach(section => section.style.display = 'none');
                
                // Show dashboard by default or show specific section
                const href = link.getAttribute('href');
                if (href === '#configuration') {
                    document.getElementById('configuration').style.display = 'block';
                    this.loadConfiguration();
                } else {
                    // Show main dashboard content for all other sections
                    const mainContent = document.querySelector('.container-fluid .row:first-child').parentElement;
                    mainContent.querySelectorAll('.row').forEach(row => {
                        if (!row.querySelector('#configuration')) {
                            row.style.display = 'block';
                        }
                    });
                }
            });
        });
        
        // Show dashboard by default
        const dashboardLink = document.querySelector('.navbar-nav .nav-link[href="#dashboard"]');
        if (dashboardLink) {
            dashboardLink.classList.add('active');
        }
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

    async loadConfiguration() {
        try {
            const response = await fetch('/api/system/configuration');
            if (!response.ok) throw new Error('Failed to load configuration');
            
            const data = await response.json();
            if (data.success) {
                this.renderConfiguration(data.configuration);
            } else {
                throw new Error(data.message || 'Failed to load configuration');
            }
        } catch (error) {
            console.error('Error loading configuration:', error);
            document.getElementById('configuration-content').innerHTML = `
                <div class="alert alert-danger">
                    <i class="bi bi-exclamation-triangle"></i>
                    Failed to load configuration: ${error.message}
                </div>
            `;
        }
    }

    renderConfiguration(config) {
        const configContent = document.getElementById('configuration-content');
        
        // Render feature configuration
        let featuresHtml = '<div class="row">';
        
        Object.entries(config.features).forEach(([key, feature]) => {
            const statusColor = feature.enabled ? 'success' : (feature.installed ? 'warning' : 'secondary');
            const statusIcon = feature.enabled ? 'check-circle' : (feature.installed ? 'exclamation-triangle' : 'x-circle');
            
            featuresHtml += `
                <div class="col-lg-6 mb-4">
                    <div class="card h-100 ${feature.enabled ? 'border-success' : ''}">
                        <div class="card-header d-flex justify-content-between align-items-center">
                            <h6 class="mb-0">
                                <i class="bi bi-${statusIcon} text-${statusColor}"></i>
                                ${feature.name}
                            </h6>
                            <span class="badge bg-${statusColor}">${feature.status}</span>
                        </div>
                        <div class="card-body">
                            <p class="card-text text-muted mb-3">${feature.description}</p>
                            ${feature.warning ? `
                                <div class="alert alert-warning alert-sm mb-3">
                                    <i class="bi bi-exclamation-triangle"></i>
                                    <strong>Note:</strong> ${feature.warning}
                                </div>
                            ` : ''}
                            <h6 class="small text-uppercase text-muted mb-2">Benefits:</h6>
                            <ul class="list-unstyled small">
                                ${feature.benefits.map(benefit => `
                                    <li class="mb-1">
                                        <i class="bi bi-check2 text-success"></i> ${benefit}
                                    </li>
                                `).join('')}
                            </ul>
                        </div>
                    </div>
                </div>
            `;
        });
        
        featuresHtml += '</div>';
        configContent.innerHTML = featuresHtml;
        
        // Update web interface status
        this.updateWebInterfaceStatus(config.web_interfaces);
    }

    updateWebInterfaceStatus(interfaces) {
        // Update CasaOS
        const casaosStatus = document.getElementById('casaos-status');
        const casaosLink = document.getElementById('casaos-link');
        if (interfaces.casaos && interfaces.casaos.enabled) {
            casaosStatus.textContent = 'Available';
            casaosStatus.className = 'badge bg-success';
            casaosLink.style.display = 'block';
            casaosLink.onclick = () => window.open(interfaces.casaos.url, '_blank');
        } else {
            casaosStatus.textContent = 'Not Installed';
            casaosStatus.className = 'badge bg-secondary';
            casaosLink.style.display = 'none';
        }
        
        // Update Cockpit
        const cockpitStatus = document.getElementById('cockpit-status');
        const cockpitLink = document.getElementById('cockpit-link');
        if (interfaces.cockpit && interfaces.cockpit.enabled) {
            cockpitStatus.textContent = 'Available';
            cockpitStatus.className = 'badge bg-success';
            cockpitLink.style.display = 'block';
            cockpitLink.onclick = () => window.open(interfaces.cockpit.url, '_blank');
        } else {
            cockpitStatus.textContent = 'Not Installed';
            cockpitStatus.className = 'badge bg-secondary';
            cockpitLink.style.display = 'none';
        }
        
        // Update Headplane
        const headplaneStatus = document.getElementById('headplane-status');
        const headplaneLink = document.getElementById('headplane-link');
        if (interfaces.headplane && interfaces.headplane.enabled) {
            headplaneStatus.textContent = 'Available';
            headplaneStatus.className = 'badge bg-success';
            headplaneLink.style.display = 'block';
            headplaneLink.onclick = () => window.open(interfaces.headplane.url, '_blank');
        } else {
            headplaneStatus.textContent = 'Not Available';
            headplaneStatus.className = 'badge bg-secondary';
            headplaneLink.style.display = 'none';
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

function refreshConfiguration() {
    dashboard.loadConfiguration();
    dashboard.showAlert('Configuration refreshed', 'info', 2000);
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
window.refreshConfiguration = refreshConfiguration;
