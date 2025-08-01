#!/bin/bash

# IGEL M250C Wireless Network Management Script
# Provides command-line wireless network management for headless systems

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    IGEL Wireless Network Manager                      ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

show_help() {
    print_header
    cat << EOF
USAGE: $0 [COMMAND]

COMMANDS:
    scan              - Scan for available wireless networks
    list              - Show saved wireless connections
    connect SSID      - Connect to a wireless network (will prompt for password)
    disconnect        - Disconnect from current wireless network
    status            - Show wireless interface status
    enable            - Enable wireless interfaces
    disable           - Disable wireless interfaces
    forget SSID       - Remove saved network connection
    priority SSID N   - Set connection priority (higher number = higher priority)
    
EXAMPLES:
    $0 scan                    # Scan for networks
    $0 connect "MyWiFi"        # Connect to MyWiFi network
    $0 status                  # Show current status
    $0 priority "MyWiFi" 100   # Set MyWiFi to high priority

EOF
}

get_wireless_interface() {
    local interface=$(ip link show | grep -E "^[0-9]+: (wlan|wlp)" | head -1 | cut -d: -f2 | tr -d ' ')
    if [[ -z "$interface" ]]; then
        echo -e "${RED}No wireless interface found${NC}" >&2
        return 1
    fi
    echo "$interface"
}

scan_networks() {
    echo -e "${BLUE}📡 Scanning for wireless networks...${NC}"
    echo
    
    local interface
    if ! interface=$(get_wireless_interface); then
        return 1
    fi
    
    # Enable interface if disabled
    nmcli radio wifi on 2>/dev/null || true
    
    # Scan and display results
    if nmcli dev wifi list --rescan yes 2>/dev/null; then
        echo
        echo -e "${GREEN}✅ Scan complete${NC}"
        echo "Use: $0 connect \"NETWORK_NAME\" to connect to a network"
    else
        echo -e "${RED}❌ Failed to scan for networks${NC}"
        echo "Try: sudo rfkill unblock wifi"
        return 1
    fi
}

list_connections() {
    echo -e "${BLUE}📋 Saved wireless connections:${NC}"
    echo
    
    if nmcli connection show | grep wifi; then
        echo
    else
        echo "No saved wireless connections found"
    fi
    echo
    echo -e "${BLUE}🔗 Active connections:${NC}"
    nmcli connection show --active | grep -E "(wifi|wireless)" || echo "No active wireless connections"
}

connect_network() {
    local ssid="$1"
    
    if [[ -z "$ssid" ]]; then
        echo -e "${RED}❌ Please specify network name${NC}"
        echo "Usage: $0 connect \"NETWORK_NAME\""
        return 1
    fi
    
    echo -e "${BLUE}🔗 Connecting to wireless network: $ssid${NC}"
    
    # Check if connection already exists
    if nmcli connection show "$ssid" >/dev/null 2>&1; then
        echo "Connection profile exists, attempting to connect..."
        if nmcli connection up "$ssid"; then
            echo -e "${GREEN}✅ Connected to $ssid${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Failed to connect with existing profile, creating new one...${NC}"
        fi
    fi
    
    # Prompt for password
    echo
    read -s -p "Enter password for '$ssid' (leave empty for open network): " password
    echo
    
    # Connect to network
    if [[ -n "$password" ]]; then
        if nmcli dev wifi connect "$ssid" password "$password"; then
            echo -e "${GREEN}✅ Successfully connected to $ssid${NC}"
        else
            echo -e "${RED}❌ Failed to connect to $ssid${NC}"
            echo "Check password and try again"
            return 1
        fi
    else
        if nmcli dev wifi connect "$ssid"; then
            echo -e "${GREEN}✅ Successfully connected to $ssid${NC}"
        else
            echo -e "${RED}❌ Failed to connect to $ssid${NC}"
            return 1
        fi
    fi
}

