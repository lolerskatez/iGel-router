#!/bin/bash

# TailSentry WiFi Manager Script
# Handles WiFi client mode and AP mode configuration

set -euo pipefail

LOG_FILE="/var/log/tailsentry-wifi.log"

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

# Function to detect WAN/Internet interface
detect_wan_interface() {
    local wan_interface=""
    local default_gateway=""
    local default_gateway_interface=""
    local is_connected=false
    local test_hosts=("8.8.8.8" "1.1.1.1" "9.9.9.9")
    
    log "Detecting WAN interface..."
    
    # Method 1: Check the interface used by the default route
    default_gateway=$(ip route | grep default | head -n1)
    if [[ -n "$default_gateway" ]]; then
        default_gateway_interface=$(echo "$default_gateway" | awk '{print $5}')
        log "Default gateway interface: $default_gateway_interface"
        
        # Test connectivity through this interface
        for host in "${test_hosts[@]}"; do
            if ping -c 1 -W 2 -I "$default_gateway_interface" "$host" > /dev/null 2>&1; then
                log "Confirmed internet connectivity on $default_gateway_interface"
                wan_interface="$default_gateway_interface"
                is_connected=true
                break
            fi
        done
    fi
    
    # Method 2: If Method 1 failed, try each interface with an IPv4 address
    if [[ "$is_connected" == "false" ]]; then
        log "Default route check failed. Trying all interfaces with IPv4 addresses..."
        
        # Get all interfaces with IPv4 addresses
        local interfaces=$(ip -4 addr | grep -v "127.0.0.1" | grep "inet " | awk '{print $NF}' | sort | uniq)
        
        for iface in $interfaces; do
            # Skip loopback, docker, and tailscale interfaces
            if [[ "$iface" == "lo" || "$iface" == docker* || "$iface" == tailscale* ]]; then
                continue
            fi
            
            log "Testing interface $iface..."
            for host in "${test_hosts[@]}"; do
                if ping -c 1 -W 2 -I "$iface" "$host" > /dev/null 2>&1; then
                    log "Confirmed internet connectivity on $iface"
                    wan_interface="$iface"
                    is_connected=true
                    break 2  # Break out of both loops
                fi
            done
        done
    fi
    
    # Method 3: Check common Raspberry Pi specific interfaces
    if [[ "$is_connected" == "false" ]]; then
        log "Standard methods failed. Checking common Pi configurations..."
        
        # Check common interfaces for Raspberry Pi in order of likelihood
        local common_pi_interfaces=("eth0" "wlan0" "usb0" "eth1")
        for iface in "${common_pi_interfaces[@]}"; do
            if ip link show dev "$iface" > /dev/null 2>&1; then
                if ip -4 addr show dev "$iface" | grep -q "inet "; then
                    log "Found configured interface: $iface"
                    wan_interface="$iface"
                    is_connected=true
                    break
                fi
            fi
        done
    fi
    
    # Final output
    if [[ -n "$wan_interface" ]]; then
        log "Detected WAN interface: $wan_interface"
        echo "$wan_interface"
        return 0
    else
        log_error "Failed to detect any WAN interface!"
        echo ""
        return 1
    fi
}

# List available WiFi networks
list_wifi_networks() {
    local interface="$1"
    log "Scanning for WiFi networks on $interface..."
    
    if ! command -v nmcli &> /dev/null; then
        log_error "nmcli not found. Please install NetworkManager."
        return 1
    fi
    
    # Ensure interface is up
    ip link set dev "$interface" up
    
    # Scan for networks
    nmcli -t -f SSID,SIGNAL,SECURITY device wifi list ifname "$interface" | sort -t: -k2 -nr
}

# Connect to WiFi network
connect_wifi() {
    local interface="$1"
    local ssid="$2"
    local password="$3"
    local hidden="${4:-no}"
    
    log "Connecting to WiFi network $ssid on $interface..."
    
    if ! command -v nmcli &> /dev/null; then
        log_error "nmcli not found. Please install NetworkManager."
        return 1
    fi
    
    # Disconnect from any existing connection on this interface
    nmcli device disconnect "$interface" 2>/dev/null || true
    
    # Create and connect to the new network
    if [[ "$hidden" == "yes" ]]; then
        nmcli connection add type wifi con-name "$ssid" ifname "$interface" ssid "$ssid" wifi.hidden yes
    else
        nmcli connection add type wifi con-name "$ssid" ifname "$interface" ssid "$ssid"
    fi
    
    # Set password if provided
    if [[ -n "$password" ]]; then
        nmcli connection modify "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$password"
    fi
    
    # Connect to network
    nmcli connection up "$ssid"
    
    # Check connection status
    sleep 3
    if nmcli -t -f DEVICE,STATE device | grep -q "$interface:connected"; then
        log "Successfully connected to $ssid"
        return 0
    else
        log_error "Failed to connect to $ssid"
        return 1
    fi
}

