#!/bin/bash

# Automatic Backup Scheduler for IGEL M250C
# Sets up automated configuration backups

set -euo pipefail

LOG_FILE="/var/log/igel-backup-scheduler.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Setup automatic backup scheduling
setup_backup_schedule() {
    log "Setting up automatic backup schedule..."
    
    # Create backup cron job - daily at 2 AM
    cat > /etc/cron.d/igel-auto-backup << 'EOF'
# IGEL M250C Automatic Configuration Backup
# Runs daily at 2:00 AM
0 2 * * * root /opt/igel-setup/scripts/backup-config.sh backup >/dev/null 2>&1

# Weekly cleanup - keep only last 30 days of backups
0 3 * * 0 root find /opt/igel-backups -name "*.tar.gz" -mtime +30 -delete >/dev/null 2>&1
EOF

    # Ensure backup directory exists with proper permissions
    mkdir -p /opt/igel-backups
    chmod 750 /opt/igel-backups
    
    # Create backup retention script
    cat > /usr/local/bin/igel-backup-cleanup << 'EOF'
#!/bin/bash

# IGEL Backup Cleanup Script
# Manages backup retention and cleanup

BACKUP_DIR="/opt/igel-backups"
RETENTION_DAYS="${1:-30}"

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "Cleaning up backups older than $RETENTION_DAYS days..."

# Find and remove old backups
find "$BACKUP_DIR" -name "igel-config-*.tar.gz" -mtime +$RETENTION_DAYS -print -delete

# Show remaining backups
echo "Remaining backups:"
ls -la "$BACKUP_DIR"
EOF

    chmod +x /usr/local/bin/igel-backup-cleanup
    
    log "✅ Automatic backup schedule configured"
    log "Backups will run daily at 2:00 AM"
    log "Backups older than 30 days will be automatically removed"
}

# Setup log rotation for IGEL-specific logs
setup_log_rotation() {
    log "Setting up enhanced log rotation..."
    
    cat > /etc/logrotate.d/igel-logs << 'EOF'
/var/log/igel-*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        # Restart services if needed
        systemctl reload rsyslog >/dev/null 2>&1 || true
    endscript
}

/var/log/tailscale/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

    log "✅ Enhanced log rotation configured"
}

# Setup system health monitoring
setup_health_monitoring() {
    log "Setting up automated health monitoring..."
    
    # Create health check cron job - every 6 hours
    cat > /etc/cron.d/igel-health-check << 'EOF'
# IGEL M250C Health Check
# Runs every 6 hours and logs results
0 */6 * * * root /usr/local/bin/igel-health-check >/dev/null 2>&1

# Weekly health report - runs Sunday at 6 AM
0 6 * * 0 root /usr/local/bin/igel-health-check > /var/log/weekly-health-report.log 2>&1
EOF

    log "✅ Automated health monitoring configured"
}

# Setup update notifications
setup_update_notifications() {
    log "Setting up update notifications..."
    
    # Create update check script
    cat > /usr/local/bin/igel-update-check << 'EOF'
#!/bin/bash

# IGEL Update Check Script
# Checks for available updates and logs them

LOG_FILE="/var/log/igel-updates.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check for system updates
check_system_updates() {
    apt update >/dev/null 2>&1
    
    local security_updates
    local total_updates
    
    security_updates=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
    total_updates=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
    
    if [[ $security_updates -gt 0 ]]; then
        log "SECURITY: $security_updates security updates available"
        apt list --upgradable 2>/dev/null | grep -i security | head -10 | tee -a "$LOG_FILE"
    fi
    
    if [[ $total_updates -gt 1 ]]; then  # -gt 1 because header line counts as 1
        log "INFO: $((total_updates - 1)) total updates available"
    else
        log "INFO: System is up to date"
    fi
}

# Check Tailscale version
check_tailscale_updates() {
    if command -v tailscale >/dev/null 2>&1; then
        local current_version
        current_version=$(tailscale version | head -1 | awk '{print $1}')
        log "INFO: Current Tailscale version: $current_version"
    fi
}

main() {
    log "=== Update Check Started ==="
    check_system_updates
    check_tailscale_updates
    log "=== Update Check Completed ==="
}

main "$@"
EOF

    chmod +x /usr/local/bin/igel-update-check
    
    # Add to cron - check for updates daily at 6 AM
    cat > /etc/cron.d/igel-update-check << 'EOF'
# IGEL Update Check
# Runs daily at 6:00 AM
0 6 * * * root /usr/local/bin/igel-update-check >/dev/null 2>&1
EOF

    log "✅ Update notifications configured"
}

# Main function
main() {
    case "${1:-all}" in
        "all")
            log "Setting up all automated maintenance tasks..."
            setup_backup_schedule
            setup_log_rotation
            setup_health_monitoring
            setup_update_notifications
            log "✅ All automated maintenance tasks configured"
            ;;
        "backup")
            setup_backup_schedule
            ;;
        "logs")
            setup_log_rotation
            ;;
        "health")
            setup_health_monitoring
            ;;
        "updates")
            setup_update_notifications
            ;;
        *)
            echo "Usage: $0 {all|backup|logs|health|updates}"
            echo "  all     - Setup all automated maintenance"
            echo "  backup  - Setup automatic backup scheduling"
            echo "  logs    - Setup enhanced log rotation"  
            echo "  health  - Setup automated health monitoring"
            echo "  updates - Setup update notifications"
            exit 1
            ;;
    esac
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

main "$@"
