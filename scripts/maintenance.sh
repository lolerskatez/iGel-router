#!/bin/bash

# IGEL M250C Update and Maintenance Script
# Handles system updates, service maintenance, and health checks

set -euo pipefail

LOG_FILE="/var/log/igel-maintenance.log"
BACKUP_DIR="/opt/igel-backups"

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

# System health check
health_check() {
    log "=== System Health Check ==="
    
    local issues=0
    
    # Check disk usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 85 ]]; then
        log_warning "High disk usage: ${disk_usage}%"
        issues=$((issues + 1))
    else
        log "✓ Disk usage: ${disk_usage}%"
    fi
    
    # Check memory usage
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $mem_usage -gt 90 ]]; then
        log_warning "High memory usage: ${mem_usage}%"
        issues=$((issues + 1))
    else
        log "✓ Memory usage: ${mem_usage}%"
    fi
    
    # Check swap usage (if available)
    if swapon --show | grep -q "/dev"; then
        local swap_usage=$(free | grep Swap | awk '{if($2>0) printf "%.0f", $3/$2 * 100.0; else print "0"}')
        log "✓ Swap usage: ${swap_usage}%"
    fi
    
    # Check system load
    local load_avg=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local load_percent=$(echo "$load_avg * 100 / $cpu_cores" | bc -l | cut -d. -f1)
    if [[ $load_percent -gt 80 ]]; then
        log_warning "High system load: ${load_avg} (${load_percent}% of ${cpu_cores} cores)"
        issues=$((issues + 1))
    else
        log "✓ System load: ${load_avg} (${load_percent}% of ${cpu_cores} cores)"
    fi
    
    # Check critical services
    local services=("tailscaled" "casaos" "igel-monitor")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log "✓ Service $service: Active"
        else
            log_warning "Service $service: Inactive"
            issues=$((issues + 1))
        fi
    done
    
    # Check Tailscale connectivity
    if tailscale status >/dev/null 2>&1; then
        log "✓ Tailscale: Connected"
    else
        log_warning "Tailscale: Not connected"
        issues=$((issues + 1))
    fi
    
    # Check network connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log "✓ Internet connectivity: OK"
    else
        log_warning "Internet connectivity: Failed"
        issues=$((issues + 1))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✅ All health checks passed"
    else
        log_warning "⚠️  $issues issue(s) found"
    fi
    
    return $issues
}

# Update system packages
update_system() {
    log "=== Updating System Packages ==="
    
    # Update package list
    apt update
    
    # Show available updates
    local updates=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
    log "Available updates: $updates packages"
    
    if [[ $updates -gt 0 ]]; then
        # Upgrade packages
        apt upgrade -y
        
        # Check if reboot is required
        if [[ -f /var/run/reboot-required ]]; then
            log_warning "System reboot required after updates"
            if [[ -f /var/run/reboot-required.pkgs ]]; then
                log_info "Packages requiring reboot:"
                cat /var/run/reboot-required.pkgs | tee -a "$LOG_FILE"
            fi
        fi
        
        log "System packages updated successfully"
    else
        log "System is up to date"
    fi
}

# Update Tailscale
update_tailscale() {
    log "=== Updating Tailscale ==="
    
    local current_version=$(tailscale version | head -1 | awk '{print $1}' || echo "unknown")
    log "Current Tailscale version: $current_version"
    
    # Update Tailscale package
    apt update
    if apt list --upgradable 2>/dev/null | grep -q tailscale; then
        apt upgrade -y tailscale
        log "Tailscale updated successfully"
        
        # Restart if needed
        systemctl restart tailscaled
        sleep 5
        
        local new_version=$(tailscale version | head -1 | awk '{print $1}' || echo "unknown")
        log "New Tailscale version: $new_version"
    else
        log "Tailscale is up to date"
    fi
}

# Clean up system
cleanup_system() {
    log "=== Cleaning Up System ==="
    
    # Clean package cache
    apt autoremove -y
    apt autoclean
    
    # Clean old log files
    find /var/log -name "*.log" -type f -mtime +30 -exec rm -f {} \; 2>/dev/null || true
    
    # Clean old journal files
    journalctl --vacuum-time=7d
    
    # Clean old backups (keep last 10)
    if [[ -d "$BACKUP_DIR" ]]; then
        find "$BACKUP_DIR" -name "igel-config-*.tar.gz" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
    fi
    
    # Clean temporary files
    find /tmp -type f -mtime +7 -delete 2>/dev/null || true
    
    log "System cleanup completed"
}