# Setup WiFi AP mode
setup_wifi_ap() {
    local interface="$1"
    local ssid="$2"
    local password="$3"
    local channel="${4:-6}"
    
    log "Setting up WiFi AP mode on $interface with SSID $ssid..."
    
    # Check if necessary packages are installed
    if ! command -v hostapd &> /dev/null; then
        log "Installing required packages for AP mode..."
        apt update
        apt install -y hostapd dnsmasq
    fi
    
    # Stop services if already running
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    
    # Configure hostapd
    cat > /etc/hostapd/hostapd.conf << EOF
interface=$interface
driver=nl80211
ssid=$ssid
hw_mode=g
channel=$channel
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$password
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF
    
    # Configure hostapd service
    sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd
    
    # Configure static IP for AP interface
    cat > /etc/network/interfaces.d/ap-$interface << EOF
allow-hotplug $interface
iface $interface inet static
    address 192.168.4.1
    netmask 255.255.255.0
    network 192.168.4.0
    broadcast 192.168.4.255
EOF
    
    # Configure dnsmasq for DHCP
    cat > /etc/dnsmasq.conf << EOF
interface=$interface
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=wlan
address=/tailsentry.local/192.168.4.1
EOF
    
    # Configure routing and IP forwarding
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/90-ap-forward.conf
    sysctl -p /etc/sysctl.d/90-ap-forward.conf
    
    # Setup iptables for NAT
    wan_iface=$(detect_wan_interface)
    if [[ -n "$wan_iface" ]]; then
        iptables -t nat -A POSTROUTING -o "$wan_iface" -j MASQUERADE
        iptables -A FORWARD -i "$interface" -o "$wan_iface" -j ACCEPT
        iptables -A FORWARD -i "$wan_iface" -o "$interface" -m state --state RELATED,ESTABLISHED -j ACCEPT
        
        # Save iptables rules
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
    else
        log_warning "No WAN interface detected. NAT not configured."
    fi
    
    # Enable and start services
    systemctl unmask hostapd
    systemctl enable hostapd dnsmasq
    systemctl start hostapd dnsmasq
    
    log "WiFi AP setup complete. SSID: $ssid"
    return 0
}

# Disable WiFi AP mode
disable_wifi_ap() {
    local interface="$1"
    
    log "Disabling WiFi AP mode on $interface..."
    
    # Stop services
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    systemctl disable hostapd dnsmasq 2>/dev/null || true
    
    # Remove configuration files
    rm -f /etc/network/interfaces.d/ap-$interface
    
    # Reset the interface
    ip link set dev "$interface" down
    ip addr flush dev "$interface"
    
    log "WiFi AP mode disabled on $interface"
    return 0
}

# Get WiFi connection status
get_wifi_status() {
    local interface="$1"
    
    log "Getting WiFi status for $interface..."
    
    if ! command -v nmcli &> /dev/null; then
        echo "{\"error\": \"NetworkManager not installed\"}"
        return 1
    fi
    
    # Check if interface exists
    if ! ip link show dev "$interface" &>/dev/null; then
        echo "{\"error\": \"Interface $interface not found\"}"
        return 1
    fi
    
    # Get connection status
    local connected_ssid=""
    local signal_strength=""
    local connection_status="disconnected"
    local ip_address=""
    
    if nmcli -t -f DEVICE,STATE device | grep -q "$interface:connected"; then
        connection_status="connected"
        connected_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$interface" | cut -d: -f2)
        signal_strength=$(nmcli -t -f GENERAL.HWADDR,WIFI-PROPERTIES.SIGNAL device show "$interface" | grep -A1 "HWADDR" | tail -1 | cut -d: -f2)
        ip_address=$(ip -4 addr show dev "$interface" | grep -oP 'inet \K[\d.]+')
    fi
    
    # Create JSON output
    cat << EOF
{
  "interface": "$interface",
  "status": "$connection_status",
  "ssid": "$connected_ssid",
  "signal": "$signal_strength",
  "ip": "$ip_address",
  "type": "$(if [[ -d /sys/class/net/$interface/wireless ]]; then echo "wireless"; else echo "wired"; fi)"
}
EOF
}

