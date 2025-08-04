#!/bin/bash

# IGEL M250C Tailscale Subnet Router Setup Script
# This script configures an IGEL M250C thin client as a headless Tailscale subnet router
# and exit node using USB-booted Debian 12
#
# REQUIRED: Only Tailscale installation is mandatory
# OPTIONAL: All other features (CasaOS, Cockpit, monitoring, etc.) are optional
#
# Usage:
#   sudo ./install.sh                    # Interactive setup
#   sudo ./install.sh --minimal          # Tailscale only  
#   sudo ./install.sh --full             # All features
#   sudo ./install.sh --help             # Show all options

set -euo pipefail

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/igel-setup.log"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
INSTALL_COCKPIT="${INSTALL_COCKPIT:-}"
INSTALL_CASAOS="${INSTALL_CASAOS:-}"
INSTALL_HEADSCALE="${INSTALL_HEADSCALE:-}"
INSTALL_HEADPLANE="${INSTALL_HEADPLANE:-}"
INSTALL_DASHBOARD="${INSTALL_DASHBOARD:-true}"
USE_EMMC="${USE_EMMC:-}"
DEVICE_HOSTNAME="${DEVICE_HOSTNAME:-}"
ADVERTISED_ROUTES="${ADVERTISED_ROUTES:-}"
HEADSCALE_DOMAIN="${HEADSCALE_DOMAIN:-}"
HEADSCALE_LISTEN_PORT="${HEADSCALE_LISTEN_PORT:-8080}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8088}"
NETWORK_INTERFACE_MODE="${NETWORK_INTERFACE_MODE:-auto}"
INTERACTIVE_MODE="${INTERACTIVE_MODE:-true}"
ENABLE_SECURITY_HARDENING="${ENABLE_SECURITY_HARDENING:-}"
ENABLE_MONITORING="${ENABLE_MONITORING:-}"
ENABLE_MAINTENANCE_SCRIPTS="${ENABLE_MAINTENANCE_SCRIPTS:-}"
ENABLE_SYSTEM_OPTIMIZATION="${ENABLE_SYSTEM_OPTIMIZATION:-}"
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
    if [[ -n "$TAILSCALE_AUTH_KEY" && -n "$INSTALL_COCKPIT" && -n "$INSTALL_CASAOS" && -n "$USE_EMMC" && -n "$DEVICE_HOSTNAME" && -n "$ENABLE_SECURITY_HARDENING" ]]; then
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
    echo "Tailscale subnet router. Only Tailscale is required - all other features are optional."
    echo "You can press Enter to use default values or skip optional features."
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
    
    # Web management interfaces
    if [[ -z "$INSTALL_CASAOS" ]]; then
        echo -e "${YELLOW}Web Management Interface - CasaOS${NC}"
        echo "CasaOS provides a user-friendly web interface for managing Docker containers and services:"
        echo "  • Easy Docker container management"
        echo "  • App store for common applications"
        echo "  • File management and media server capabilities"
        echo
        while true; do
            read -p "Install CasaOS for container management? [Y/n]: " -n 1 -r casaos_choice
            echo
            case $casaos_choice in
                [Yy]|"") INSTALL_CASAOS="true"; break ;;
                [Nn]) INSTALL_CASAOS="false"; break ;;
                *) echo "Please answer Y or n" ;;
            esac
        done
        echo
    fi
    
    # Cockpit installation
    if [[ -z "$INSTALL_COCKPIT" ]]; then
        echo -e "${YELLOW}Web Management Interface - Cockpit${NC}"
        echo "Cockpit provides advanced system management capabilities:"
        echo "  • System monitoring and performance metrics"
        echo "  • Network configuration and firewall management"
        echo "  • Service management and log viewing"
        echo "  • Terminal access and file management"
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
        echo "Configure which networks this router will advertise to VPN clients:"
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
    
    # Headscale installation
    if [[ -z "$INSTALL_HEADSCALE" ]]; then
        echo -e "${YELLOW}Self-Hosted VPN Server - Headscale${NC}"
        echo "Headscale is a self-hosted, open-source implementation of the Tailscale coordination server:"
        echo "  • Full control over your VPN infrastructure"
        echo "  • No reliance on external Tailscale service"
        echo "  • Custom domain and branding"
        echo "  • Advanced access controls and policies"
        echo "  • Includes Headplane web UI for management"
        echo
        echo "⚠️  Note: Installing Headscale will make this device a VPN server."
        echo "   Clients will connect to THIS device instead of Tailscale's servers."
        echo
        while true; do
            read -p "Install Headscale server for self-hosted VPN? [y/N]: " -n 1 -r headscale_choice
            echo
            case $headscale_choice in
                [Yy]) 
                    INSTALL_HEADSCALE="true"
                    
                    # Get domain for Headscale
                    echo
                    echo "Headscale requires a domain name for clients to connect."
                    echo "This can be:"
                    echo "  • Your router's IP address (e.g., 192.168.1.100)"
                    echo "  • A domain name pointing to this router (e.g., vpn.yourdomain.com)"
                    echo "  • A dynamic DNS hostname"
                    echo
                    read -p "Enter domain/IP for Headscale [$(hostname -I | awk '{print $1}')]: " -r domain_input
                    HEADSCALE_DOMAIN="${domain_input:-$(hostname -I | awk '{print $1}')}"
                    
                    echo
                    read -p "Enter port for Headscale [8080]: " -r port_input
                    HEADSCALE_LISTEN_PORT="${port_input:-8080}"
                    
                    # Ask about Headplane web UI
                    echo
                    echo "Headplane provides a web-based UI for managing Headscale:"
                    echo "  • Device management and monitoring"
                    echo "  • User and access control management"
                    echo "  • Network topology visualization"
                    echo "  • Route and policy configuration"
                    echo
                    while true; do
                        read -p "Install Headplane web UI? [Y/n]: " -n 1 -r headplane_choice
                        echo
                        case $headplane_choice in
                            [Yy]|"") INSTALL_HEADPLANE="true"; break ;;
                            [Nn]) INSTALL_HEADPLANE="false"; break ;;
                            *) echo "Please answer Y or n" ;;
                        esac
                    done
                    break
                    ;;
                [Nn]|"") 
                    INSTALL_HEADSCALE="false"
                    INSTALL_HEADPLANE="false"
                    break
                    ;;
                *) echo "Please answer y or N" ;;
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
            read -p "Enable additional security hardening? [y/N]: " -n 1 -r security_choice
            echo
            case $security_choice in
                [Yy]) ENABLE_SECURITY_HARDENING="true"; break ;;
                [Nn]|"") ENABLE_SECURITY_HARDENING="false"; break ;;
                *) echo "Please answer y or N" ;;
            esac
        done
        echo
    fi
    
    if [[ -z "$ENABLE_MONITORING" ]]; then
        echo -e "${YELLOW}System Monitoring${NC}"
        echo "Install system monitoring service that tracks:"
        echo "  • Tailscale connectivity status"
        echo "  • Disk and memory usage"
        echo "  • Service health and performance"
        echo "  • Automated log collection"
        echo
        while true; do
            read -p "Enable system monitoring service? [y/N]: " -n 1 -r monitor_choice
            echo
            case $monitor_choice in
                [Yy]) ENABLE_MONITORING="true"; break ;;
                [Nn]|"") ENABLE_MONITORING="false"; break ;;
                *) echo "Please answer y or N" ;;
            esac
        done
        echo
    fi
    
    if [[ -z "$ENABLE_MAINTENANCE_SCRIPTS" ]]; then
        echo -e "${YELLOW}Automated Maintenance${NC}"
        echo "Install maintenance scripts and automated tasks for:"
        echo "  • System health checks and diagnostics"
        echo "  • Automated backups and updates"
        echo "  • Network connectivity monitoring"
        echo "  • Log rotation and cleanup"
        echo
        while true; do
            read -p "Install maintenance scripts and automation? [y/N]: " -n 1 -r maintenance_choice
            echo
            case $maintenance_choice in
                [Yy]) ENABLE_MAINTENANCE_SCRIPTS="true"; break ;;
                [Nn]|"") ENABLE_MAINTENANCE_SCRIPTS="false"; break ;;
                *) echo "Please answer y or N" ;;
            esac
        done
        echo
    fi
    
    if [[ -z "$ENABLE_SYSTEM_OPTIMIZATION" ]]; then
        echo -e "${YELLOW}System Optimization${NC}"
        echo "Apply system optimizations for router performance:"
        echo "  • Reduced logging to preserve USB drive"
        echo "  • Optimized kernel parameters for networking"
        echo "  • Memory and swap optimizations"
        echo "  • Log rotation and journald configuration"
        echo
        while true; do
            read -p "Apply system optimizations? [y/N]: " -n 1 -r optimization_choice
            echo
            case $optimization_choice in
                [Yy]) ENABLE_SYSTEM_OPTIMIZATION="true"; break ;;
                [Nn]|"") ENABLE_SYSTEM_OPTIMIZATION="false"; break ;;
                *) echo "Please answer y or N" ;;
            esac
        done
        echo
    fi
    echo -e "${GREEN}║                        Configuration Summary                          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "Device Hostname: $DEVICE_HOSTNAME"
    echo "Use eMMC Storage: ${USE_EMMC:-false}"
    echo "Install CasaOS: ${INSTALL_CASAOS:-false}"
    echo "Install Cockpit: ${INSTALL_COCKPIT:-false}"
    echo "Install Headscale Server: ${INSTALL_HEADSCALE:-false}"
    if [[ "$INSTALL_HEADSCALE" == "true" ]]; then
        echo "  Headscale Domain: ${HEADSCALE_DOMAIN}"
        echo "  Headscale Port: ${HEADSCALE_LISTEN_PORT}"
        echo "  Install Headplane UI: ${INSTALL_HEADPLANE:-false}"
    fi
    echo "Network Interface Mode: $NETWORK_INTERFACE_MODE"
    echo "Security Hardening: ${ENABLE_SECURITY_HARDENING:-false}"
    echo "System Monitoring: ${ENABLE_MONITORING:-false}"
    echo "Maintenance Scripts: ${ENABLE_MAINTENANCE_SCRIPTS:-false}"
    echo "System Optimization: ${ENABLE_SYSTEM_OPTIMIZATION:-false}"
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
and exit node running Debian 12 from a USB drive. Only Tailscale is required - all
other features are optional.

