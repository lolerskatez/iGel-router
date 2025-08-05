#!/bin/bash

# TailSentry Coffee Shop Mode Setup
# This script configures the device as a WiFi client gateway

set -euo pipefail

LOG_FILE="/var/log/tailsentry-gateway.log"
WIFI_MANAGER="/usr/local/bin/wifi-manager.sh"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}" 
    exit 1
fi

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

show_help() {
    cat << EOF
TailSentry Coffee Shop / Gateway Mode Setup

This script configures TailSentry to connect to external WiFi networks
(like apartments or coffee shops) and route Tailscale traffic through them.

USAGE:
    sudo $(basename "$0") [OPTIONS] <wifi-interface> <ssid> <password>

OPTIONS:
    -h, --help          Show this help message
    -a, --ap-mode       Also create a local WiFi access point (requires second WiFi interface)
    --ap-name=NAME      Access point SSID (default: TailSentry)
    --ap-pass=PASS      Access point password
    --ap-interface=IF   Interface for access point (if different from client)

EXAMPLES:
    # Basic gateway mode (connect to coffee shop WiFi)
    sudo $(basename "$0") wlan0 "Coffee Shop WiFi" "password123"
    
    # Gateway mode with local access point on second WiFi adapter
    sudo $(basename "$0") -a wlan0 "Coffee Shop WiFi" "password123" --ap-interface=wlan1
    
    # Gateway mode with custom AP name
    sudo $(basename "$0") -a wlan0 "Coffee Shop WiFi" "password123" --ap-name="My TailSentry AP"

EOF
}

main() {
    # Parse command line options
    local enable_ap=false
    local ap_name="TailSentry"
    local ap_pass=""
    local ap_interface=""
    local wifi_interface=""
    local wifi_ssid=""
    local wifi_pass=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--ap-mode)
                enable_ap=true
                shift
                ;;
            --ap-name=*)
                ap_name="${1#*=}"
                shift
                ;;
            --ap-pass=*)
                ap_pass="${1#*=}"
                shift
                ;;
            --ap-interface=*)
                ap_interface="${1#*=}"
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$wifi_interface" ]]; then
                    wifi_interface="$1"
                elif [[ -z "$wifi_ssid" ]]; then
                    wifi_ssid="$1"
                elif [[ -z "$wifi_pass" ]]; then
                    wifi_pass="$1"
                else
                    log_error "Too many arguments"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Check required parameters
    if [[ -z "$wifi_interface" || -z "$wifi_ssid" ]]; then
        log_error "Missing required parameters"
        show_help
        exit 1
    fi

    # Check if WiFi interface exists
    if ! ip link show dev "$wifi_interface" &>/dev/null; then
        log_error "WiFi interface $wifi_interface does not exist"
        exit 1
    fi

    # Check AP interface if specified
    if [[ "$enable_ap" == "true" ]]; then
        if [[ -z "$ap_interface" ]]; then
            # Use the same interface if not specified
            ap_interface="$wifi_interface"
        elif ! ip link show dev "$ap_interface" &>/dev/null; then
            log_error "AP interface $ap_interface does not exist"
            exit 1
        fi

        # Check if AP password is specified
        if [[ -z "$ap_pass" ]]; then
            log_error "AP password is required in AP mode"
            exit 1
        fi
    fi

    log "Setting up TailSentry in Gateway mode"
    log "WiFi Client Interface: $wifi_interface"
    log "Target WiFi: $wifi_ssid"

    # Install necessary packages
    log "Installing required packages..."
    apt update
    apt install -y hostapd dnsmasq network-manager
    
    # Connect to the WiFi network
    log "Connecting to WiFi network $wifi_ssid..."
    if ! $WIFI_MANAGER connect "$wifi_interface" "$wifi_ssid" "$wifi_pass"; then
        log_error "Failed to connect to WiFi network"
        exit 1
    fi
    
    # Wait for connection
    log "Waiting for connection to establish..."
    sleep 5
    
    # Check connection
    if ! $WIFI_MANAGER status "$wifi_interface" | grep -q "connected"; then
        log_error "Failed to establish WiFi connection"
        exit 1
    fi
    
    # Configure Tailscale as exit node
    log "Setting up Tailscale as exit node..."
    tailscale up --advertise-exit-node
    
    # Create service to maintain connection
    log "Creating service to maintain connection..."
    cat > /etc/systemd/system/tailsentry-gateway.service << EOF
[Unit]
Description=TailSentry Gateway Mode
After=network.target tailscaled.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wifi-manager.sh gateway $wifi_interface "$wifi_ssid" "$wifi_pass"
Restart=on-failure
RestartSec=10
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tailsentry-gateway.service
    systemctl start tailsentry-gateway.service
    
    # Setup AP if requested
    if [[ "$enable_ap" == "true" ]]; then
        log "Setting up WiFi access point on $ap_interface with SSID: $ap_name"
        
        if ! $WIFI_MANAGER start-ap "$ap_interface" "$ap_name" "$ap_pass"; then
            log_error "Failed to set up access point"
            exit 1
        fi
        
        # Create service to maintain AP
        log "Creating service to maintain access point..."
        cat > /etc/systemd/system/tailsentry-ap.service << EOF
[Unit]
Description=TailSentry WiFi Access Point
After=network.target tailscaled.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wifi-manager.sh start-ap $ap_interface "$ap_name" "$ap_pass"
Restart=on-failure
RestartSec=10
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable tailsentry-ap.service
        systemctl start tailsentry-ap.service
    fi
    
    log "TailSentry Gateway Mode setup complete!"
    log "Your device is now connected to $wifi_ssid and serving as an exit node for your Tailscale network."
    
    if [[ "$enable_ap" == "true" ]]; then
        log "WiFi Access Point is active with SSID: $ap_name"
        log "Local devices can connect to this WiFi network."
    fi
    
    log "To manage this configuration, use the TailSentry Dashboard."
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