# List all interfaces with their status
list_all_interfaces() {
    log "Listing all network interfaces..."
    
    echo "["
    
    first=true
    for iface in $(ls /sys/class/net/ | grep -v "lo\|docker\|tailscale\|veth"); do
        if ! $first; then
            echo ","
        else
            first=false
        fi
        
        # Determine interface type
        local type="wired"
        if [[ -d /sys/class/net/$iface/wireless ]]; then
            type="wireless"
        elif [[ "$iface" == "wwan"* || "$iface" == "usb"* || "$iface" == "wwan"* ]]; then
            type="cellular"
        fi
        
        # Get status
        local status="down"
        local ip_address=""
        if ip link show dev "$iface" | grep -q "UP"; then
            status="up"
            ip_address=$(ip -4 addr show dev "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")
        fi
        
        # Check if it's the WAN interface
        local wan_if=$(detect_wan_interface || echo "")
        local is_wan="false"
        if [[ "$wan_if" == "$iface" ]]; then
            is_wan="true"
        fi
        
        # Get additional WiFi information
        local ssid=""
        local signal=""
        if [[ "$type" == "wireless" && "$status" == "up" ]]; then
            ssid=$(iwconfig "$iface" 2>/dev/null | grep -oP 'ESSID:"\K[^"]+' || echo "")
            signal=$(iwconfig "$iface" 2>/dev/null | grep -oP 'Signal level=\K-[0-9]+' || echo "")
        fi
        
        cat << EOF
{
  "interface": "$iface",
  "type": "$type",
  "status": "$status",
  "ip": "$ip_address",
  "is_wan": $is_wan,
  "ssid": "$ssid",
  "signal": "$signal"
}
EOF
    done
    
    echo "]"
}

# Setup system for apartment/coffee shop WiFi gateway
setup_wifi_gateway() {
    local wifi_interface="$1"
    local ssid="$2"
    local password="$3"
    
    log "Setting up WiFi gateway for apartment/coffee shop use..."
    
    # 1. Connect to external WiFi
    connect_wifi "$wifi_interface" "$ssid" "$password" || return 1
    
    # 2. Configure Tailscale as exit node
    log "Setting up Tailscale as exit node..."
    tailscale up --advertise-exit-node
    
    # 3. Wait for connection to be established
    sleep 5
    
    # 4. Save the configuration
    mkdir -p /etc/tailsentry
    cat > /etc/tailsentry/gateway-config.json << EOF
{
  "mode": "wifi-gateway",
  "client_interface": "$wifi_interface",
  "client_ssid": "$ssid",
  "timestamp": "$(date -Iseconds)"
}
EOF
    
    log "WiFi gateway setup complete."
    return 0
}

# Display usage information
usage() {
    cat << EOF
TailSentry WiFi Manager

Usage: $0 [command] [options]

Commands:
  scan <interface>                    Scan for WiFi networks
  connect <interface> <ssid> <pass>   Connect to a WiFi network
  status <interface>                  Show WiFi connection status
  list                                List all network interfaces
  start-ap <interface> <ssid> <pass>  Start WiFi access point
  stop-ap <interface>                 Stop WiFi access point
  gateway <interface> <ssid> <pass>   Setup as WiFi gateway (coffee shop mode)
  wan                                 Detect WAN/Internet interface

Examples:
  $0 scan wlan0
  $0 connect wlan0 "Coffee Shop WiFi" "password123"
  $0 start-ap wlan1 "TailSentry" "securepassword"
  $0 gateway wlan0 "ApartmentWifi" "password123"

EOF
}

# Main function
main() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check if we have enough arguments
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi
    
    # Parse command
    case "$1" in
        scan)
            if [[ $# -lt 2 ]]; then
                log_error "Missing interface parameter"
                usage
                exit 1
            fi
            list_wifi_networks "$2"
            ;;
        connect)
            if [[ $# -lt 4 ]]; then
                log_error "Missing parameters"
                usage
                exit 1
            fi
            connect_wifi "$2" "$3" "$4" "${5:-no}"
            ;;
        status)
            if [[ $# -lt 2 ]]; then
                log_error "Missing interface parameter"
                usage
                exit 1
            fi
            get_wifi_status "$2"
            ;;
        list)
            list_all_interfaces
            ;;
        start-ap)
            if [[ $# -lt 4 ]]; then
                log_error "Missing parameters"
                usage
                exit 1
            fi
            setup_wifi_ap "$2" "$3" "$4" "${5:-6}"
            ;;
        stop-ap)
            if [[ $# -lt 2 ]]; then
                log_error "Missing interface parameter"
                usage
                exit 1
            fi
            disable_wifi_ap "$2"
            ;;
        gateway)
            if [[ $# -lt 4 ]]; then
                log_error "Missing parameters"
                usage
                exit 1
            fi
            setup_wifi_gateway "$2" "$3" "$4"
            ;;
        wan)
            detect_wan_interface
            ;;
        *)
            log_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
