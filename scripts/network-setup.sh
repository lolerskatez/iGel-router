#!/bin/bash

# Network Interface Configuration Script for IGEL M250C
# Detects and configures network interfaces with proper priorities

set -euo pipefail

LOG_FILE="/var/log/igel-network-setup.log"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Detect network interfaces
detect_interfaces() {
    log "=== Detecting Network Interfaces ==="
    
    # Ethernet interfaces
    local ethernet_interfaces=($(ip link show | grep -E "^[0-9]+: (eth|enp|eno)" | cut -d: -f2 | tr -d ' '))
    log "Ethernet interfaces: ${ethernet_interfaces[*]:-none}"
    
    # Wireless interfaces
    local wireless_interfaces=($(ip link show | grep -E "^[0-9]+: (wlan|wlp)" | cut -d: -f2 | tr -d ' '))
    log "Wireless interfaces: ${wireless_interfaces[*]:-none}"
    
    # USB interfaces (often appear as ethernet or cellular)
    local usb_interfaces=($(ip link show | grep -E "^[0-9]+: (usb|wwp|wwan)" | cut -d: -f2 | tr -d ' '))
    log "USB/Cellular interfaces: ${usb_interfaces[*]:-none}"
    
    # Check for Realtek RTL8111G (IGEL M250C ethernet)
    if lspci | grep -q "RTL8111"; then
        log "✓ Found IGEL M250C built-in Realtek Ethernet"
    fi
    
    # Detect USB dongles by vendor
    if lsusb | grep -i "huawei\|zte\|sierra\|novatel\|qualcomm"; then
        log "✓ Found cellular USB dongle"
        # Check for modem manager
        if ! systemctl is-active --quiet ModemManager; then
            log_warning "ModemManager not active - cellular connectivity may not work"
        fi
    fi
    
    # Show interface statistics
    for iface in $(ip link show | grep "^[0-9]" | cut -d: -f2 | tr -d ' '); do
        if [[ "$iface" != "lo" ]]; then
            local status=$(ip link show "$iface" | grep -o "state [A-Z]*" | awk '{print $2}')
            local carrier=$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || echo "unknown")
            log "  $iface: $status (carrier: $carrier)"
        fi
    done
}

# Configure interface priorities
configure_interface_priorities() {
    log "=== Configuring Interface Priorities ==="
    
    # Create systemd-networkd configuration directory
    mkdir -p /etc/systemd/network
    
    # Configure ethernet with highest priority (metric 100)
    cat > /etc/systemd/network/10-ethernet.network << 'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPForward=yes
LinkLocalAddressing=ipv6

[DHCP]
RouteMetric=100
UseDNS=yes
UseHostname=false

[DHCPv4]
RouteMetric=100
UseDNS=yes

[DHCPv6]
RouteMetric=100
UseDNS=yes
EOF

    # Configure wireless with medium priority (metric 200)
    cat > /etc/systemd/network/20-wireless.network << 'EOF'
[Match]
Name=wl*

[Network]
DHCP=yes
IPForward=yes
LinkLocalAddressing=ipv6

[DHCP]
RouteMetric=200
UseDNS=yes
UseHostname=false

[DHCPv4]
RouteMetric=200
UseDNS=yes

[DHCPv6]
RouteMetric=200
UseDNS=yes
EOF

    # Configure USB/cellular with lowest priority (metric 300)
    cat > /etc/systemd/network/30-usb-cellular.network << 'EOF'
[Match]
Name=usb* wwp* ppp*

[Network]
DHCP=yes
IPForward=yes
LinkLocalAddressing=ipv6

[DHCP]
RouteMetric=300
UseDNS=yes
UseHostname=false

[DHCPv4]
RouteMetric=300
UseDNS=yes

[DHCPv6]
RouteMetric=300
UseDNS=yes
EOF

    log "Network interface priorities configured"
}

# Configure NetworkManager for better USB dongle support
configure_networkmanager() {
    log "=== Configuring NetworkManager ==="
    
    # Enhanced NetworkManager configuration
    cat > /etc/NetworkManager/NetworkManager.conf << 'EOF'
[main]
plugins=ifupdown,keyfile
no-auto-default=*
dns=systemd-resolved

[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=yes
ethernet.cloned-mac-address=random
wifi.cloned-mac-address=random

[connection]
# Autoconnect priorities
ethernet.autoconnect-priority=100
wifi.autoconnect-priority=50
gsm.autoconnect-priority=10

[keyfile]
unmanaged-devices=none
EOF

    # Create connection priority configuration
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-igel-priority.conf << 'EOF'
# IGEL M250C Network Priority Configuration

[connection-ethernet]
# Prioritize wired connections
autoconnect-priority=100
metric=100

[connection-wifi]
# Wi-Fi has lower priority than ethernet
autoconnect-priority=50
metric=200

[connection-gsm]
# Cellular has lowest priority
autoconnect-priority=10
metric=300

[device-ethernet]
# Keep ethernet always available
ignore-carrier=false

[device-wifi]
# Enable Wi-Fi power management
wifi.powersave=2
EOF

    log "NetworkManager configured for IGEL M250C"
}

# Test connectivity and routing
test_connectivity() {
    log "=== Testing Network Connectivity ==="
    
    # Show current routing table
    log "Current routing table:"
    ip route show | tee -a "$LOG_FILE"
    
    # Test primary gateway
    local default_gw=$(ip route show default | head -1 | awk '{print $3}')
    if [[ -n "$default_gw" ]]; then
        if ping -c 2 "$default_gw" >/dev/null 2>&1; then
            log "✓ Gateway connectivity: $default_gw"
        else
            log_warning "Gateway not reachable: $default_gw"
        fi
    fi
    
    # Test internet connectivity
    if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        log "✓ Internet connectivity: OK"
    else
        log_warning "Internet connectivity: FAILED"
    fi
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        log "✓ DNS resolution: OK"
    else
        log_warning "DNS resolution: FAILED"
    fi
}

# Main function
main() {
    case "${1:-setup}" in
        "setup")
            log "Starting network interface configuration..."
            detect_interfaces
            configure_interface_priorities
            configure_networkmanager
            
            # Restart networking services
            systemctl restart systemd-networkd || true
            systemctl restart NetworkManager || true
            
            sleep 5  # Wait for interfaces to come up
            test_connectivity
            log "Network configuration completed"
            ;;
        "detect")
            detect_interfaces
            ;;
        "test")
            test_connectivity
            ;;
        *)
            echo "Usage: $0 {setup|detect|test}"
            echo "  setup   - Configure network interfaces and priorities"
            echo "  detect  - Detect available network interfaces"
            echo "  test    - Test network connectivity"
            exit 1
            ;;
    esac
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

main "$@"
