#!/bin/bash

# USB Dongle Setup Script for IGEL M250C
# Configures USB Wi-Fi dongles and cellular modems for internet connectivity

set -euo pipefail

LOG_FILE="/var/log/usb-dongle-setup.log"
SUPPORTED_WIFI_DONGLES=(
    "0bda:8179"  # Realtek RTL8188EUS
    "0bda:818b"  # Realtek RTL8192EU
    "148f:5370"  # Ralink RT5370
    "148f:5372"  # Ralink RT5372
    "0cf3:9271"  # Atheros AR9271
    "0bda:8812"  # Realtek RTL8812AU
)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Install required packages
install_packages() {
    log "Installing USB dongle support packages..."
    
    apt update
    apt install -y \
        network-manager \
        network-manager-gnome \
        modemmanager \
        usb-modeswitch \
        usb-modeswitch-data \
        wireless-tools \
        wpasupplicant \
        rfkill \
        hostapd \
        dnsmasq
    
    log "USB dongle support packages installed"
}

# Detect USB devices
detect_usb_devices() {
    log "Detecting USB devices..."
    
    # List all USB devices
    log_info "All USB devices:"
    lsusb | tee -a "$LOG_FILE"
    
    echo
    log_info "Network interfaces:"
    ip link show | tee -a "$LOG_FILE"
    
    echo
    log_info "Wireless interfaces:"
    iwconfig 2>/dev/null | grep -E "^[a-z]" | tee -a "$LOG_FILE" || log_warning "No wireless interfaces found"
    
    echo
    log_info "ModemManager devices:"
    mmcli -L 2>/dev/null | tee -a "$LOG_FILE" || log_warning "No modem devices found"
}

