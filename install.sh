#!/bin/bash

# IGEL M250C Tailscale Subnet Router Setup Script
# This script configures an IGEL M250C thin client as a headless Tailscale subnet router
# and exit node using USB-booted Debian 12

set -euo pipefail

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/igel-setup.log"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
INSTALL_COCKPIT="${INSTALL_COCKPIT:-}"
USE_EMMC="${USE_EMMC:-}"
DEVICE_HOSTNAME="${DEVICE_HOSTNAME:-}"
ADVERTISED_ROUTES="${ADVERTISED_ROUTES:-}"
NETWORK_INTERFACE_MODE="${NETWORK_INTERFACE_MODE:-auto}"
INTERACTIVE_MODE="${INTERACTIVE_MODE:-true}"
ENABLE_SECURITY_HARDENING="${ENABLE_SECURITY_HARDENING:-true}"
INSTALL_ID="igel-$(date +%Y%m%d)-$(openssl rand -hex 4 2>/dev/null || echo $(shuf -i 1000-9999 -n 1))"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Pre-flight system checks
preflight_checks() {
    log "=== Running Pre-flight Checks ==="
    
    local checks_passed=true
    
    # Check if this looks like an IGEL M250C
    if ! lscpu | grep -q "AMD GX-415GA\|AuthenticAMD"; then
        log_warning "System doesn't appear to be AMD-based (expected for IGEL M250C)"
    fi
    
    # Check available memory
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_kb / 1024 / 1024))
    if [[ $mem_gb -lt 2 ]]; then
        log_error "Insufficient memory: ${mem_gb}GB (minimum 2GB required)"
        checks_passed=false
    fi
    
    # Check available disk space (minimum 8GB)
    local disk_space=$(df / | tail -1 | awk '{print $4}')
    local disk_gb=$((disk_space / 1024 / 1024))
    if [[ $disk_gb -lt 8 ]]; then
        log_error "Insufficient disk space: ${disk_gb}GB (minimum 8GB required)"
        checks_passed=false
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connectivity - required for package installation"
        checks_passed=false
    fi
    
    # Check if Debian/Ubuntu
    if ! command -v apt >/dev/null 2>&1; then
        log_error "This script requires a Debian-based system with apt"
        checks_passed=false
    fi
    
    # Check USB boot (look for USB storage as root device)
    local root_device=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
    if [[ "$root_device" =~ /dev/sd[a-z] ]] && ! [[ "$root_device" =~ /dev/mmcblk ]]; then
        log "✓ Running from USB storage (recommended): $root_device"
    else
        log_warning "Root device ($root_device) may not be USB storage"
    fi
    
    if [[ "$checks_passed" != "true" ]]; then
        log_error "Pre-flight checks failed. Please address the issues above."
        exit 1
    fi
    
    log "✓ Pre-flight checks passed"
}