# Optimize system performance
optimize_performance() {
    log "=== Optimizing System Performance ==="
    
    # Update memory settings for low-memory system
    sysctl vm.swappiness=10
    sysctl vm.vfs_cache_pressure=50
    
    # Optimize network buffers
    sysctl net.core.rmem_default=65536
    sysctl net.core.wmem_default=65536
    
    # Clear memory caches if memory usage is high
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $mem_usage -gt 80 ]]; then
        log "High memory usage ($mem_usage%), clearing caches..."
        sync
        echo 1 > /proc/sys/vm/drop_caches
    fi
    
    log "Performance optimization completed"
}

# Monitor and alert
monitor_and_alert() {
    log "=== System Monitoring ==="
    
    # Check for critical issues
    local alerts=()
    
    # High disk usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        alerts+=("CRITICAL: Disk usage at ${disk_usage}%")
    fi
    
    # High memory usage
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $mem_usage -gt 95 ]]; then
        alerts+=("CRITICAL: Memory usage at ${mem_usage}%")
    fi
    
    # Service failures
    local services=("tailscaled" "casaos" "igel-monitor")
    for service in "${services[@]}"; do
        if ! systemctl is-active "$service" >/dev/null 2>&1; then
            alerts+=("CRITICAL: Service $service is down")
        fi
    done
    
    # Tailscale disconnected
    if ! tailscale status >/dev/null 2>&1; then
        alerts+=("WARNING: Tailscale is disconnected")
    fi
    
    # Log alerts
    if [[ ${#alerts[@]} -gt 0 ]]; then
        log_error "System alerts detected:"
        for alert in "${alerts[@]}"; do
            log_error "  $alert"
        done
        
        # Could send notifications here (email, webhook, etc.)
    else
        log "✓ No critical alerts"
    fi
}

# Show system status
show_status() {
    log "=== System Status ==="
    
    # System information
    log "Hostname: $(hostname)"
    log "Uptime: $(uptime -p)"
    log "Load: $(uptime | awk '{print $(NF-2)" "$(NF-1)" "$NF}')"
    
    # Memory and disk
    log "Memory: $(free -h | grep Mem | awk '{print $3"/"$2" ("$3/$2*100"%)"}')"
    log "Disk: $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
    
    # Network
    local ip_address=$(hostname -I | awk '{print $1}')
    log "IP Address: $ip_address"
    
    # Services
    local services=("tailscaled" "casaos" "cockpit.socket" "igel-monitor")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log "✓ $service: Active"
        else
            log "✗ $service: Inactive"
        fi
    done
    
    # Tailscale status
    if tailscale status >/dev/null 2>&1; then
        log "Tailscale: Connected"
        tailscale status --peers=false | head -5 | tee -a "$LOG_FILE"
    else
        log "Tailscale: Disconnected"
    fi
}

# Main function
main() {
    case "${1:-status}" in
        "health")
            health_check
            ;;
        "update")
            health_check
            update_system
            update_tailscale
            cleanup_system
            ;;
        "cleanup")
            cleanup_system
            ;;
        "optimize")
            optimize_performance
            ;;
        "monitor")
            monitor_and_alert
            ;;
        "status")
            show_status
            ;;
        "full")
            log "Starting full maintenance cycle..."
            health_check
            update_system
            update_tailscale
            cleanup_system
            optimize_performance
            monitor_and_alert
            log "Full maintenance cycle completed"
            ;;
        *)
            echo "IGEL M250C Maintenance Script"
            echo
            echo "Usage: $0 {health|update|cleanup|optimize|monitor|status|full}"
            echo
            echo "Commands:"
            echo "  health    - Run system health checks"
            echo "  update    - Update system and Tailscale packages"
            echo "  cleanup   - Clean up system files and caches"
            echo "  optimize  - Optimize system performance"
            echo "  monitor   - Check for alerts and issues"
            echo "  status    - Show current system status"
            echo "  full      - Run complete maintenance cycle"
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