USAGE:
    sudo ./install.sh [OPTIONS]

OPTIONS:
    -h, --help                 Show this help message
    --non-interactive          Run in non-interactive mode (requires environment variables)
    --tailscale-key=KEY        Tailscale auth key (starts with tskey-auth-)
    --hostname=NAME            Device hostname (default: igel-m250c-router)
    --routes=ROUTES            Comma-separated CIDR routes to advertise
    
    Headscale Self-Hosted VPN Options:
    --headscale                Enable Headscale server installation
    --headscale-domain=DOMAIN  Domain/IP for Headscale server (required with --headscale)
    --headscale-port=PORT      Headscale listen port (default: 8080)
    --headplane                Enable Headplane web UI (requires --headscale)
    --no-headscale             Disable Headscale installation (default)
    
    Optional Feature Controls:
    --no-casaos                Skip CasaOS installation (Docker web UI)
    --no-cockpit               Skip Cockpit installation (system management)
    --no-emmc                  Skip eMMC storage configuration
    --no-security              Skip security hardening
    --no-monitoring            Skip system monitoring service
    --no-maintenance           Skip maintenance scripts and automation
    --no-optimization          Skip system optimizations
    
    Preset Configurations:
    --minimal                  Minimal install (Tailscale only)
    --full                     Full install (all features enabled)

EXAMPLES:
    # Interactive installation (recommended):
    sudo ./install.sh

    # Minimal installation (Tailscale only):
    sudo ./install.sh --minimal

    # Full installation (all features):
    sudo ./install.sh --full

    # Custom installation with specific features:
    sudo ./install.sh --no-casaos --no-cockpit --hostname=my-router

    # Non-interactive with custom configuration:
    sudo ./install.sh --non-interactive --minimal \\
        --tailscale-key=tskey-auth-your-key-here \\
        --hostname=office-router \\
        --routes=192.168.1.0/24,10.0.0.0/8