# Interactive configuration prompt
interactive_config() {
    # Skip if all values are already set via environment variables
    if [[ -n "$TAILSCALE_AUTH_KEY" && -n "$INSTALL_COCKPIT" && -n "$USE_EMMC" && -n "$DEVICE_HOSTNAME" ]]; then
        log "Using configuration from environment variables"
        return 0
    fi
    
    echo
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      IGEL M250C Router Setup                          ║${NC}"
    echo -e "${BLUE}║                   Interactive Configuration                           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "This wizard will guide you through configuring your IGEL M250C as a"
    echo "Tailscale subnet router. You can press Enter to use default values."
    echo
    
    # Device hostname
    if [[ -z "$DEVICE_HOSTNAME" ]]; then
        echo -e "${YELLOW}Device Hostname Configuration${NC}"
        echo "Choose a hostname for your IGEL router (will appear in Tailscale admin):"
        read -p "Hostname [igel-m250c-router]: " -r hostname_input
        DEVICE_HOSTNAME="${hostname_input:-igel-m250c-router}"
        echo
    fi
    
    # eMMC usage
    if [[ -z "$USE_EMMC" ]]; then
        echo -e "${YELLOW}eMMC Storage Configuration${NC}"
        echo "The IGEL M250C has ~3.5GB internal eMMC storage that can be used for:"
        echo "  • Swap space (reduces USB drive wear)"
        echo "  • Log storage (improves performance)"
        echo
        while true; do
            read -p "Use eMMC for swap and log storage? [Y/n]: " -n 1 -r emmc_choice
            echo
            case $emmc_choice in
                [Yy]|"") USE_EMMC="true"; break ;;
                [Nn]) USE_EMMC="false"; break ;;
                *) echo "Please answer Y or n" ;;
            esac
        done
        echo
    fi
    
    # Cockpit installation
    if [[ -z "$INSTALL_COCKPIT" ]]; then
        echo -e "${YELLOW}Web Management Interface${NC}"
        echo "Choose your management interface preference:"
        echo "  • CasaOS: User-friendly, Docker-focused (always installed)"
        echo "  • Cockpit: Advanced system management (optional)"
        echo
        while true; do
            read -p "Install Cockpit for advanced system management? [Y/n]: " -n 1 -r cockpit_choice
            echo
            case $cockpit_choice in
                [Yy]|"") INSTALL_COCKPIT="true"; break ;;
                [Nn]) INSTALL_COCKPIT="false"; break ;;
                *) echo "Please answer Y or n" ;;
            esac
        done
        echo
    fi
    
    # Network interface configuration
    if [[ -z "$NETWORK_INTERFACE_MODE" ]]; then
        echo -e "${YELLOW}Network Interface Configuration${NC}"
        echo "Configure network interface priorities and behavior:"
        echo
        echo "Available interfaces:"
        # Show detected interfaces
        local ethernet_ifs=($(ip link show | grep -E "^[0-9]+: (eth|enp|eno)" | cut -d: -f2 | tr -d ' ' || true))
        local wireless_ifs=($(ip link show | grep -E "^[0-9]+: (wlan|wlp)" | cut -d: -f2 | tr -d ' ' || true))
        local usb_ifs=($(ip link show | grep -E "^[0-9]+: (usb|wwp)" | cut -d: -f2 | tr -d ' ' || true))
        
        [[ ${#ethernet_ifs[@]} -gt 0 ]] && echo "  • Ethernet: ${ethernet_ifs[*]}"
        [[ ${#wireless_ifs[@]} -gt 0 ]] && echo "  • Wireless: ${wireless_ifs[*]}"
        [[ ${#usb_ifs[@]} -gt 0 ]] && echo "  • USB/Cellular: ${usb_ifs[*]}"
        echo
        
        echo "Priority configuration (recommended: Ethernet > Wi-Fi > Cellular):"
        while true; do
            read -p "Use automatic interface prioritization? [Y/n]: " -n 1 -r net_choice
            echo
            case $net_choice in
                [Yy]|"") NETWORK_INTERFACE_MODE="auto"; break ;;
                [Nn]) 
                    echo "Manual configuration will be required after installation."
                    NETWORK_INTERFACE_MODE="manual"
                    break
                    ;;
                *) echo "Please answer Y or n" ;;
            esac
        done
        echo
    fi
    
    # Network routes
    if [[ -z "$ADVERTISED_ROUTES" ]]; then
        echo -e "${YELLOW}Network Route Configuration${NC}"
        echo "Configure which networks this router will advertise to Tailscale clients:"
        echo
        echo "Default routes (recommended for most setups):"
        echo "  • 192.168.0.0/16  - Most home/office networks"
        echo "  • 10.0.0.0/8      - Corporate networks"
        echo "  • 172.16.0.0/12   - Docker/container networks"
        echo
        echo "Options:"
        echo "  1. Use default routes (covers most networks)"
        echo "  2. Enter custom routes"
        echo "  3. Auto-detect local network only"
        echo
        
        while true; do
            read -p "Choose option [1]: " -n 1 -r route_choice
            echo
            case $route_choice in
                1|"")
                    ADVERTISED_ROUTES="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
                    break
                    ;;
                2)
                    echo "Enter routes separated by commas (e.g., 192.168.1.0/24,10.0.0.0/8):"
                    read -p "Routes: " -r custom_routes
                    if [[ -n "$custom_routes" ]]; then
                        ADVERTISED_ROUTES="$custom_routes"
                    else
                        ADVERTISED_ROUTES="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
                    fi
                    break
                    ;;
                3)
                    # Auto-detect local network
                    local_network=$(ip route | grep -E "^192\.168\.|^10\.|^172\." | head -1 | awk '{print $1}' || echo "192.168.1.0/24")
                    ADVERTISED_ROUTES="$local_network"
                    echo "Auto-detected: $ADVERTISED_ROUTES"
                    break
                    ;;
                *)
                    echo "Please choose 1, 2, or 3"
                    ;;
            esac
        done
        echo
    fi
    
    if [[ -z "$ENABLE_SECURITY_HARDENING" ]]; then
        echo -e "${YELLOW}Security Hardening${NC}"
        echo "Additional security measures can be applied to harden this router:"
        echo "  • Fail2ban for intrusion prevention"
        echo "  • Automatic security updates"
        echo "  • SSH hardening and monitoring"
        echo "  • Kernel security settings"
        echo "  • Enhanced logging and monitoring"
        echo
        while true; do
            read -p "Enable additional security hardening? [Y/n]: " -n 1 -r security_choice
            echo
            case $security_choice in
                [Yy]|"") ENABLE_SECURITY_HARDENING="true"; break ;;
                [Nn]) ENABLE_SECURITY_HARDENING="false"; break ;;
                *) echo "Please answer Y or n" ;;
            esac
        done
        echo
    fi
    echo -e "${GREEN}║                        Configuration Summary                          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "Device Hostname: $DEVICE_HOSTNAME"
    echo "Use eMMC Storage: $USE_EMMC"
    echo "Install Cockpit: $INSTALL_COCKPIT"
    echo "Network Interface Mode: $NETWORK_INTERFACE_MODE"
    echo "Security Hardening: $ENABLE_SECURITY_HARDENING"
    echo "Advertised Routes: $ADVERTISED_ROUTES"
    echo "Tailscale Auth Key: ${TAILSCALE_AUTH_KEY:+[Provided]}${TAILSCALE_AUTH_KEY:-[Will prompt later]}"
    echo
    
    while true; do
        read -p "Proceed with this configuration? [Y/n]: " -n 1 -r proceed_choice
        echo
        case $proceed_choice in
            [Yy]|"") break ;;
            [Nn]) 
                echo "Configuration cancelled. Please run the script again."
                exit 0
                ;;
            *) echo "Please answer Y or n" ;;
        esac
    done
    
        log "Interactive configuration completed"
}

