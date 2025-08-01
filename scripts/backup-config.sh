#!/bin/bash

# Configuration Backup Script for IGEL M250C
# Creates backups of system configuration files

set -euo pipefail

BACKUP_DIR="/opt/igel-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="igel-config-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Create backup directory
create_backup_dir() {
    mkdir -p "$BACKUP_PATH"
    log "Created backup directory: $BACKUP_PATH"
}

# Backup system configuration files
backup_system_config() {
    log "Backing up system configuration..."
    
    local system_files=(
        "/etc/fstab"
        "/etc/hostname"
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/sysctl.conf"
        "/etc/systemd/journald.conf"
        "/etc/logrotate.conf"
        "/etc/udev/rules.d/"
        "/etc/systemd/system/"
    )
    
    mkdir -p "${BACKUP_PATH}/system"
    
    for file in "${system_files[@]}"; do
        if [[ -e "$file" ]]; then
            cp -r "$file" "${BACKUP_PATH}/system/" 2>/dev/null || log_warning "Failed to backup $file"
        fi
    done
}

# Backup network configuration
backup_network_config() {
    log "Backing up network configuration..."
    
    local network_files=(
        "/etc/NetworkManager/"
        "/etc/ModemManager/"
        "/etc/systemd/network/"
        "/etc/netplan/"
        "/etc/dhcp/"
        "/etc/bind/"
    )
    
    mkdir -p "${BACKUP_PATH}/network"
    
    for file in "${network_files[@]}"; do
        if [[ -e "$file" ]]; then
            cp -r "$file" "${BACKUP_PATH}/network/" 2>/dev/null || true
        fi
    done
    
    # Backup current network state
    ip addr show > "${BACKUP_PATH}/network/ip-addr.txt" 2>/dev/null || true
    ip route show > "${BACKUP_PATH}/network/ip-route.txt" 2>/dev/null || true
    nmcli connection show > "${BACKUP_PATH}/network/nm-connections.txt" 2>/dev/null || true
}

# Backup Tailscale configuration
backup_tailscale_config() {
    log "Backing up Tailscale configuration..."
    
    mkdir -p "${BACKUP_PATH}/tailscale"
    
    # Tailscale state and config
    if [[ -d "/var/lib/tailscale" ]]; then
        cp -r /var/lib/tailscale "${BACKUP_PATH}/tailscale/" 2>/dev/null || true
    fi
    
    # Tailscale status
    tailscale status > "${BACKUP_PATH}/tailscale/status.txt" 2>/dev/null || true
    tailscale version > "${BACKUP_PATH}/tailscale/version.txt" 2>/dev/null || true
}

# Backup CasaOS configuration
backup_casaos_config() {
    log "Backing up CasaOS configuration..."
    
    mkdir -p "${BACKUP_PATH}/casaos"
    
    local casaos_dirs=(
        "/var/lib/casaos"
        "/etc/casaos"
        "$HOME/.config/casaos"
    )
    
    for dir in "${casaos_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            cp -r "$dir" "${BACKUP_PATH}/casaos/" 2>/dev/null || true
        fi
    done
}

# Backup Cockpit configuration
backup_cockpit_config() {
    log "Backing up Cockpit configuration..."
    
    mkdir -p "${BACKUP_PATH}/cockpit"
    
    local cockpit_dirs=(
        "/etc/cockpit"
        "/usr/share/cockpit"
    )
    
    for dir in "${cockpit_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            cp -r "$dir" "${BACKUP_PATH}/cockpit/" 2>/dev/null || true
        fi
    done
}