ENVIRONMENT VARIABLES:
    You can also set configuration via environment variables:
    
    TAILSCALE_AUTH_KEY           Your Tailscale auth key
    DEVICE_HOSTNAME              Device hostname  
    ADVERTISED_ROUTES            Comma-separated routes
    INSTALL_CASAOS               true/false (install CasaOS)
    INSTALL_COCKPIT              true/false (install Cockpit)
    USE_EMMC                     true/false (use eMMC storage)
    ENABLE_SECURITY_HARDENING    true/false (security hardening)
    ENABLE_MONITORING            true/false (system monitoring)
    ENABLE_MAINTENANCE_SCRIPTS   true/false (maintenance automation)
    ENABLE_SYSTEM_OPTIMIZATION   true/false (system optimizations)
    INTERACTIVE_MODE             true/false (enable interactive prompts)

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

# Create app-services user for running services
create_app_user() {
    log "=== Creating app-services User ==="
    
    # Create app-services user with home directory
    if ! id "app-services" &>/dev/null; then
        useradd -m -s /bin/bash -c "Application Services User" app-services
        log "Created app-services user"
        
        # Add to necessary groups for service management
        usermod -a -G docker app-services 2>/dev/null || true  # Will be added later when Docker is installed
        usermod -a -G systemd-journal app-services
        
        # Create .ssh directory for potential key-based access
        mkdir -p /home/app-services/.ssh
        chmod 700 /home/app-services/.ssh
        chown app-services:app-services /home/app-services/.ssh
        
        # Set up basic environment
        cat > /home/app-services/.bashrc << 'EOF'
# .bashrc for app-services user

# Source global definitions
if [ -f /etc/bash.bashrc ]; then
    . /etc/bash.bashrc
fi

# User specific aliases and functions
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add local bin to PATH for custom scripts
export PATH="$HOME/.local/bin:$PATH"

# Tailscale status shortcut
alias ts='tailscale status'

# IGEL router management shortcuts
alias router-status='sudo systemctl status tailscaled casaos cockpit.socket igel-monitor 2>/dev/null'
alias router-health='sudo /usr/local/bin/igel-health-check 2>/dev/null || echo "Health check not installed"'

echo "Welcome to IGEL M250C Router - app-services user"
echo "Use 'router-status' to check service status"
EOF
        
        chown app-services:app-services /home/app-services/.bashrc
        
        # Add app-services to sudo group with limited permissions
        cat > /etc/sudoers.d/app-services << 'EOF'
# Allow app-services user to manage specific services without password
app-services ALL=(ALL) NOPASSWD: /bin/systemctl status *, /bin/systemctl start casaos, /bin/systemctl stop casaos, /bin/systemctl restart casaos
app-services ALL=(ALL) NOPASSWD: /bin/systemctl start cockpit.socket, /bin/systemctl stop cockpit.socket, /bin/systemctl restart cockpit.socket
app-services ALL=(ALL) NOPASSWD: /usr/bin/tailscale status, /usr/bin/tailscale ip, /usr/bin/tailscale netcheck
app-services ALL=(ALL) NOPASSWD: /usr/local/bin/igel-*, /usr/local/bin/router-*
app-services ALL=(ALL) NOPASSWD: /bin/cat /var/log/igel-*.log, /bin/tail /var/log/igel-*.log
app-services ALL=(ALL) NOPASSWD: /bin/journalctl -u tailscaled, /bin/journalctl -u casaos, /bin/journalctl -u cockpit.socket
EOF
        
        log "Configured sudo permissions for app-services user"
    else
        log "app-services user already exists, skipping creation"
    fi
}

# Update system packages
update_system() {
    log "=== Updating System Packages ==="
    apt update
    apt upgrade -y
    
    # Install essential system utilities for minimal Debian
    apt install -y \
        sudo \
        nano \
        vim-tiny \
        curl \
        wget \
        gnupg \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        systemd \
        systemd-timesyncd \
        iptables \
        iptables-persistent \
        ufw \
        fail2ban \
        htop \
        tree \
        less \
        git \
        unzip \
        zip \
        rsync \
        cron \
        logrotate \
        openssh-server \
        openssh-client \
        dbus \
        network-manager \
        modemmanager \
        usb-modeswitch \
        usb-modeswitch-data \
        wireless-tools \
        wpasupplicant \
        rfkill \
        iw \
        network-manager-config-connectivity-debian \
        python3 \
        python3-pip \
        python3-venv \
        build-essential \
        pkg-config \
        lsb-release \
        procps \
        psmisc \
        file \
        findutils \
        grep \
        sed \
        awk \
        bc \
        jq
    
    # Install Docker prerequisites
    apt install -y \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key and repository for CasaOS
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update again and install Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl enable docker
    systemctl start docker
    
    # Add app-services user to docker group
    usermod -a -G docker app-services
    
    # Configure SSH for security
    if [[ -f /etc/ssh/sshd_config ]]; then
        # Backup original SSH config
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)
        
        # Basic SSH hardening
        sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        
        # Allow app-services user SSH access
        echo "AllowUsers root app-services" >> /etc/ssh/sshd_config
        
        systemctl restart ssh
    fi
    
    # Enable time synchronization
    systemctl enable systemd-timesyncd
    systemctl start systemd-timesyncd
    
    log "System packages updated and essential services configured"
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

# Connection tracking for NAT (will be applied after netfilter modules are loaded)
net.netfilter.nf_conntrack_max = 65536
EOF
    
    # Apply immediately (ignore errors for parameters that can't be set yet)
    sysctl -p || log_warning "Some sysctl parameters couldn't be applied yet (normal during installation)"
    
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