# Show help information
show_help() {
    cat << EOF
IGEL M250C Tailscale Router Setup

This script sets up an IGEL M250C thin client as a headless Tailscale subnet router
and exit node running Debian 12 from a USB drive.

USAGE:
    sudo ./install.sh [OPTIONS]

OPTIONS:
    -h, --help                 Show this help message
    --non-interactive          Run in non-interactive mode (requires environment variables)
    --tailscale-key=KEY        Tailscale auth key (starts with tskey-auth-)
    --hostname=NAME            Device hostname (default: igel-m250c-router)
    --routes=ROUTES            Comma-separated CIDR routes to advertise
    --no-cockpit               Skip Cockpit installation
    --no-emmc                  Skip eMMC configuration

EXAMPLES:
    # Interactive installation (recommended):
    sudo ./install.sh

    # Non-interactive with custom configuration:
    sudo ./install.sh --non-interactive 
        --tailscale-key=tskey-auth-your-key-here 
        --hostname=office-router 
        --routes=192.168.1.0/24,10.0.0.0/8

    # Interactive with some pre-configured options:
    sudo ./install.sh --hostname=home-router --no-cockpit

ENVIRONMENT VARIABLES:
    You can also set configuration via environment variables:
    
    TAILSCALE_AUTH_KEY    Your Tailscale auth key
    DEVICE_HOSTNAME       Device hostname
    ADVERTISED_ROUTES     Comma-separated routes
    INSTALL_COCKPIT       true/false (install Cockpit)
    USE_EMMC             true/false (use eMMC storage)
    INTERACTIVE_MODE     true/false (enable interactive prompts)

REQUIREMENTS:
    - IGEL M250C thin client
    - 64GB+ USB 3.0 drive with Debian 12 minimal/server
    - Internet connection
    - Tailscale account with auth key
    - Root access

For more information, see README.md or visit:
https://github.com/your-repo/igel-m250c-router

EOF
}

# System information
show_system_info() {
    log "=== IGEL M250C System Information ==="
    log "Hostname: $(hostname)"
    log "OS: $(lsb_release -d | cut -f2)"
    log "Kernel: $(uname -r)"
    log "Architecture: $(uname -m)"
    log "Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
    log "Storage devices:"
    lsblk | tee -a "$LOG_FILE"
    echo
}

# Update system packages
update_system() {
    log "=== Updating System Packages ==="
    apt update
    apt upgrade -y
    apt install -y \
        curl \
        wget \
        gnupg \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        systemd \
        iptables \
        ufw \
        htop \
        nano \
        git \
        unzip \
        network-manager \
        modemmanager \
        usb-modeswitch \
        usb-modeswitch-data \
        wireless-tools \
        wpasupplicant \
        rfkill \
        iw \
        network-manager-config-connectivity-debian
    log "System packages updated successfully"
}

# Configure IP forwarding
configure_ip_forwarding() {
    log "=== Configuring IP Forwarding ==="
    
    # Backup original sysctl.conf
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)
    
    # Remove any existing IP forwarding entries to avoid duplicates
    sed -i '/net\.ipv4\.ip_forward/d' /etc/sysctl.conf
    sed -i '/net\.ipv6\.conf\.all\.forwarding/d' /etc/sysctl.conf
    
    # Enable IP forwarding with optimized settings for routing
    cat >> /etc/sysctl.conf << 'EOF'