# Check for supported Wi-Fi dongles
check_wifi_dongles() {
    log "Checking for supported Wi-Fi dongles..."
    
    local found_dongles=()
    local usb_devices=$(lsusb | awk '{print $6}')
    
    for device in $usb_devices; do
        for supported in "${SUPPORTED_WIFI_DONGLES[@]}"; do
            if [[ "$device" == "$supported" ]]; then
                found_dongles+=("$device")
                log_info "Found supported Wi-Fi dongle: $device"
            fi
        done
    done
    
    if [[ ${#found_dongles[@]} -eq 0 ]]; then
        log_warning "No recognized Wi-Fi dongles found"
        log_info "You may need to install additional drivers for your Wi-Fi adapter"
    else
        log "Found ${#found_dongles[@]} supported Wi-Fi dongle(s)"
    fi
    
    return 0
}

# Configure NetworkManager
configure_networkmanager() {
    log "Configuring NetworkManager..."
    
    # Enable and start NetworkManager
    systemctl enable NetworkManager
    systemctl start NetworkManager
    
    # Configure NetworkManager to manage all interfaces
    cat > /etc/NetworkManager/NetworkManager.conf << 'EOF'
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
EOF

    # Create a connection priority configuration
    cat > /etc/NetworkManager/conf.d/99-igel-priority.conf << 'EOF'
[connection-ethernet]
# Prioritize wired connections
autoconnect-priority=100

[connection-wifi]
# Wi-Fi has lower priority than ethernet
autoconnect-priority=50

[connection-cellular]
# Cellular has lowest priority
autoconnect-priority=10
EOF

    # Restart NetworkManager to apply changes
    systemctl restart NetworkManager
    
    log "NetworkManager configured"
}

# Configure ModemManager for cellular dongles
configure_modemmanager() {
    log "Configuring ModemManager for cellular dongles..."
    
    # Enable and start ModemManager
    systemctl enable ModemManager
    systemctl start ModemManager
    
    # Create ModemManager configuration
    mkdir -p /etc/ModemManager
    cat > /etc/ModemManager/ModemManager.conf << 'EOF'
[Logging]
level=INFO

[Test]
# Enable test mode for debugging if needed
enabled=false
EOF

    log "ModemManager configured"
}

# Setup USB mode switching
configure_usb_modeswitch() {
    log "Configuring USB mode switching..."
    
    # Enable usb_modeswitch service
    systemctl enable usb_modeswitch@*
    
    # Create custom rules if needed
    cat > /etc/udev/rules.d/99-igel-usb-modeswitch.rules << 'EOF'
# Custom USB mode switch rules for IGEL M250C
# Add any specific USB device rules here

# Example: Generic USB cellular modems
SUBSYSTEM=="usb", ATTRS{idVendor}=="12d1", ATTRS{idProduct}=="1f01", RUN+="/usr/sbin/usb_modeswitch -K -v 12d1 -p 1f01"
EOF

    # Reload udev rules
    udevadm control --reload-rules
    udevadm trigger
    
    log "USB mode switching configured"
}

# Create Wi-Fi connection helper script
create_wifi_helper() {
    log "Creating Wi-Fi connection helper..."
    
    cat > /usr/local/bin/igel-wifi-connect << 'EOF'
#!/bin/bash

# IGEL Wi-Fi Connection Helper
# Simple script to connect to Wi-Fi networks

set -euo pipefail

SSID="$1"
PASSWORD="${2:-}"
SECURITY="${3:-WPA}"

if [[ -z "$SSID" ]]; then
    echo "Usage: $0 <SSID> [PASSWORD] [SECURITY]"
    echo "Security options: NONE, WEP, WPA (default)"
    exit 1
fi

echo "Connecting to Wi-Fi network: $SSID"

if [[ "$SECURITY" == "NONE" ]]; then
    nmcli device wifi connect "$SSID"
elif [[ "$SECURITY" == "WEP" ]]; then
    nmcli device wifi connect "$SSID" password "$PASSWORD" --wep-key-type key
else
    # WPA/WPA2
    nmcli device wifi connect "$SSID" password "$PASSWORD"
fi

echo "Connection attempt completed"
nmcli connection show --active
EOF

    chmod +x /usr/local/bin/igel-wifi-connect
    
    log "Wi-Fi helper created: /usr/local/bin/igel-wifi-connect"
}

# Create cellular connection helper script
create_cellular_helper() {
    log "Creating cellular connection helper..."
    
    cat > /usr/local/bin/igel-cellular-connect << 'EOF'
#!/bin/bash

# IGEL Cellular Connection Helper
# Simple script to connect to cellular networks

set -euo pipefail

APN="${1:-internet}"
USERNAME="${2:-}"
PASSWORD="${3:-}"

echo "Setting up cellular connection with APN: $APN"

# Check for available modems
MODEMS=$(mmcli -L | grep -o '/org/freedesktop/ModemManager1/Modem/[0-9]*' | head -1)

if [[ -z "$MODEMS" ]]; then
    echo "No cellular modems found"
    exit 1
fi

MODEM_ID=$(echo "$MODEMS" | sed 's/.*Modem\///')
echo "Using modem: $MODEM_ID"

# Enable modem
mmcli -m "$MODEM_ID" --enable

# Create connection
if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
    nmcli connection add type gsm ifname '*' con-name cellular apn "$APN" user "$USERNAME" password "$PASSWORD"
else
    nmcli connection add type gsm ifname '*' con-name cellular apn "$APN"
fi

# Activate connection
nmcli connection up cellular

echo "Cellular connection setup completed"
nmcli connection show cellular
EOF

    chmod +x /usr/local/bin/igel-cellular-connect
    
    log "Cellular helper created: /usr/local/bin/igel-cellular-connect"
}

# Test connectivity
test_connectivity() {
    log "Testing network connectivity..."
    
    # Check active connections
    log_info "Active NetworkManager connections:"
    nmcli connection show --active | tee -a "$LOG_FILE"
    
    echo
    log_info "Network interfaces with IP addresses:"
    ip addr show | grep -E "inet " | tee -a "$LOG_FILE"
    
    echo
    log_info "Default route:"
    ip route show default | tee -a "$LOG_FILE"
    
    # Test internet connectivity
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        log "✓ Internet connectivity test passed"
    else
        log_warning "Internet connectivity test failed"
    fi
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        log "✓ DNS resolution test passed"
    else
        log_warning "DNS resolution test failed"
    fi
}

# Show usage instructions
show_usage() {
    echo
    log "=== USB Dongle Usage Instructions ==="
    echo
    log_info "Wi-Fi Connection:"
    log "  sudo igel-wifi-connect \"YourWiFiNetwork\" \"password\""
    log "  sudo igel-wifi-connect \"OpenNetwork\" \"\" NONE"
    echo
    log_info "Cellular Connection:"
    log "  sudo igel-cellular-connect \"internet\""
    log "  sudo igel-cellular-connect \"your.apn\" \"username\" \"password\""
    echo
    log_info "Manual NetworkManager Commands:"
    log "  nmcli device wifi list                    # List available Wi-Fi networks"
    log "  nmcli device wifi connect SSID password  # Connect to Wi-Fi"
    log "  nmcli connection show                     # Show all connections"
    log "  nmcli connection up connection_name       # Activate connection"
    log "  nmcli connection down connection_name     # Deactivate connection"
    echo
    log_info "Cellular Modem Commands:"
    log "  mmcli -L                                  # List available modems"
    log "  mmcli -m 0 --enable                      # Enable modem 0"
    log "  mmcli -m 0 --simple-connect=\"apn=internet\" # Simple connect"
}

# Main setup function
main() {
    case "${1:-setup}" in
        "setup")
            log "Starting USB dongle setup..."
            install_packages
            configure_networkmanager
            configure_modemmanager
            configure_usb_modeswitch
            create_wifi_helper
            create_cellular_helper
            detect_usb_devices
            check_wifi_dongles
            test_connectivity
            show_usage
            log "USB dongle setup completed"
            ;;
        "detect")
            detect_usb_devices
            check_wifi_dongles
            ;;
        "test")
            test_connectivity
            ;;
        "usage")
            show_usage
            ;;
        *)
            echo "Usage: $0 {setup|detect|test|usage}"
            echo "  setup   - Install and configure USB dongle support"
            echo "  detect  - Detect connected USB devices"
            echo "  test    - Test network connectivity"
            echo "  usage   - Show usage instructions"
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