disconnect_network() {
    echo -e "${BLUE}🔌 Disconnecting from wireless network...${NC}"
    
    local interface
    if ! interface=$(get_wireless_interface); then
        return 1
    fi
    
    if nmcli device disconnect "$interface"; then
        echo -e "${GREEN}✅ Disconnected from wireless network${NC}"
    else
        echo -e "${RED}❌ Failed to disconnect${NC}"
        return 1
    fi
}

show_status() {
    echo -e "${BLUE}📊 Wireless Interface Status${NC}"
    echo
    
    # Show radio status
    echo "Radio status:"
    nmcli radio wifi
    echo
    
    # Show interface details
    echo "Interface details:"
    local interface
    if interface=$(get_wireless_interface); then
        nmcli device show "$interface" | grep -E "(GENERAL.DEVICE|GENERAL.STATE|GENERAL.CONNECTION|IP4.ADDRESS|WIFI.SSID|WIFI.SIGNAL)"
    else
        echo "No wireless interface found"
        return 1
    fi
    echo
    
    # Show active connection
    echo "Active wireless connection:"
    nmcli connection show --active | grep wifi || echo "No active wireless connection"
}

enable_wireless() {
    echo -e "${BLUE}📡 Enabling wireless interfaces...${NC}"
    
    # Enable radio
    nmcli radio wifi on
    
    # Unblock rfkill if needed
    rfkill unblock wifi 2>/dev/null || true
    
    echo -e "${GREEN}✅ Wireless enabled${NC}"
}

disable_wireless() {
    echo -e "${BLUE}📵 Disabling wireless interfaces...${NC}"
    
    # Disconnect first
    disconnect_network 2>/dev/null || true
    
    # Disable radio
    nmcli radio wifi off
    
    echo -e "${GREEN}✅ Wireless disabled${NC}"
}

forget_network() {
    local ssid="$1"
    
    if [[ -z "$ssid" ]]; then
        echo -e "${RED}❌ Please specify network name${NC}"
        echo "Usage: $0 forget \"NETWORK_NAME\""
        return 1
    fi
    
    echo -e "${BLUE}🗑️ Removing saved network: $ssid${NC}"
    
    if nmcli connection delete "$ssid"; then
        echo -e "${GREEN}✅ Network '$ssid' removed${NC}"
    else
        echo -e "${RED}❌ Failed to remove network '$ssid'${NC}"
        echo "Network may not exist or may be currently active"
        return 1
    fi
}

set_priority() {
    local ssid="$1"
    local priority="$2"
    
    if [[ -z "$ssid" || -z "$priority" ]]; then
        echo -e "${RED}❌ Please specify network name and priority${NC}"
        echo "Usage: $0 priority \"NETWORK_NAME\" PRIORITY_NUMBER"
        echo "Higher numbers = higher priority"
        return 1
    fi
    
    echo -e "${BLUE}⚡ Setting priority for $ssid to $priority${NC}"
    
    if nmcli connection modify "$ssid" connection.autoconnect-priority "$priority"; then
        echo -e "${GREEN}✅ Priority set for '$ssid'${NC}"
    else
        echo -e "${RED}❌ Failed to set priority for '$ssid'${NC}"
        echo "Network connection may not exist"
        return 1
    fi
}

main() {
    case "${1:-help}" in
        "scan"|"s")
            scan_networks
            ;;
        "list"|"l")
            list_connections
            ;;
        "connect"|"c")
            connect_network "${2:-}"
            ;;
        "disconnect"|"d")
            disconnect_network
            ;;
        "status"|"st")
            show_status
            ;;
        "enable"|"on")
            enable_wireless
            ;;
        "disable"|"off")
            disable_wireless
            ;;
        "forget"|"f")
            forget_network "${2:-}"
            ;;
        "priority"|"p")
            set_priority "${2:-}" "${3:-}"
            ;;
        "help"|"h"|*)
            show_help
            ;;
    esac
}

# Check if NetworkManager is running
if ! systemctl is-active --quiet NetworkManager; then
    echo -e "${RED}❌ NetworkManager is not running${NC}"
    echo "Please start NetworkManager: sudo systemctl start NetworkManager"
    exit 1
fi

main "$@"