# Install Headscale server
install_headscale() {
    if [[ "$INSTALL_HEADSCALE" != "true" ]]; then
        log "Headscale installation disabled, skipping..."
        return
    fi

    log "=== Installing Headscale Server ==="
    
    # Create headscale user
    useradd -r -s /bin/false -d /var/lib/headscale headscale || true
    
    # Create directories
    mkdir -p /etc/headscale
    mkdir -p /var/lib/headscale
    mkdir -p /var/log/headscale
    chown headscale:headscale /var/lib/headscale /var/log/headscale
    
    # Download latest Headscale binary
    log "Downloading Headscale binary..."
    HEADSCALE_VERSION=$(curl -s https://api.github.com/repos/juanfont/headscale/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    HEADSCALE_URL="https://github.com/juanfont/headscale/releases/download/${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION#v}_linux_amd64"
    
    curl -fsSL "$HEADSCALE_URL" -o /usr/local/bin/headscale
    chmod +x /usr/local/bin/headscale
    
    # Create Headscale configuration
    log "Configuring Headscale..."
    cat > /etc/headscale/config.yaml << EOF
# Headscale configuration for IGEL M250C Router
server_url: http://${HEADSCALE_DOMAIN}:${HEADSCALE_LISTEN_PORT}
listen_addr: 0.0.0.0:${HEADSCALE_LISTEN_PORT}
metrics_listen_addr: 127.0.0.1:9090

# Database
db_type: sqlite3
db_path: /var/lib/headscale/db.sqlite

# TLS disabled for internal use
tls_cert_path: ""
tls_key_path: ""

# Network settings
ip_prefixes:
  - fd7a:115c:a1e0::/48
  - 100.64.0.0/10

# DNS settings
dns_config:
  override_local_dns: true
  nameservers:
    - 1.1.1.1
    - 8.8.8.8
  domains: []
  magic_dns: true
  base_domain: ${HEADSCALE_DOMAIN}

# Logging
log_level: info

# DERP (NAT traversal) - use Tailscale's DERP servers
derp:
  server:
    enabled: false

# Policy and ACLs
policy:
  path: /etc/headscale/acl.hujson

# Unix socket for CLI
unix_socket: /var/run/headscale/headscale.sock

# Ephemeral nodes
ephemeral_node_inactivity_timeout: 30m

# Node update check interval
node_update_check_interval: 10s
EOF

    # Create ACL policy file
    cat > /etc/headscale/acl.hujson << 'EOF'
{
  // Default ACL for IGEL Router - Allow all traffic
  "acls": [
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["*:*"]
    }
  ],
  
  // Tags for organizing devices
  "tagOwners": {
    "tag:router": ["autogroup:admin"],
    "tag:client": ["autogroup:admin"],
    "tag:server": ["autogroup:admin"]
  },
  
  // Advertised routes - matches router configuration
  "autoApprovers": {
    "routes": {
      "192.168.0.0/16": ["tag:router"],
      "10.0.0.0/8": ["tag:router"],
      "172.16.0.0/12": ["tag:router"]
    },
    "exitNode": ["tag:router"]
  }
}
EOF

    # Create systemd service
    cat > /etc/systemd/system/headscale.service << 'EOF'
[Unit]
Description=Headscale VPN coordination server
Documentation=https://headscale.net
After=syslog.target
After=network.target

[Service]
Type=simple
User=headscale
Group=headscale
ExecStart=/usr/local/bin/headscale serve
ExecReload=/bin/kill -HUP $MAINPID
WorkingDirectory=/var/lib/headscale
ReadWritePaths=/var/lib/headscale /var/log/headscale
TimeoutStopSec=5
KillMode=mixed
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

    # Create runtime directory for socket
    mkdir -p /var/run/headscale
    chown headscale:headscale /var/run/headscale
    
    # Enable and start Headscale
    systemctl daemon-reload
    systemctl enable headscale
    systemctl start headscale
    
    # Wait for service to start
    sleep 5
    
    # Create initial namespace/user
    log "Creating default namespace..."
    /usr/local/bin/headscale namespaces create default || true
    
    # Add app-services user permissions for headscale commands
    cat >> /etc/sudoers.d/app-services << 'EOF'

# Headscale management
app-services ALL=(ALL) NOPASSWD: /usr/local/bin/headscale *
app-services ALL=(ALL) NOPASSWD: /bin/systemctl status headscale, /bin/systemctl restart headscale
app-services ALL=(ALL) NOPASSWD: /bin/journalctl -u headscale
EOF

    log "Headscale server installed and started"
    log "Headscale will be available at: http://${HEADSCALE_DOMAIN}:${HEADSCALE_LISTEN_PORT}"
    log "Use 'headscale' command to manage users and devices"
}

