#!/bin/bash

# eMMC Setup Script for IGEL M250C
# Configures the onboard eMMC storage for optimal use as swap or log storage

set -euo pipefail

LOG_FILE="/var/log/emmc-setup.log"
EMMC_DEVICE=""
EMMC_MOUNT_POINT="/mnt/emmc"

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

# Detect eMMC device
detect_emmc() {
    log "Detecting eMMC device..."
    
    for device in /dev/mmcblk*; do
        if [[ -b "$device" ]] && [[ ! "$device" =~ p[0-9]+$ ]]; then
            # Check if it's likely the eMMC (not an SD card)
            if [[ -f "/sys/block/$(basename "$device")/device/type" ]]; then
                device_type=$(cat "/sys/block/$(basename "$device")/device/type" 2>/dev/null || echo "")
                if [[ "$device_type" == "MMC" ]]; then
                    EMMC_DEVICE="$device"
                    log "Found eMMC device: $EMMC_DEVICE"
                    return 0
                fi
            fi
        fi
    done
    
    log_error "No eMMC device found"
    return 1
}

# Get eMMC information
get_emmc_info() {
    if [[ -z "$EMMC_DEVICE" ]]; then
        log_error "No eMMC device specified"
        return 1
    fi
    
    log "Getting eMMC information..."
    
    # Size
    local size_bytes=$(lsblk -b -d -n -o SIZE "$EMMC_DEVICE" 2>/dev/null || echo "0")
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))
    
    # Model
    local model=$(lsblk -d -n -o MODEL "$EMMC_DEVICE" 2>/dev/null || echo "Unknown")
    
    log "eMMC Device: $EMMC_DEVICE"
    log "eMMC Size: ${size_gb}GB (${size_bytes} bytes)"
    log "eMMC Model: $model"
    
    # Check if size is adequate
    if [[ $size_gb -lt 3 ]]; then
        log_warning "eMMC size (${size_gb}GB) may be too small for optimal use"
        return 1
    fi
    
    return 0
}

