#!/bin/bash

# IGEL M250C Router Health Check Script
# Quick system health and status verification

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
    echo -e "${BLUE}║                    IGEL M250C Health Check                            ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

check_service() {
    local service="$1"
    local description="$2"
    
    if systemctl is-active --quiet "$service"; then
        echo -e "  ✅ $description: ${GREEN}Running${NC}"
        return 0
    else
        echo -e "  ❌ $description: ${RED}Not running${NC}"
        return 1
    fi
}

check_network_connectivity() {
    echo -e "${BLUE}🌐 Network Connectivity${NC}"
    
    # Check default gateway
    local gateway=$(ip route show default | head -1 | awk '{print $3}' 2>/dev/null || echo "")
    if [[ -n "$gateway" ]] && ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
        echo -e "  ✅ Gateway ($gateway): ${GREEN}Reachable${NC}"
    else
        echo -e "  ❌ Gateway: ${RED}Unreachable${NC}"
    fi
    
    # Check internet connectivity
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "  ✅ Internet: ${GREEN}Connected${NC}"
    else
        echo -e "  ❌ Internet: ${RED}No connectivity${NC}"
    fi
    
    # Check DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "  ✅ DNS: ${GREEN}Working${NC}"
    else
        echo -e "  ❌ DNS: ${RED}Resolution failed${NC}"
    fi
    echo
}

check_tailscale_status() {
    echo -e "${BLUE}🔗 Tailscale Status${NC}"
    
    if ! command -v tailscale >/dev/null 2>&1; then
        echo -e "  ❌ Tailscale: ${RED}Not installed${NC}"
        return 1
    fi
    
    if ! systemctl is-active --quiet tailscaled; then
        echo -e "  ❌ Tailscale daemon: ${RED}Not running${NC}"
        return 1
    fi
    
    if tailscale status >/dev/null 2>&1; then
        echo -e "  ✅ Tailscale: ${GREEN}Connected${NC}"
        local tailscale_ip=$(tailscale ip 2>/dev/null || echo "Unknown")
        echo "     Tailscale IP: $tailscale_ip"
        
        # Check if advertising routes
        if tailscale status | grep -q "offering exit node"; then
            echo -e "     Exit node: ${GREEN}Advertising${NC}"
        else
            echo -e "     Exit node: ${YELLOW}Not advertising${NC}"
        fi
        
        # Check subnet routes
        local routes=$(tailscale status | grep "subnet routes" | cut -d: -f2 | tr -d ' ' || echo "none")
        echo "     Subnet routes: $routes"
    else
        echo -e "  ❌ Tailscale: ${RED}Not authenticated${NC}"
    fi
    echo
}

check_system_resources() {
    echo -e "${BLUE}📊 System Resources${NC}"
    
    # Memory usage
    local mem_info=$(free -h | grep "Mem:")
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_percent=$(free | grep "Mem:" | awk '{printf "%.0f", ($3/$2)*100}')
    
    if [[ $mem_percent -lt 80 ]]; then
        echo -e "  ✅ Memory: ${GREEN}$mem_used/$mem_total (${mem_percent}%)${NC}"
    elif [[ $mem_percent -lt 90 ]]; then
        echo -e "  ⚠️  Memory: ${YELLOW}$mem_used/$mem_total (${mem_percent}%)${NC}"
    else
        echo -e "  ❌ Memory: ${RED}$mem_used/$mem_total (${mem_percent}%)${NC}"
    fi
    
    # Disk usage for root filesystem
    local disk_info=$(df -h / | tail -1)
    local disk_used=$(echo "$disk_info" | awk '{print $3}')
    local disk_total=$(echo "$disk_info" | awk '{print $2}')
    local disk_percent=$(echo "$disk_info" | awk '{print $5}' | tr -d '%')
    
    if [[ $disk_percent -lt 80 ]]; then
        echo -e "  ✅ Disk (/): ${GREEN}$disk_used/$disk_total (${disk_percent}%)${NC}"
    elif [[ $disk_percent -lt 90 ]]; then
        echo -e "  ⚠️  Disk (/): ${YELLOW}$disk_used/$disk_total (${disk_percent}%)${NC}"
    else
        echo -e "  ❌ Disk (/): ${RED}$disk_used/$disk_total (${disk_percent}%)${NC}"
    fi
    
    # Load average
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    echo "     Load average: $load"
    
    # Uptime
    local uptime_info=$(uptime -p)
    echo "     Uptime: $uptime_info"
    echo
}

check_web_interfaces() {
    echo -e "${BLUE}🌐 Web Interfaces${NC}"
    
    local ip_address=$(hostname -I | awk '{print $1}')
    
    # Check CasaOS
    if curl -s --connect-timeout 3 "http://$ip_address" >/dev/null 2>&1; then
        echo -e "  ✅ CasaOS: ${GREEN}http://$ip_address${NC}"
    else
        echo -e "  ❌ CasaOS: ${RED}Not responding${NC}"
    fi
    
    # Check Cockpit
    if systemctl is-active --quiet cockpit.socket; then
        if curl -s -k --connect-timeout 3 "https://$ip_address:9090" >/dev/null 2>&1; then
            echo -e "  ✅ Cockpit: ${GREEN}https://$ip_address:9090${NC}"
        else
            echo -e "  ⚠️  Cockpit: ${YELLOW}Service running but not responding${NC}"
        fi
    else
        echo "     Cockpit: Not installed or disabled"
    fi
    echo
}

main() {
    print_header
    
    # Check core services
    echo -e "${BLUE}🔧 Core Services${NC}"
    local services_ok=0
    check_service "tailscaled" "Tailscale" && ((services_ok++))
    check_service "casaos" "CasaOS" && ((services_ok++))
    check_service "igel-monitor" "System Monitor" && ((services_ok++))
    echo
    
    # Detailed checks
    check_network_connectivity
    check_tailscale_status
    check_system_resources
    check_web_interfaces
    
    # Summary
    echo -e "${BLUE}📋 Summary${NC}"
    echo "  System: IGEL M250C Router"
    echo "  Hostname: $(hostname)"
    echo "  IP Address: $(hostname -I | awk '{print $1}')"
    echo "  Check time: $(date)"
    
    # Overall status
    if [[ $services_ok -eq 3 ]] && ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        echo -e "  Overall status: ${GREEN}✅ Healthy${NC}"
        exit 0
    else
        echo -e "  Overall status: ${YELLOW}⚠️  Issues detected${NC}"
        exit 1
    fi
}

main "$@"