# Install Headplane web UI
install_headplane() {
    if [[ "$INSTALL_HEADPLANE" != "true" || "$INSTALL_HEADSCALE" != "true" ]]; then
        log "Headplane installation disabled or Headscale not installed, skipping..."
        return
    fi

    log "=== Installing Headplane Web UI ==="
    
    # Headplane runs as a Docker container, so ensure Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is required for Headplane but not installed"
        return
    fi
    
    # Create Headplane data directory
    mkdir -p /var/lib/headplane
    chown app-services:app-services /var/lib/headplane
    
    # Create Headplane Docker Compose configuration
    cat > /var/lib/headplane/docker-compose.yml << EOF
version: '3.8'

services:
  headplane:
    image: ghcr.io/tale/headplane:latest
    container_name: headplane
    restart: unless-stopped
    ports:
      - "3001:3000"
    environment:
      - HEADSCALE_URL=http://localhost:${HEADSCALE_LISTEN_PORT}
      - HEADSCALE_API_KEY_FILE=/data/headscale_api_key
    volumes:
      - /var/lib/headplane:/data
      - /var/run/headscale:/var/run/headscale:ro
    networks:
      - headplane-network
    depends_on:
      - headscale-proxy

  headscale-proxy:
    image: nginx:alpine
    container_name: headscale-proxy
    restart: unless-stopped
    ports:
      - "8081:80"
    volumes:
      - /var/lib/headplane/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - headplane-network

networks:
  headplane-network:
    driver: bridge
EOF

    # Create nginx configuration for Headscale proxy
    cat > /var/lib/headplane/nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream headscale {
        server host.docker.internal:${HEADSCALE_LISTEN_PORT};
    }

    server {
        listen 80;
        
        location / {
            proxy_pass http://headscale;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF

    # Generate API key for Headplane
    log "Generating Headscale API key for Headplane..."
    HEADSCALE_API_KEY=$(/usr/local/bin/headscale apikeys create --expiration 87600h 2>/dev/null | grep "^[a-zA-Z0-9]" || echo "")
    
    if [[ -n "$HEADSCALE_API_KEY" ]]; then
        echo "$HEADSCALE_API_KEY" > /var/lib/headplane/headscale_api_key
        chown app-services:app-services /var/lib/headplane/headscale_api_key
        chmod 600 /var/lib/headplane/headscale_api_key
    else
        log_warning "Failed to generate Headscale API key. Headplane may not work properly."
        echo "manual_setup_required" > /var/lib/headplane/headscale_api_key
    fi
    
    # Create systemd service for Headplane
    cat > /etc/systemd/system/headplane.service << 'EOF'
[Unit]
Description=Headplane Web UI
Requires=docker.service headscale.service
After=docker.service headscale.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/var/lib/headplane
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
User=app-services
Group=app-services

[Install]
WantedBy=multi-user.target
EOF

    # Start Headplane
    systemctl daemon-reload
    systemctl enable headplane
    
    # Change to headplane directory and start
    cd /var/lib/headplane
    docker-compose up -d
    
    log "Headplane web UI installed"
    log "Headplane will be available at: http://${HEADSCALE_DOMAIN}:3001"
    log "Headscale API proxy at: http://${HEADSCALE_DOMAIN}:8081"
}

# Install IGEL Dashboard
install_dashboard() {
    if [[ "$INSTALL_DASHBOARD" != "true" ]]; then
        log "Dashboard installation disabled, skipping..."
        return
    fi

    log "=== Installing IGEL M250C Dashboard ==="
    
    # Install Python and dependencies
    apt-get update
    apt-get install -y python3 python3-pip python3-venv
    
    # Copy dashboard files to system location
    local dashboard_dir="/opt/igel-setup/web-dashboard"
    
    if [[ ! -d "$dashboard_dir" ]]; then
        log_error "Dashboard files not found at $dashboard_dir"
        return 1
    fi
    
    # Make setup script executable
    chmod +x "$dashboard_dir/setup-dashboard.sh"
    
    # Run dashboard setup
    log "Setting up dashboard environment..."
    cd "$dashboard_dir"
    ./setup-dashboard.sh setup
    
    # Add dashboard to firewall
    ufw allow "$DASHBOARD_PORT"
    
    log "IGEL Dashboard installed successfully"
    log "Dashboard will be available at: http://$(hostname -I | awk '{print $1}'):$DASHBOARD_PORT"
    log "Default credentials: admin/admin123 and user/user123"
    log "Please change these default passwords!"
}

# Configure Tailscale
configure_tailscale() {
    log "=== Configuring Tailscale ==="
    
    # Check if we're using Headscale instead of Tailscale cloud
    if [[ "$INSTALL_HEADSCALE" == "true" ]] && systemctl is-active --quiet headscale; then
        log "Headscale detected, configuring for local server..."
        
        # Generate a pre-auth key for this node
        local namespace="default"
        local preauth_key
        
        # Create namespace if it doesn't exist
        headscale namespaces create "$namespace" 2>/dev/null || true
        
        # Generate pre-auth key
        preauth_key=$(headscale --user "$namespace" preauthkeys create --reusable --expiration 1h)
        
        if [[ -n "$preauth_key" ]]; then
            local routes="${ADVERTISED_ROUTES:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"
            local hostname="${DEVICE_HOSTNAME:-igel-m250c-router}"
            local headscale_url="http://localhost:${HEADSCALE_LISTEN_PORT:-8080}"
            
            log "Connecting to Headscale server at $headscale_url..."
            
            if tailscale up --login-server="$headscale_url" \
                --authkey="$preauth_key" \
                --advertise-routes="$routes" \
                --advertise-exit-node \
                --accept-routes \
                --hostname="$hostname"; then
                log "✓ Connected to Headscale server successfully!"
                log "  Hostname: $hostname"
                log "  Advertised routes: $routes"
                log "  Headscale server: $headscale_url"
            else
                log_error "Failed to connect to Headscale server"
                log_warning "You can manually connect later with:"
                log "tailscale up --login-server=$headscale_url --advertise-routes=$routes --advertise-exit-node --accept-routes --hostname=$hostname"
            fi
        else
            log_error "Failed to generate Headscale pre-auth key"
            log_warning "Manual configuration required for Headscale"
        fi
        
        log "Headscale configuration completed"
        return
    fi
    
    # Standard Tailscale cloud configuration
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
    
    # Ensure Docker is running and app-services user is in docker group
    systemctl enable docker
    systemctl start docker
    
    # Download and run CasaOS install script
    curl -fsSL https://get.casaos.io | bash
    
    # Configure CasaOS to run with app-services user context where appropriate
    # CasaOS runs as root but we'll create a service directory for app-services
    mkdir -p /home/app-services/casaos-data
    chown -R app-services:app-services /home/app-services/casaos-data
    
    # Create a convenience script for app-services user to manage containers
    cat > /home/app-services/.local/bin/casa-manage << 'EOF'
#!/bin/bash
# CasaOS container management helper for app-services user

case "$1" in
    "status")
        echo "=== CasaOS Service Status ==="
        sudo systemctl status casaos --no-pager
        echo
        echo "=== Docker Containers ==="
        docker ps -a
        ;;
    "logs")
        echo "=== CasaOS Logs ==="
        sudo journalctl -u casaos -n 50 --no-pager
        ;;
    "restart")
        echo "Restarting CasaOS..."
        sudo systemctl restart casaos
        ;;
    *)
        echo "Usage: casa-manage {status|logs|restart}"
        echo "  status  - Show CasaOS and container status"
        echo "  logs    - Show CasaOS service logs"
        echo "  restart - Restart CasaOS service"
        ;;
esac
EOF
    
    mkdir -p /home/app-services/.local/bin
    chown app-services:app-services /home/app-services/.local/bin/casa-manage
    chmod +x /home/app-services/.local/bin/casa-manage
    
    # Enable and start CasaOS
    systemctl enable casaos
    systemctl start casaos
    
    # Wait a moment for CasaOS to initialize
    sleep 10
    
    log "CasaOS installed successfully"
    log "CasaOS will be available at: http://$(hostname -I | awk '{print $1}'):80"
    log "app-services user can manage containers with: casa-manage status"
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
    
    # Allow Headscale ports if installed
    if [[ "$INSTALL_HEADSCALE" == "true" ]]; then
        ufw allow "${HEADSCALE_LISTEN_PORT:-8080}"
        log "Allowed Headscale port ${HEADSCALE_LISTEN_PORT:-8080}"
    fi
    
    # Allow Headplane ports if installed
    if [[ "$INSTALL_HEADPLANE" == "true" ]]; then
        ufw allow 3001
        ufw allow 8081
        log "Allowed Headplane ports 3001 and 8081"
    fi
    
    # Allow CasaOS
    ufw allow 80
    ufw allow 443
    
    # Allow Cockpit if installed
    if [[ "$INSTALL_COCKPIT" == "true" ]]; then
        ufw allow 9090
    fi
    
    # Allow Dashboard if installed
    if [[ "$INSTALL_DASHBOARD" == "true" ]]; then
        ufw allow "$DASHBOARD_PORT"
        log "Allowed Dashboard port $DASHBOARD_PORT"
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