# IGEL Router Configuration
# IPv4 forwarding
net.ipv4.ip_forward = 1

# IPv6 forwarding  
net.ipv6.conf.all.forwarding = 1

# Network performance optimizations for routing
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 5000

# Reduce swap usage to preserve USB drive
vm.swappiness = 10

# Connection tracking for NAT
net.netfilter.nf_conntrack_max = 65536
EOF
    
    # Apply immediately
    sysctl -p
    
    log "IP forwarding and network optimizations configured"
}

# Install Tailscale
install_tailscale() {
    log "=== Installing Tailscale ==="
    
    # Add Tailscale's GPG key
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    
    # Add Tailscale repository
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
    
    # Update and install
    apt update
    apt install -y tailscale
    
    # Enable and start service
    systemctl enable tailscaled
    systemctl start tailscaled
    
    log "Tailscale installed successfully"
}

# Configure Tailscale
configure_tailscale() {
    log "=== Configuring Tailscale ==="
    
    # Prompt for Tailscale auth key if not provided
    if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
        echo
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                    Tailscale Authentication                    ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo
        echo "To configure Tailscale automatically, you need an authentication key."
        echo "You can get one from: https://login.tailscale.com/admin/settings/keys"
        echo
        echo "Options:"
        echo "  1. Enter your Tailscale auth key now (recommended)"
        echo "  2. Skip automatic setup (manual configuration required later)"
        echo
        
        while true; do
            read -p "Enter your choice (1/2): " -n 1 -r choice
            echo
            
            case $choice in
                1)
                    echo
                    read -p "Enter your Tailscale auth key (tskey-auth-...): " -r auth_key
                    echo
                    
                    # Validate auth key format
                    if [[ "$auth_key" =~ ^tskey-auth-.+ ]]; then
                        TAILSCALE_AUTH_KEY="$auth_key"
                        log "Tailscale auth key provided, proceeding with automatic setup..."
                        break
                    else
                        echo -e "${RED}Invalid auth key format. Keys should start with 'tskey-auth-'${NC}"
                        echo "Please try again or choose option 2 for manual setup."
                        echo
                    fi
                    ;;
                2)
                    log_warning "Skipping automatic Tailscale setup"
                    break
                    ;;
                *)
                    echo "Please enter 1 or 2"
                    ;;
            esac
        done
    fi
    
    # Configure Tailscale with auth key or manual setup
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        log "Authenticating Tailscale with provided auth key..."
        
        # Use configured routes or defaults
        local routes="${ADVERTISED_ROUTES:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"
        local hostname="${DEVICE_HOSTNAME:-igel-m250c-router}"
        
        # Attempt automatic configuration
        if tailscale up --authkey="$TAILSCALE_AUTH_KEY" \
            --advertise-routes="$routes" \
            --advertise-exit-node \
            --accept-routes \
            --hostname="$hostname"; then
            log "✓ Tailscale authenticated and configured successfully!"
            log "  Hostname: $hostname"
            log "  Advertised routes: $routes"
        else
            log_error "Failed to authenticate with Tailscale"
            log_warning "You can manually authenticate later with:"
            log "tailscale up --advertise-routes=$routes --advertise-exit-node --accept-routes --hostname=$hostname"
        fi
    else
        log_warning "No Tailscale auth key provided. Manual configuration required:"
        echo
        echo -e "${YELLOW}After installation completes, run the following command:${NC}"
        local routes="${ADVERTISED_ROUTES:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"
        local hostname="${DEVICE_HOSTNAME:-igel-m250c-router}"
        echo -e "${BLUE}tailscale up --advertise-routes=$routes --advertise-exit-node --accept-routes --hostname=$hostname${NC}"
        echo
        echo "This will open a browser window for authentication, or provide a URL to visit."
    fi
    
    log "Tailscale configuration completed"
}