# Backup custom scripts and logs
backup_custom_files() {
    log "Backing up custom files and logs..."
    
    mkdir -p "${BACKUP_PATH}/custom"
    
    # Custom scripts
    if [[ -d "/usr/local/bin" ]]; then
        find /usr/local/bin -name "igel-*" -exec cp {} "${BACKUP_PATH}/custom/" \; 2>/dev/null || true
    fi
    
    # Custom systemd services
    find /etc/systemd/system -name "igel-*" -exec cp {} "${BACKUP_PATH}/custom/" \; 2>/dev/null || true
    
    # Log files
    mkdir -p "${BACKUP_PATH}/logs"
    find /var/log -name "*igel*" -exec cp {} "${BACKUP_PATH}/logs/" \; 2>/dev/null || true
    
    # Package list
    dpkg --get-selections > "${BACKUP_PATH}/custom/package-list.txt" 2>/dev/null || true
    apt list --installed > "${BACKUP_PATH}/custom/apt-list.txt" 2>/dev/null || true
}

# Create system information file
create_system_info() {
    log "Creating system information file..."
    
    local info_file="${BACKUP_PATH}/system-info.txt"
    
    cat > "$info_file" << EOF
IGEL M250C System Backup Information
====================================
Backup Date: $(date)
Hostname: $(hostname)
OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")
Kernel: $(uname -r)
Architecture: $(uname -m)
Uptime: $(uptime)

Memory Information:
$(free -h)

Disk Usage:
$(df -h)

Block Devices:
$(lsblk)

Network Interfaces:
$(ip addr show)

Active Services:
$(systemctl list-units --state=active --type=service | grep -E "(tailscale|casa|cockpit|igel)")

USB Devices:
$(lsusb)

PCI Devices:
$(lspci)
EOF

    log "System information saved to: $info_file"
}

# Compress backup
compress_backup() {
    log "Compressing backup..."
    
    cd "$BACKUP_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
    
    if [[ -f "${BACKUP_NAME}.tar.gz" ]]; then
        rm -rf "$BACKUP_NAME"
        log "Backup compressed to: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    else
        log_error "Failed to compress backup"
        return 1
    fi
}

# List available backups
list_backups() {
    log "Available backups in $BACKUP_DIR:"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -la "$BACKUP_DIR" | grep "igel-config"
    else
        log_warning "No backup directory found"
    fi
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_warning "WARNING: This will restore system configuration from backup"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled"
        return 0
    fi
    
    log "Restoring from backup: $backup_file"
    
    # Extract backup
    local restore_dir="/tmp/igel-restore-$$"
    mkdir -p "$restore_dir"
    tar -xzf "$backup_file" -C "$restore_dir"
    
    # Find the backup directory
    local backup_content=$(find "$restore_dir" -name "igel-config-*" -type d | head -1)
    
    if [[ -z "$backup_content" ]]; then
        log_error "Invalid backup file format"
        rm -rf "$restore_dir"
        return 1
    fi
    
    # Restore system files (be careful!)
    log "Restoring system configuration..."
    cp -r "${backup_content}/system/"* /etc/ 2>/dev/null || true
    
    # Restore network configuration
    log "Restoring network configuration..."
    cp -r "${backup_content}/network/NetworkManager/"* /etc/NetworkManager/ 2>/dev/null || true
    
    # Restore custom scripts
    log "Restoring custom scripts..."
    cp "${backup_content}/custom/igel-"* /usr/local/bin/ 2>/dev/null || true
    chmod +x /usr/local/bin/igel-* 2>/dev/null || true
    
    # Cleanup
    rm -rf "$restore_dir"
    
    log "Restore completed. You may need to reboot for all changes to take effect."
}

# Main function
main() {
    case "${1:-backup}" in
        "backup")
            log "Starting configuration backup..."
            create_backup_dir
            backup_system_config
            backup_network_config
            backup_tailscale_config
            backup_casaos_config
            backup_cockpit_config
            backup_custom_files
            create_system_info
            compress_backup
            log "Backup completed: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
            ;;
        "list")
            list_backups
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                log_error "Please specify backup file to restore"
                echo "Usage: $0 restore /path/to/backup.tar.gz"
                exit 1
            fi
            restore_backup "$2"
            ;;
        *)
            echo "Usage: $0 {backup|list|restore}"
            echo "  backup              - Create a new configuration backup"
            echo "  list                - List available backups"
            echo "  restore <file>      - Restore from specified backup file"
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