Users:
  root         - Full system administration
  app-services - Service management and monitoring

For app-services user:
  casa-manage status   - Check CasaOS and containers
  router-status        - Check all router services
  router-health        - Run health diagnostics
  update-console       - Refresh physical console login screen

For full command reference: cat /opt/igel-setup/QUICK_REFERENCE.md
Installation logs: tail -f /var/log/igel-setup.log

EOF
    log "Login message (MOTD) configured for headless access"
    
    # Create dynamic login screen for physical console access
    cat > /usr/local/bin/update-login-screen << 'EOF'
#!/bin/bash
# Dynamic login screen updater for IGEL M250C

# Get current IP address
IP_ADDRESS=$(hostname -I | awk '{print $1}' || echo "No IP")
TAILSCALE_IP=$(tailscale ip 2>/dev/null || echo "Not connected")

# Check which services are installed and running
CASAOS_STATUS=""
COCKPIT_STATUS=""
HEADSCALE_STATUS=""
HEADPLANE_STATUS=""
DASHBOARD_STATUS=""

if systemctl is-enabled casaos >/dev/null 2>&1; then
    if systemctl is-active --quiet casaos; then
        CASAOS_STATUS="✅ CasaOS:    http://$IP_ADDRESS"
    else
        CASAOS_STATUS="❌ CasaOS:    http://$IP_ADDRESS (service stopped)"
    fi
fi

if systemctl is-enabled cockpit.socket >/dev/null 2>&1; then
    if systemctl is-active --quiet cockpit.socket; then
        COCKPIT_STATUS="✅ Cockpit:   https://$IP_ADDRESS:9090"
    else
        COCKPIT_STATUS="❌ Cockpit:   https://$IP_ADDRESS:9090 (service stopped)"
    fi
fi

if systemctl is-enabled headscale >/dev/null 2>&1; then
    if systemctl is-active --quiet headscale; then
        HEADSCALE_STATUS="✅ Headscale: http://$IP_ADDRESS:$(grep listen_addr /etc/headscale/config.yaml | grep -o '[0-9]*' | tail -1 2>/dev/null || echo '8080')"
    else
        HEADSCALE_STATUS="❌ Headscale: http://$IP_ADDRESS:$(grep listen_addr /etc/headscale/config.yaml | grep -o '[0-9]*' | tail -1 2>/dev/null || echo '8080') (service stopped)"
    fi
fi

if systemctl is-enabled headplane >/dev/null 2>&1; then
    if systemctl is-active --quiet headplane; then
        HEADPLANE_STATUS="✅ Headplane: http://$IP_ADDRESS:3001"
    else
        HEADPLANE_STATUS="❌ Headplane: http://$IP_ADDRESS:3001 (service stopped)"
    fi
fi

if systemctl is-enabled igel-dashboard >/dev/null 2>&1; then
    DASHBOARD_PORT=$(grep DASHBOARD_PORT /etc/environment 2>/dev/null | cut -d'=' -f2 || echo '8088')
    if systemctl is-active --quiet igel-dashboard; then
        DASHBOARD_STATUS="✅ Dashboard: http://$IP_ADDRESS:$DASHBOARD_PORT"
    else
        DASHBOARD_STATUS="❌ Dashboard: http://$IP_ADDRESS:$DASHBOARD_PORT (service stopped)"
    fi
fi

# Generate the login screen
cat > /etc/issue << EOL
╔═══════════════════════════════════════════════════════════════════════╗
║                    IGEL M250C Tailscale Router                       ║
║                        Physical Console                               ║
╚═══════════════════════════════════════════════════════════════════════╝

🌐 Network Information:
   Local IP:     $IP_ADDRESS
   Tailscale IP: $TAILSCALE_IP
   Hostname:     $(hostname)

🔧 Web Interfaces:
$([ -n "$CASAOS_STATUS" ] && echo "   $CASAOS_STATUS")
$([ -n "$COCKPIT_STATUS" ] && echo "   $COCKPIT_STATUS")
$([ -n "$HEADSCALE_STATUS" ] && echo "   $HEADSCALE_STATUS")
$([ -n "$HEADPLANE_STATUS" ] && echo "   $HEADPLANE_STATUS")
$([ -n "$DASHBOARD_STATUS" ] && echo "   $DASHBOARD_STATUS")
$([ -n "$HEADPLANE_STATUS" ] && echo "   $HEADPLANE_STATUS")

👤 Available Users:
   root         - Full system administration
   app-services - Service management and monitoring

📊 System Status: $(uptime -p)
💾 Disk Usage:   $(df -h / | tail -1 | awk '{print $5}')
🧠 Memory:       $(free -h | grep '^Mem:' | awk '{print $3"/"$2}')

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOL

# Also update /etc/issue.net for network logins
cat > /etc/issue.net << EOL
IGEL M250C Tailscale Router

Network Information:
  Local IP:     $IP_ADDRESS
  Tailscale IP: $TAILSCALE_IP
  Hostname:     $(hostname)

Web Interfaces:
$([ -n "$CASAOS_STATUS" ] && echo "  $CASAOS_STATUS" | sed 's/✅/[Active]/' | sed 's/❌/[Stopped]/')
$([ -n "$COCKPIT_STATUS" ] && echo "  $COCKPIT_STATUS" | sed 's/✅/[Active]/' | sed 's/❌/[Stopped]/')
$([ -n "$HEADSCALE_STATUS" ] && echo "  $HEADSCALE_STATUS" | sed 's/✅/[Active]/' | sed 's/❌/[Stopped]/')
$([ -n "$HEADPLANE_STATUS" ] && echo "  $HEADPLANE_STATUS" | sed 's/✅/[Active]/' | sed 's/❌/[Stopped]/')
$([ -n "$DASHBOARD_STATUS" ] && echo "  $DASHBOARD_STATUS" | sed 's/✅/[Active]/' | sed 's/❌/[Stopped]/')

Users: root, app-services

EOL
EOF

    chmod +x /usr/local/bin/update-login-screen
    
    # Run the script once to set initial login screen
    /usr/local/bin/update-login-screen
    
    # Create systemd service to update login screen on network changes
    cat > /etc/systemd/system/igel-login-screen.service << 'EOF'
