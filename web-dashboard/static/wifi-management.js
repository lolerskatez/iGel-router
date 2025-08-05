$(document).ready(function() {
    // WiFi management functionality
    $('#wifiTab').on('click', function() {
        refreshWifiInterfaces();
    });

    // Scan for WiFi networks
    $('#scanWifi').on('click', function() {
        const interface = $('#wifiInterface').val();
        $(this).prop('disabled', true).html('<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Scanning...');
        
        $.ajax({
            url: `/api/wifi/scan?interface=${interface}`,
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    displayWifiNetworks(response.networks);
                } else {
                    showAlert('danger', `Failed to scan: ${response.error}`);
                }
            },
            error: function(xhr) {
                showAlert('danger', 'Error scanning WiFi networks');
            },
            complete: function() {
                $('#scanWifi').prop('disabled', false).text('Scan Networks');
            }
        });
    });
    
    // Connect to WiFi network
    $('#wifiNetworksList').on('click', '.connect-wifi', function() {
        const ssid = $(this).data('ssid');
        const security = $(this).data('security');
        
        // Populate the connection modal
        $('#connectSsid').val(ssid);
        $('#connectSsid').prop('readonly', true);
        $('#wifiPassword').val('').prop('required', security !== 'OPEN');
        $('#wifiConnectionModal').modal('show');
    });
    
    $('#wifiConnectForm').on('submit', function(e) {
        e.preventDefault();
        
        const interface = $('#wifiInterface').val();
        const ssid = $('#connectSsid').val();
        const password = $('#wifiPassword').val();
        const hidden = $('#hiddenNetwork').is(':checked') ? 'yes' : 'no';
        
        $('#connectWifiBtn').prop('disabled', true).html('<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Connecting...');
        
        $.ajax({
            url: '/api/wifi/connect',
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify({
                interface: interface,
                ssid: ssid,
                password: password,
                hidden: hidden
            }),
            success: function(response) {
                if (response.success) {
                    $('#wifiConnectionModal').modal('hide');
                    showAlert('success', `Connected to ${ssid}`);
                    setTimeout(refreshWifiStatus, 2000);
                } else {
                    showAlert('danger', `Connection failed: ${response.error}`);
                }
            },
            error: function(xhr) {
                showAlert('danger', 'Error connecting to network');
            },
            complete: function() {
                $('#connectWifiBtn').prop('disabled', false).text('Connect');
            }
        });
    });
    
    // AP Mode Controls
    $('#startApBtn').on('click', function() {
        $('#apInterface').val($('#wifiInterface').val());
        $('#apModal').modal('show');
    });
    
    $('#apForm').on('submit', function(e) {
        e.preventDefault();
        
        const interface = $('#apInterface').val();
        const ssid = $('#apSsid').val();
        const password = $('#apPassword').val();
        const channel = $('#apChannel').val();
        
        $('#startApSubmitBtn').prop('disabled', true).html('<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Starting...');
        
        $.ajax({
            url: '/api/wifi/ap/start',
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify({
                interface: interface,
                ssid: ssid,
                password: password,
                channel: channel
            }),
            success: function(response) {
                if (response.success) {
                    $('#apModal').modal('hide');
                    showAlert('success', `Started access point ${ssid}`);
                    setTimeout(refreshWifiInterfaces, 2000);
                } else {
                    showAlert('danger', `Failed to start AP: ${response.error}`);
                }
            },
            error: function(xhr) {
                showAlert('danger', 'Error starting access point');
            },
            complete: function() {
                $('#startApSubmitBtn').prop('disabled', false).text('Start Access Point');
            }
        });
    });
    
    // Stop AP
    $('#stopApBtn').on('click', function() {
        const interface = $('#wifiInterface').val();
        
        if (confirm(`Are you sure you want to stop the access point on ${interface}?`)) {
            $(this).prop('disabled', true).html('<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Stopping...');
            
            $.ajax({
                url: '/api/wifi/ap/stop',
                method: 'POST',
                contentType: 'application/json',
                data: JSON.stringify({
                    interface: interface
                }),
                success: function(response) {
                    if (response.success) {
                        showAlert('success', 'Access point stopped');
                        setTimeout(refreshWifiInterfaces, 2000);
                    } else {
                        showAlert('danger', `Failed to stop AP: ${response.error}`);
                    }
                },
                error: function(xhr) {
                    showAlert('danger', 'Error stopping access point');
                },
                complete: function() {
                    $('#stopApBtn').prop('disabled', false).text('Stop Access Point');
                }
            });
        }
    });
    
    // Gateway Mode (Coffee Shop)
    $('#gatewayModeBtn').on('click', function() {
        $('#gatewayInterface').val($('#wifiInterface').val());
        $('#gatewayModal').modal('show');
    });
    
    $('#gatewayForm').on('submit', function(e) {
        e.preventDefault();
        
        const interface = $('#gatewayInterface').val();
        const ssid = $('#gatewaySsid').val();
        const password = $('#gatewayPassword').val();
        
        $('#gatewaySubmitBtn').prop('disabled', true).html('<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Setting up...');
        
        $.ajax({
            url: '/api/wifi/gateway',
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify({
                interface: interface,
                ssid: ssid,
                password: password
            }),
            success: function(response) {
                if (response.success) {
                    $('#gatewayModal').modal('hide');
                    showAlert('success', `Gateway mode enabled, connected to ${ssid}`);
                    setTimeout(refreshWifiInterfaces, 2000);
                } else {
                    showAlert('danger', `Failed to set up gateway: ${response.error}`);
                }
            },
            error: function(xhr) {
                showAlert('danger', 'Error setting up gateway mode');
            },
            complete: function() {
                $('#gatewaySubmitBtn').prop('disabled', false).text('Enable Gateway Mode');
            }
        });
    });
    
    // Interface selection change
    $('#wifiInterface').on('change', function() {
        refreshWifiStatus();
    });
    
    // Function to refresh WiFi interfaces
    function refreshWifiInterfaces() {
        $.ajax({
            url: '/api/wifi/interfaces',
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    populateInterfaceDropdown(response.interfaces);
                    refreshWifiStatus();
                }
            },
            error: function(xhr) {
                showAlert('danger', 'Error getting network interfaces');
            }
        });
    }
    
    // Function to get WiFi status
    function refreshWifiStatus() {
        const interface = $('#wifiInterface').val();
        if (!interface) return;
        
        $.ajax({
            url: `/api/wifi/status?interface=${interface}`,
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    updateWifiStatusDisplay(response.status);
                }
            }
        });
    }
    
    // Function to populate interface dropdown
    function populateInterfaceDropdown(interfaces) {
        const dropdown = $('#wifiInterface');
        dropdown.empty();
        
        // Filter to only include wireless interfaces
        const wirelessInterfaces = interfaces.filter(iface => iface.type === 'wireless');
        
        if (wirelessInterfaces.length === 0) {
            dropdown.append($('<option>').text('No wireless interfaces found'));
            $('#wifiControls').hide();
            $('#noWifiInterfaces').show();
        } else {
            wirelessInterfaces.forEach(function(iface) {
                dropdown.append(
                    $('<option>')
                        .val(iface.interface)
                        .text(`${iface.interface} (${iface.status === 'up' ? 'Active' : 'Down'}${iface.ip ? ' - ' + iface.ip : ''})`)
                );
            });
            $('#wifiControls').show();
            $('#noWifiInterfaces').hide();
        }
    }
    
    // Function to update WiFi status display
    function updateWifiStatusDisplay(status) {
        if (status.status === 'connected') {
            $('#currentConnection').html(`
                <div class="alert alert-success">
                    <h5>Connected to: ${status.ssid}</h5>
                    <p><strong>IP Address:</strong> ${status.ip || 'Not assigned'}<br>
                    <strong>Signal:</strong> ${status.signal ? status.signal + ' dBm' : 'Unknown'}</p>
                </div>
            `);
            $('#apControls').show();
        } else {
            $('#currentConnection').html(`
                <div class="alert alert-warning">
                    <h5>Not connected</h5>
                    <p>Scan for networks to connect</p>
                </div>
            `);
            $('#apControls').hide();
        }
    }
    
    // Function to display WiFi networks
    function displayWifiNetworks(networks) {
        const list = $('#wifiNetworksList');
        list.empty();
        
        if (networks.length === 0) {
            list.html('<div class="alert alert-info">No networks found</div>');
            return;
        }
        
        networks.forEach(function(network) {
            const signalStrength = network.signal >= 70 ? 'Excellent' :
                                 network.signal >= 50 ? 'Good' :
                                 network.signal >= 30 ? 'Fair' : 'Poor';
            
            const signalClass = network.signal >= 70 ? 'success' :
                              network.signal >= 50 ? 'info' :
                              network.signal >= 30 ? 'warning' : 'danger';
            
            list.append(`
                <div class="card mb-2">
                    <div class="card-body">
                        <div class="row">
                            <div class="col-md-8">
                                <h5 class="card-title">${escapeHtml(network.ssid)}</h5>
                                <p class="card-text">
                                    <span class="badge bg-${signalClass}">${signalStrength} (${network.signal}%)</span>
                                    <span class="badge bg-secondary">${network.security}</span>
                                </p>
                            </div>
                            <div class="col-md-4 text-end">
                                <button class="btn btn-primary connect-wifi" data-ssid="${escapeHtml(network.ssid)}" data-security="${network.security}">
                                    Connect
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            `);
        });
    }
    
    // Utility function to escape HTML
    function escapeHtml(unsafe) {
        return unsafe
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
    }
    
    // Show alert message
    function showAlert(type, message) {
        const alert = $(`<div class="alert alert-${type} alert-dismissible fade show" role="alert">
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
        </div>`);
        
        $('#alertContainer').append(alert);
        setTimeout(function() {
            alert.alert('close');
        }, 5000);
    }
});