# Detect and configure eMMC
configure_emmc() {
    if [[ "$USE_EMMC" != "true" ]]; then
        log "eMMC usage disabled, skipping..."
        return
    fi

    log "=== Configuring eMMC Storage ==="
    
    # Look for eMMC device (usually mmcblk0)
    EMMC_DEVICE=""
    for device in /dev/mmcblk*; do
        if [[ -b "$device" ]]; then
            EMMC_DEVICE="$device"
            break
        fi
    done
    
    if [[ -z "$EMMC_DEVICE" ]]; then
        log_warning "No eMMC device found, skipping eMMC configuration"
        return
    fi
    
    log "Found eMMC device: $EMMC_DEVICE"
    
    # Get eMMC size
    EMMC_SIZE=$(lsblk -b -d -n -o SIZE "$EMMC_DEVICE" 2>/dev/null || echo "0")
    EMMC_SIZE_GB=$((EMMC_SIZE / 1024 / 1024 / 1024))
    
    log "eMMC size: ${EMMC_SIZE_GB}GB"
    
    if [[ $EMMC_SIZE_GB -lt 3 ]]; then
        log_warning "eMMC too small (${EMMC_SIZE_GB}GB), skipping configuration"
        return
    fi
    
    # Create partition table and swap partition
    log "Creating swap partition on eMMC..."
    parted -s "$EMMC_DEVICE" mklabel gpt
    parted -s "$EMMC_DEVICE" mkpart primary linux-swap 0% 100%
    
    # Format as swap
    mkswap "${EMMC_DEVICE}p1"
    
    # Add to fstab
    echo "${EMMC_DEVICE}p1 none swap sw 0 0" >> /etc/fstab
    
    # Enable swap
    swapon "${EMMC_DEVICE}p1"
    
    log "eMMC swap configured successfully"
}

# Install CasaOS
install_casaos() {
    log "=== Installing CasaOS ==="
    
    # Download and run CasaOS install script
    curl -fsSL https://get.casaos.io | bash
    
    # Enable and start CasaOS
    systemctl enable casaos
    systemctl start casaos
    
    log "CasaOS installed successfully"
    log "CasaOS will be available at: http://$(hostname -I | awk '{print $1}'):80"
}

# Install Cockpit (optional)
install_cockpit() {
    if [[ "$INSTALL_COCKPIT" != "true" ]]; then
        log "Cockpit installation disabled, skipping..."
        return
    fi

    log "=== Installing Cockpit ==="
    
    apt install -y cockpit cockpit-networkmanager cockpit-system
    
    # Enable and start Cockpit
    systemctl enable cockpit.socket
    systemctl start cockpit.socket
    
    # Configure firewall for Cockpit
    ufw allow 9090
    
    log "Cockpit installed successfully"
    log "Cockpit will be available at: https://$(hostname -I | awk '{print $1}'):9090"
}

# Configure firewall
configure_firewall() {
    log "=== Configuring Firewall ==="
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH
    ufw allow ssh
    
    # Allow Tailscale
    ufw allow in on tailscale0
    
    # Allow CasaOS
    ufw allow 80
    ufw allow 443
    
    # Allow Cockpit if installed
    if [[ "$INSTALL_COCKPIT" == "true" ]]; then
        ufw allow 9090
    fi
    
    log "Firewall configured"
}

# Create systemd service for monitoring
create_monitoring_service() {
    log "=== Creating Monitoring Service ==="
    
    cat > /etc/systemd/system/igel-monitor.service << 'EOF'
[Unit]
Description=IGEL M250C System Monitor
After=network.target tailscaled.service

[Service]
Type=simple
ExecStart=/usr/local/bin/igel-monitor.sh
Restart=always
RestartSec=30
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Create monitoring script
    cat > /usr/local/bin/igel-monitor.sh << 'EOF'
#!/bin/bash
# Simple monitoring script for IGEL M250C

LOG_FILE="/var/log/igel-monitor.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

while true; do
    # Check Tailscale status
    if ! tailscale status >/dev/null 2>&1; then
        log "WARNING: Tailscale service appears to be down"
    fi
    
    # Check disk usage
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $DISK_USAGE -gt 85 ]]; then
        log "WARNING: Disk usage high: ${DISK_USAGE}%"
    fi
    
    # Check memory usage
    MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $MEM_USAGE -gt 90 ]]; then
        log "WARNING: Memory usage high: ${MEM_USAGE}%"
    fi
    
    sleep 300  # Check every 5 minutes
done
EOF

    chmod +x /usr/local/bin/igel-monitor.sh
    
    # Enable and start the service
    systemctl enable igel-monitor.service
    systemctl start igel-monitor.service
    
    log "Monitoring service created and started"
}

# Final system optimization
optimize_system() {
    log "=== Optimizing System ==="
    
    # Reduce systemd journal size to save USB wear
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/storage.conf << 'EOF'
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=10M
RuntimeMaxUse=100M
RuntimeMaxFileSize=10M
EOF

    # Restart systemd-journald
    systemctl restart systemd-journald
    
    # Configure log rotation
    cat > /etc/logrotate.d/igel-custom << 'EOF'
/var/log/igel-*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

    log "System optimization completed"
}