[Unit]
Description=IGEL Login Screen Updater
After=network.target tailscaled.service casaos.service cockpit.socket
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-login-screen
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Create timer to update login screen periodically
    cat > /etc/systemd/system/igel-login-screen.timer << 'EOF'
[Unit]
Description=Update IGEL Login Screen every 5 minutes
Requires=igel-login-screen.service

[Timer]
OnBootSec=30sec
OnUnitActiveSec=5min
AccuracySec=10sec

[Install]
WantedBy=timers.target
EOF

    # Create NetworkManager dispatcher script for immediate IP change detection
    cat > /etc/NetworkManager/dispatcher.d/99-update-login-screen << 'EOF'
#!/bin/bash
# Update login screen when network interfaces change

case "$2" in
    up|down|dhcp4-change|dhcp6-change)
        # Wait a moment for network to stabilize
        sleep 2
        /usr/local/bin/update-login-screen
        ;;
esac
EOF

    chmod +x /etc/NetworkManager/dispatcher.d/99-update-login-screen

    # Enable and start the login screen update service
    systemctl daemon-reload
    systemctl enable igel-login-screen.service
    systemctl enable igel-login-screen.timer
    systemctl start igel-login-screen.service
    systemctl start igel-login-screen.timer
    
    # Also add a hook for when Tailscale status changes
    mkdir -p /etc/systemd/system/tailscaled.service.d
    cat > /etc/systemd/system/tailscaled.service.d/update-login-screen.conf << 'EOF'
[Service]
ExecStartPost=/bin/bash -c 'sleep 5 && /usr/local/bin/update-login-screen'
ExecStopPost=/usr/local/bin/update-login-screen
EOF

    log "Dynamic login screen configured for physical console access"
    log "Login screen will update automatically on network changes"
    
    # Create convenience scripts for app-services user
    mkdir -p /home/app-services/.local/bin
    
    # Router status script
    cat > /home/app-services/.local/bin/router-status << 'EOF'
#!/bin/bash
# Router service status check for app-services user

echo "=== IGEL M250C Router Status ==="
echo "Date: $(date)"
echo "Uptime: $(uptime -p)"
echo

echo "=== Core Services ==="
echo -n "Tailscale: "
if sudo systemctl is-active --quiet tailscaled; then
    echo "✅ Active"
    echo "  IP: $(tailscale ip 2>/dev/null || echo 'Not connected')"
else
    echo "❌ Inactive"
fi

if systemctl is-active --quiet casaos &>/dev/null; then
    echo -n "CasaOS: "
    if sudo systemctl is-active --quiet casaos; then
        echo "✅ Active"
    else
        echo "❌ Inactive"
    fi
fi

if systemctl is-active --quiet cockpit.socket &>/dev/null; then
    echo -n "Cockpit: "
    if sudo systemctl is-active --quiet cockpit.socket; then
        echo "✅ Active"
    else
        echo "❌ Inactive"
    fi
fi

echo
echo "=== System Resources ==="
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $3"/"$2" ("$5" available)"}')"
echo "Disk: $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')"

echo
echo "=== Network ==="
echo "Primary IP: $(hostname -I | awk '{print $1}')"
echo "Interfaces:"
ip route show default | while read -r line; do
    interface=$(echo "$line" | awk '{print $5}')
    gateway=$(echo "$line" | awk '{print $3}')
    echo "  • $interface → $gateway"
done
EOF

    chmod +x /home/app-services/.local/bin/router-status
    chown app-services:app-services /home/app-services/.local/bin/router-status
    
    # Router health script  
    cat > /home/app-services/.local/bin/router-health << 'EOF'
#!/bin/bash
# Router health check for app-services user

echo "=== IGEL M250C Router Health Check ==="
echo "Date: $(date)"
echo

# Check if health check script exists and run it
if [[ -x /usr/local/bin/igel-health-check ]]; then
    sudo /usr/local/bin/igel-health-check
else
    echo "=== Basic Health Check ==="
    
    # Check disk space
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 85 ]]; then
        echo "⚠️  Disk usage high: ${disk_usage}%"
    else
        echo "✅ Disk usage OK: ${disk_usage}%"
    fi
    
    # Check memory
    mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $mem_usage -gt 90 ]]; then
        echo "⚠️  Memory usage high: ${mem_usage}%"
    else
        echo "✅ Memory usage OK: ${mem_usage}%"
    fi
    
    # Check Tailscale connectivity
    if tailscale status >/dev/null 2>&1; then
        echo "✅ Tailscale connected"
    else
        echo "❌ Tailscale not connected"
    fi
    
    # Check internet connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "✅ Internet connectivity OK"
    else
        echo "❌ No internet connectivity"
    fi
fi
EOF

    chmod +x /home/app-services/.local/bin/router-health
    chown app-services:app-services /home/app-services/.local/bin/router-health
    
    # Update ownership of the entire .local directory
    chown -R app-services:app-services /home/app-services/.local
    
    # Add manual login screen update command to both users
    cat > /usr/local/bin/update-console << 'EOF'