# Setup eMMC as swap
setup_swap() {
    log "Setting up eMMC as swap space..."
    
    # Unmount if already mounted
    if mount | grep -q "$EMMC_DEVICE"; then
        log "Unmounting existing eMMC partitions..."
        umount "${EMMC_DEVICE}p"* 2>/dev/null || true
        umount "$EMMC_DEVICE"* 2>/dev/null || true
    fi
    
    # Disable existing swap on this device
    swapoff "${EMMC_DEVICE}p"* 2>/dev/null || true
    
    # Create new partition table
    log "Creating GPT partition table..."
    parted -s "$EMMC_DEVICE" mklabel gpt
    
    # Create swap partition (use 80% of space, leave some for wear leveling)
    log "Creating swap partition..."
    parted -s "$EMMC_DEVICE" mkpart primary linux-swap 0% 80%
    
    # Wait for partition to be recognized
    sleep 2
    partprobe "$EMMC_DEVICE"
    sleep 2
    
    # Format as swap
    log "Formatting swap partition..."
    mkswap "${EMMC_DEVICE}p1" -L "igel-emmc-swap"
    
    # Add to fstab if not already present
    if ! grep -q "${EMMC_DEVICE}p1" /etc/fstab; then
        log "Adding swap to /etc/fstab..."
        echo "# IGEL eMMC Swap" >> /etc/fstab
        echo "${EMMC_DEVICE}p1 none swap sw,pri=10 0 0" >> /etc/fstab
    fi
    
    # Enable swap
    log "Enabling swap..."
    swapon "${EMMC_DEVICE}p1"
    
    # Verify swap is active
    if swapon --show | grep -q "${EMMC_DEVICE}p1"; then
        log "Swap successfully activated on ${EMMC_DEVICE}p1"
    else
        log_error "Failed to activate swap"
        return 1
    fi
    
    # Create remaining partition for logs if space available
    local remaining_start="80%"
    local remaining_end="100%"
    
    log "Creating log partition with remaining space..."
    parted -s "$EMMC_DEVICE" mkpart primary ext4 "$remaining_start" "$remaining_end" || {
        log_warning "Could not create log partition - insufficient space"
        return 0
    }
    
    sleep 2
    partprobe "$EMMC_DEVICE"
    sleep 2
    
    # Format log partition
    if [[ -b "${EMMC_DEVICE}p2" ]]; then
        log "Formatting log partition..."
        mkfs.ext4 -F "${EMMC_DEVICE}p2" -L "igel-emmc-logs"
        
        # Create mount point
        mkdir -p "$EMMC_MOUNT_POINT"
        
        # Add to fstab
        if ! grep -q "${EMMC_DEVICE}p2" /etc/fstab; then
            echo "# IGEL eMMC Logs" >> /etc/fstab
            echo "${EMMC_DEVICE}p2 $EMMC_MOUNT_POINT ext4 defaults,noatime 0 2" >> /etc/fstab
        fi
        
        # Mount
        mount "${EMMC_DEVICE}p2"
        
        # Create log directories
        mkdir -p "$EMMC_MOUNT_POINT/igel"
        mkdir -p "$EMMC_MOUNT_POINT/tailscale"
        mkdir -p "$EMMC_MOUNT_POINT/casaos"
        
        # Set permissions
        chmod 755 "$EMMC_MOUNT_POINT"
        chmod 755 "$EMMC_MOUNT_POINT"/*
        
        log "Log partition mounted at $EMMC_MOUNT_POINT"
    fi
    
    return 0
}

# Configure log redirection
configure_log_redirection() {
    if [[ ! -d "$EMMC_MOUNT_POINT" ]]; then
        log_warning "eMMC log partition not available, skipping log redirection"
        return 0
    fi
    
    log "Configuring log redirection to eMMC..."
    
    # Create rsyslog configuration for custom logs
    cat > /etc/rsyslog.d/50-emmc-logs.conf << EOF
# IGEL Custom Logs to eMMC
\$WorkDirectory $EMMC_MOUNT_POINT/rsyslog
\$CreateDirs on

# Tailscale logs
:programname,isequal,"tailscaled" $EMMC_MOUNT_POINT/tailscale/tailscale.log
& stop

# Custom IGEL logs
:syslogtag,contains,"igel" $EMMC_MOUNT_POINT/igel/system.log
& stop
EOF
    
    # Create work directory
    mkdir -p "$EMMC_MOUNT_POINT/rsyslog"
    chmod 700 "$EMMC_MOUNT_POINT/rsyslog"
    
    # Restart rsyslog
    systemctl restart rsyslog
    
    log "Log redirection configured"
}

# Show eMMC status
show_status() {
    log "=== eMMC Status ==="
    
    if [[ -n "$EMMC_DEVICE" ]]; then
        log "Device: $EMMC_DEVICE"
        lsblk "$EMMC_DEVICE" | tee -a "$LOG_FILE"
        
        echo
        log "Swap Status:"
        swapon --show | grep -E "(NAME|${EMMC_DEVICE})" | tee -a "$LOG_FILE"
        
        if [[ -d "$EMMC_MOUNT_POINT" ]]; then
            echo
            log "Mount Status:"
            df -h "$EMMC_MOUNT_POINT" | tee -a "$LOG_FILE"
        fi
    else
        log_warning "No eMMC device configured"
    fi
}

# Main function
main() {
    case "${1:-setup}" in
        "setup")
            log "Starting eMMC setup..."
            detect_emmc || exit 1
            get_emmc_info || exit 1
            setup_swap || exit 1
            configure_log_redirection
            show_status
            log "eMMC setup completed successfully"
            ;;
        "status")
            detect_emmc || exit 1
            show_status
            ;;
        "cleanup")
            log "Cleaning up eMMC configuration..."
            if detect_emmc; then
                swapoff "${EMMC_DEVICE}p"* 2>/dev/null || true
                umount "${EMMC_DEVICE}p"* 2>/dev/null || true
                # Remove from fstab
                sed -i "\|${EMMC_DEVICE}|d" /etc/fstab
                log "eMMC cleanup completed"
            fi
            ;;
        *)
            echo "Usage: $0 {setup|status|cleanup}"
            echo "  setup   - Configure eMMC for swap and log storage"
            echo "  status  - Show current eMMC configuration"
            echo "  cleanup - Remove eMMC configuration"
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