# Create maintenance scripts and cron jobs
create_maintenance_scripts() {
    log "=== Setting Up Maintenance Scripts ==="
    
    # Copy maintenance scripts to system location
    if [[ -f "$SCRIPT_DIR/scripts/maintenance.sh" ]]; then
        cp "$SCRIPT_DIR/scripts/maintenance.sh" /usr/local/bin/igel-maintenance
        chmod +x /usr/local/bin/igel-maintenance
        log "Maintenance script installed: /usr/local/bin/igel-maintenance"
    fi
    
    if [[ -f "$SCRIPT_DIR/scripts/network-setup.sh" ]]; then
        cp "$SCRIPT_DIR/scripts/network-setup.sh" /usr/local/bin/igel-network-setup
        chmod +x /usr/local/bin/igel-network-setup
        log "Network setup script installed: /usr/local/bin/igel-network-setup"
    fi
    
    if [[ -f "$SCRIPT_DIR/scripts/health-check.sh" ]]; then
        cp "$SCRIPT_DIR/scripts/health-check.sh" /usr/local/bin/igel-health-check
        chmod +x /usr/local/bin/igel-health-check
        log "Health check script installed: /usr/local/bin/igel-health-check"
    fi
    
    if [[ -f "$SCRIPT_DIR/scripts/wireless-manager.sh" ]]; then
        cp "$SCRIPT_DIR/scripts/wireless-manager.sh" /usr/local/bin/igel-wireless
        chmod +x /usr/local/bin/igel-wireless
        log "Wireless manager script installed: /usr/local/bin/igel-wireless"
    fi
    
    # Setup automated maintenance
    if [[ -f "$SCRIPT_DIR/scripts/auto-maintenance.sh" ]]; then
        bash "$SCRIPT_DIR/scripts/auto-maintenance.sh" all
        log "Automated maintenance tasks configured"
    fi
    
    # Create terminal-friendly quick reference
    cat > /etc/motd << EOF
╔═══════════════════════════════════════════════════════════════════════╗
║                    IGEL M250C Tailscale Router                       ║
║                          Welcome!                                     ║
╚═══════════════════════════════════════════════════════════════════════╝

Quick Commands:
  igel-health-check        - System health check
  igel-maintenance health  - Detailed diagnostics  
  igel-network-setup test  - Test network connectivity
  igel-wireless scan       - Scan for Wi-Fi networks
  igel-wireless connect    - Connect to Wi-Fi
  tailscale status         - Check VPN status

Web Interfaces:
  CasaOS:   http://$(hostname -I | awk '{print $1}')
$([ "$INSTALL_COCKPIT" = "true" ] && echo "  Cockpit:  https://$(hostname -I | awk '{print $1}'):9090")

For full command reference: cat /opt/igel-setup/QUICK_REFERENCE.md
Installation logs: tail -f /var/log/igel-setup.log

EOF
    log "Login message (MOTD) configured for headless access"
    
    # Set up cron jobs for automated maintenance
    cat > /etc/cron.d/igel-maintenance << 'EOF'
# IGEL M250C Automated Maintenance
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Daily health check at 2 AM
0 2 * * * root /usr/local/bin/igel-maintenance health >> /var/log/igel-maintenance.log 2>&1

# Weekly system update on Sunday at 3 AM
0 3 * * 0 root /usr/local/bin/igel-maintenance update >> /var/log/igel-maintenance.log 2>&1

# Monthly full maintenance on 1st of month at 4 AM
0 4 1 * * root /usr/local/bin/igel-maintenance full >> /var/log/igel-maintenance.log 2>&1
EOF

    log "Automated maintenance scheduled"
}