#!/bin/bash
# Manual login screen update command
echo "Updating console login screen..."
/usr/local/bin/update-login-screen
echo "✅ Console login screen updated with current network information"
EOF
    
    chmod +x /usr/local/bin/update-console
    
    # Add to app-services sudo permissions
    echo "app-services ALL=(ALL) NOPASSWD: /usr/local/bin/update-console, /usr/local/bin/update-login-screen" >> /etc/sudoers.d/app-services
    
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
    if [[ "$INSTALL_CASAOS" == "true" ]]; then
        if systemctl is-active --quiet casaos; then
            echo -e "  ✅ CasaOS: ${GREEN}Active${NC} → http://$ip_address"
        else
            echo -e "  ❌ CasaOS: ${RED}Inactive${NC}"
        fi
    else
        echo "  ℹ️  CasaOS: Skipped (not installed)"
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
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        if systemctl is-active --quiet igel-monitor; then
            echo -e "  ✅ System Monitor: ${GREEN}Active${NC}"
        else
            echo -e "  ❌ System Monitor: ${RED}Inactive${NC}"
        fi
    else
        echo "  ℹ️  System Monitor: Skipped (not enabled)"
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
    echo "Access Information:"
    echo "  • Physical Console: Direct keyboard/monitor access shows IP and web URLs"
    echo "  • SSH as root: ssh root@$(hostname -I | awk '{print $1}')"
    echo "  • SSH as app-services: ssh app-services@$(hostname -I | awk '{print $1}')"
    if [[ "$INSTALL_CASAOS" == "true" ]]; then
        echo "  • CasaOS web interface: http://$(hostname -I | awk '{print $1}')"
    fi
    if [[ "$INSTALL_COCKPIT" == "true" ]]; then
        echo "  • Cockpit management: https://$(hostname -I | awk '{print $1}'):9090"
    fi
    if [[ "$INSTALL_HEADSCALE" == "true" ]]; then
        echo "  • Headscale server: http://$(hostname -I | awk '{print $1}'):${HEADSCALE_LISTEN_PORT:-8080}"
    fi
    if [[ "$INSTALL_HEADPLANE" == "true" ]]; then
        echo "  • Headplane web UI: http://$(hostname -I | awk '{print $1}'):3001"
        echo "  • Headscale API proxy: http://$(hostname -I | awk '{print $1}'):8081"
    fi
    if [[ "$INSTALL_DASHBOARD" == "true" ]]; then
        echo "  • IGEL Dashboard: http://$(hostname -I | awk '{print $1}'):$DASHBOARD_PORT"
        echo "    Default login: admin/admin123 (change immediately!)"
    fi
    echo
    echo "User Guide:"
    echo "  • root user: Full system administration"
    echo "  • app-services user: Service management and monitoring"
    echo "  • Physical console: Shows current IP addresses and web interface URLs"
    echo "  • Use 'update-console' command to manually refresh login screen"
    if [[ "$ENABLE_MAINTENANCE_SCRIPTS" == "true" ]]; then
        echo "  • Run 'router-status' (app-services) or 'igel-health-check' (root) for diagnostics"
        echo "  • Check QUICK_REFERENCE.md for complete command list"
    fi
    echo "  • Use 'tailscale status' to verify VPN connectivity"
    echo
    echo "Configuration saved to: $LOG_FILE"
    echo "For troubleshooting: /opt/igel-setup/README.md"
    
    echo
    log "Next Steps:"
    if tailscale status >/dev/null 2>&1; then
        log "1. Configure your Tailscale admin console to approve subnet routes"
        log "2. Test connectivity from other Tailscale devices"
        if [[ "$INSTALL_CASAOS" == "true" ]]; then
            log "3. Access CasaOS web interface to install additional services"
        fi
        if [[ "$INSTALL_COCKPIT" == "true" ]]; then
            log "4. Use Cockpit for advanced system management"
        fi
    else
        echo -e "${YELLOW}To complete Tailscale setup, run:${NC}"
        echo -e "${BLUE}tailscale up --advertise-routes=192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 --advertise-exit-node --accept-routes${NC}"
        echo
        echo "This will provide a URL to visit for authentication."
        echo
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
            --no-casaos)
                INSTALL_CASAOS="false"
                ;;
            --no-emmc)
                USE_EMMC="false"
                ;;
            --no-security)
                ENABLE_SECURITY_HARDENING="false"
                ;;
            --no-monitoring)
                ENABLE_MONITORING="false"
                ;;
            --no-maintenance)
                ENABLE_MAINTENANCE_SCRIPTS="false"
                ;;
            --no-optimization)
                ENABLE_SYSTEM_OPTIMIZATION="false"
                ;;
            --headscale)
                INSTALL_HEADSCALE="true"
                ;;
            --headscale-domain=*)
                HEADSCALE_DOMAIN="${1#*=}"
                ;;
            --headscale-port=*)
                HEADSCALE_LISTEN_PORT="${1#*=}"
                ;;
            --headplane)
                INSTALL_HEADPLANE="true"
                ;;
            --no-headscale)
                INSTALL_HEADSCALE="false"
                ;;
            --minimal)
                # Minimal installation - only Tailscale and basic system setup
                INSTALL_COCKPIT="false"
                INSTALL_CASAOS="false"
                USE_EMMC="false"
                ENABLE_SECURITY_HARDENING="false"
                ENABLE_MONITORING="false"
                ENABLE_MAINTENANCE_SCRIPTS="false"
                ENABLE_SYSTEM_OPTIMIZATION="false"
                ;;
            --full)
                # Full installation - enable all features
                INSTALL_COCKPIT="true"
                INSTALL_CASAOS="true"
                USE_EMMC="true"
                ENABLE_SECURITY_HARDENING="true"
                ENABLE_MONITORING="true"
                ENABLE_MAINTENANCE_SCRIPTS="true"
                ENABLE_SYSTEM_OPTIMIZATION="true"
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
    
    # Create app-services user first, before any installations
    create_app_user
    
    # Interactive configuration (unless running non-interactively)
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        interactive_config
    fi
    
    show_system_info
    update_system
    configure_ip_forwarding
    install_tailscale
    
    # Install Headscale if requested (before Tailscale configuration)
    if [[ "$INSTALL_HEADSCALE" == "true" ]]; then
        install_headscale
    fi
    
    # Install Headplane if requested (after Headscale)
    if [[ "$INSTALL_HEADPLANE" == "true" ]]; then
        if [[ "$INSTALL_HEADSCALE" == "true" ]]; then
            install_headplane
        else
            log_warning "Headplane requires Headscale. Skipping Headplane installation."
        fi
    fi
    
    configure_tailscale
    
    # Optional features - only install if enabled
    if [[ "$USE_EMMC" == "true" ]]; then
        configure_emmc
    fi
    
    if [[ "$INSTALL_CASAOS" == "true" ]]; then
        install_casaos
    fi
    
    if [[ "$INSTALL_COCKPIT" == "true" ]]; then
        install_cockpit
    fi
    
    # Install Dashboard (after other web services)
    if [[ "$INSTALL_DASHBOARD" == "true" ]]; then
        install_dashboard
    fi
    
    configure_firewall
    
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        create_monitoring_service
    fi
    
    if [[ "$ENABLE_SYSTEM_OPTIMIZATION" == "true" ]]; then
        optimize_system
    fi
    
    if [[ "$ENABLE_MAINTENANCE_SCRIPTS" == "true" ]]; then
        create_maintenance_scripts
    fi
    
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
    systemctl stop docker 2>/dev/null || true
    systemctl stop ssh 2>/dev/null || true
    
    log_error "Installation aborted. Check logs at $LOG_FILE"
    log_error "You may need to manually clean up partial installation"
    
    exit $exit_code
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