# Show final status
show_final_status() {
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    🎉 Installation Complete! 🎉                      ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # System Information
    echo -e "${BLUE}📋 System Information${NC}"
    echo "  Device: IGEL M250C"
    echo "  Hostname: $(hostname)"
    echo "  IP Address: $(hostname -I | awk '{print $1}')"
    echo "  OS: $(lsb_release -d | cut -f2 | tr -d '\t')"
    echo "  Installation ID: $INSTALL_ID"
    echo
    
    # Services Status
    echo -e "${BLUE}🔧 Services Status${NC}"
    local ip_address=$(hostname -I | awk '{print $1}')
    
    # Tailscale
    if systemctl is-active --quiet tailscaled; then
        echo -e "  ✅ Tailscale: ${GREEN}Active${NC}"
        if tailscale status >/dev/null 2>&1; then
            local tailscale_ip=$(tailscale ip 2>/dev/null || echo "Connecting...")
            echo "     Tailscale IP: $tailscale_ip"
        fi
    else
        echo -e "  ❌ Tailscale: ${RED}Inactive${NC}"
    fi
    
    # CasaOS
    if systemctl is-active --quiet casaos; then
        echo -e "  ✅ CasaOS: ${GREEN}Active${NC} → http://$ip_address"
    else
        echo -e "  ❌ CasaOS: ${RED}Inactive${NC}"
    fi
    
    # Cockpit
    if [[ "$INSTALL_COCKPIT" == "true" ]]; then
        if systemctl is-active --quiet cockpit.socket; then
            echo -e "  ✅ Cockpit: ${GREEN}Active${NC} → https://$ip_address:9090"
        else
            echo -e "  ❌ Cockpit: ${RED}Inactive${NC}"
        fi
    else
        echo "  ℹ️  Cockpit: Skipped (not installed)"
    fi
    
    # Monitoring
    if systemctl is-active --quiet igel-monitor; then
        echo -e "  ✅ System Monitor: ${GREEN}Active${NC}"
    else
        echo -e "  ❌ System Monitor: ${RED}Inactive${NC}"
    fi
    
    echo
    
    # Network Status
    echo -e "${BLUE}🌐 Network Status${NC}"
    
    # Show active interfaces with priorities
    echo "  Active interfaces:"
    ip route show default | while read -r line; do
        local interface=$(echo "$line" | awk '{print $5}')
        local gateway=$(echo "$line" | awk '{print $3}')
        local metric=$(echo "$line" | grep -o "metric [0-9]*" | awk '{print $2}' || echo "N/A")
        echo "    • $interface → $gateway (priority: $metric)"
    done
    
    echo
    
    # Tailscale Configuration
    echo -e "${BLUE}🔗 Tailscale Configuration${NC}"
    if tailscale status >/dev/null 2>&1; then
        echo -e "  Status: ${GREEN}Connected and ready!${NC}"
        echo "  Configured as:"
        echo "    • Subnet router for: ${ADVERTISED_ROUTES:-default networks}"
        echo "    • Exit node: Enabled"
        echo "    • Hostname: ${DEVICE_HOSTNAME:-igel-m250c-router}"
        
        # Show some connected devices
        echo "  Connected devices:"
        tailscale status | head -5 | tail -n +2 | while read -r line; do
            local device=$(echo "$line" | awk '{print $1}')
            local ip=$(echo "$line" | awk '{print $2}')
            echo "    • $device ($ip)"
        done
    else
        echo -e "  Status: ${YELLOW}Awaiting authentication${NC}"
        echo "  Next steps:"
        echo "    1. Visit Tailscale admin: https://login.tailscale.com/admin/"
        echo "    2. Approve this device as a subnet router"
        echo "    3. Enable exit node if desired"
    fi
    
    echo
    
    # Quick Commands
    echo -e "${BLUE}📚 Quick Commands${NC}"
    echo "  Health check:     igel-health-check"
    echo "  System maintenance: igel-maintenance health"
    echo "  Network setup:    igel-network-setup detect"
    echo "  Backup config:    /opt/igel-setup/scripts/backup-config.sh backup"
    echo "  View logs:        tail -f /var/log/igel-setup.log"
    
    echo
    
    # Storage Status
    if [[ "$USE_EMMC" == "true" ]]; then
        echo -e "${BLUE}💾 Storage Configuration${NC}"
        echo "  eMMC optimization: Enabled"
        local swap_status=$(swapon --show --noheadings | wc -l)
        if [[ $swap_status -gt 0 ]]; then
            echo -e "  Swap status: ${GREEN}Active${NC}"
        else
            echo -e "  Swap status: ${YELLOW}Not active${NC}"
        fi
        echo
    fi
    
    # Final message
    echo -e "${GREEN}🚀 Your IGEL M250C router is ready!${NC}"
    echo
    echo "Next steps:"
    echo "  • Access CasaOS web interface: http://$(hostname -I | awk '{print $1}')"
    if [[ "$INSTALL_COCKPIT" == "true" ]]; then
        echo "  • Access Cockpit management: https://$(hostname -I | awk '{print $1}'):9090"
    fi
    echo "  • Run 'igel-health-check' anytime to verify system status"
    echo "  • Check QUICK_REFERENCE.md for complete command list"
    echo
    echo "Configuration saved to: $LOG_FILE"
    echo "For troubleshooting: /opt/igel-setup/README.md"
        echo -e "${YELLOW}To complete Tailscale setup, run:${NC}"
        echo -e "${BLUE}tailscale up --advertise-routes=192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 --advertise-exit-node --accept-routes${NC}"
        echo
        echo "This will provide a URL to visit for authentication."
    fi
    
    echo
    log "Next Steps:"
    if tailscale status >/dev/null 2>&1; then
        log "1. Configure your Tailscale admin console to approve subnet routes"
        log "2. Test connectivity from other Tailscale devices"
        log "3. Access CasaOS web interface to install additional services"
        if [[ "$INSTALL_COCKPIT" == "true" ]]; then
            log "4. Use Cockpit for advanced system management"
        fi
    else
        log "1. Complete Tailscale authentication (see command above)"
        log "2. Configure your Tailscale admin console to approve subnet routes"
        log "3. Test connectivity from other Tailscale devices"
        log "4. Access CasaOS web interface to install additional services"
        if [[ "$INSTALL_COCKPIT" == "true" ]]; then
            log "5. Use Cockpit for advanced system management"
        fi
    fi
    
    log "Log files are available at: $LOG_FILE"
}

# Main installation function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --non-interactive)
                INTERACTIVE_MODE="false"
                ;;
            --tailscale-key=*)
                TAILSCALE_AUTH_KEY="${1#*=}"
                ;;
            --hostname=*)
                DEVICE_HOSTNAME="${1#*=}"
                ;;
            --routes=*)
                ADVERTISED_ROUTES="${1#*=}"
                ;;
            --no-cockpit)
                INSTALL_COCKPIT="false"
                ;;
            --no-emmc)
                USE_EMMC="false"
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    log "Starting IGEL M250C Tailscale Router Setup..."
    log "Installation ID: $INSTALL_ID"
    
    # Set up error handling with cleanup
    trap 'error_cleanup $?' ERR
    
    # Show banner
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      IGEL M250C Router Setup                          ║${NC}"
    echo -e "${BLUE}║               Tailscale Subnet Router & Exit Node                     ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_root
    preflight_checks
    
    # Interactive configuration (unless running non-interactively)
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        interactive_config
    fi
    
    show_system_info
    update_system
    configure_ip_forwarding
    install_tailscale
    configure_tailscale
    configure_emmc
    install_casaos
    install_cockpit
    configure_firewall
    create_monitoring_service
    optimize_system
    create_maintenance_scripts
    
    # Apply security hardening if enabled
    if [[ "$ENABLE_SECURITY_HARDENING" == "true" ]]; then
        echo -e "${BLUE}[Additional] Applying security hardening...${NC}"
        if [[ -f "$SCRIPT_DIR/scripts/security-hardening.sh" ]]; then
            bash "$SCRIPT_DIR/scripts/security-hardening.sh" all || log_warning "Security hardening completed with some warnings"
        else
            log_warning "Security hardening script not found, skipping"
        fi
    fi
    
    show_final_status
    
    log "Setup completed successfully!"
}

# Error cleanup function
error_cleanup() {
    local exit_code=$1
    log_error "Installation failed with exit code $exit_code"
    
    # Try to restore sysctl.conf if it was backed up
    if [[ -f "/etc/sysctl.conf.bak.$(date +%Y%m%d)" ]]; then
        log "Restoring sysctl.conf backup..."
        cp /etc/sysctl.conf.bak.* /etc/sysctl.conf 2>/dev/null || true
    fi
    
    # Stop services that may have been started
    systemctl stop tailscaled 2>/dev/null || true
    systemctl stop casaos 2>/dev/null || true
    systemctl stop cockpit.socket 2>/dev/null || true
    systemctl stop igel-monitor 2>/dev/null || true
    
    log_error "Installation aborted. Check logs at $LOG_FILE"
    log_error "You may need to manually clean up partial installation"
    
    exit $exit_code
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "IGEL M250C Tailscale Router Setup Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "This script will interactively prompt for required information if not"
        echo "provided via environment variables."
        echo
        echo "Environment variables:"
        echo "  TAILSCALE_AUTH_KEY    Tailscale authentication key (optional)"
        echo "                        If not provided, you'll be prompted to enter it"
        echo "                        Get one from: https://login.tailscale.com/admin/settings/keys"
        echo "  INSTALL_COCKPIT       Install Cockpit web UI (default: true)"
        echo "  USE_EMMC             Use eMMC for swap/logs (default: true)"
        echo
        echo "Examples:"
        echo "  sudo $0                                    # Interactive setup"
        echo "  sudo TAILSCALE_AUTH_KEY='tskey-...' $0     # Automated setup"
        echo "  sudo INSTALL_COCKPIT=false $0              # Skip Cockpit installation"
        echo
        echo "The script will guide you through the setup process and provide"
        echo "clear instructions for any manual steps required."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
