#!/bin/bash

# Security Hardening Script for IGEL M250C
# Implements additional security measures beyond basic installation

set -euo pipefail

LOG_FILE="/var/log/igel-security-hardening.log"

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

# Configure fail2ban for SSH protection
configure_fail2ban() {
    log "=== Configuring Fail2Ban ==="
    
    if ! command -v fail2ban-server >/dev/null 2>&1; then
        apt update
        apt install -y fail2ban
    fi
    
    # Create custom jail configuration
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban for 1 hour
bantime = 3600
# Look back 10 minutes for failed attempts
findtime = 600
# Allow 3 attempts before ban
maxretry = 3
# Send ban notifications (optional)
destemail = root@localhost
action = %(action_mw)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[tailscale-auth]
enabled = true
filter = tailscale-auth
logpath = /var/log/syslog
maxretry = 5
bantime = 1800
EOF

    # Create custom filter for Tailscale authentication failures
    cat > /etc/fail2ban/filter.d/tailscale-auth.conf << 'EOF'
[Definition]
failregex = ^.*tailscaled.*authentication failed.*from <HOST>.*$
ignoreregex =
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log "✅ Fail2Ban configured and started"
}

# Configure automatic security updates
configure_auto_updates() {
    log "=== Configuring Automatic Security Updates ==="
    
    if ! dpkg -l | grep -q unattended-upgrades; then
        apt install -y unattended-upgrades apt-listchanges
    fi
    
    # Configure unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
EOF

    # Enable automatic updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    systemctl enable unattended-upgrades
    
    log "✅ Automatic security updates configured"
}

# Harden SSH configuration
harden_ssh() {
    log "=== Hardening SSH Configuration ==="
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)
    
    # Apply SSH hardening
    cat > /etc/ssh/sshd_config.d/igel-hardening.conf << 'EOF'
# IGEL M250C SSH Hardening
Protocol 2
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 60
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts no
PermitTunnel no
PrintMotd yes
ClientAliveInterval 300
ClientAliveCountMax 0
EOF

    # Test SSH configuration
    if sshd -t; then
        systemctl restart sshd
        log "✅ SSH configuration hardened and restarted"
    else
        log_error "SSH configuration test failed, reverting changes"
        rm /etc/ssh/sshd_config.d/igel-hardening.conf
        return 1
    fi
}

# Configure system limits and kernel hardening
harden_kernel() {
    log "=== Applying Kernel Hardening ==="
    
    # Network security settings
    cat > /etc/sysctl.d/99-igel-security.conf << 'EOF'
# Network security
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# IPv6 security (if IPv6 is enabled)
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Memory protection
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# File system protection
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
EOF

    # Apply settings
    sysctl -p /etc/sysctl.d/99-igel-security.conf
    
    log "✅ Kernel hardening applied"
}

# Configure log monitoring and rotation
configure_logging() {
    log "=== Configuring Enhanced Logging ==="
    
    # Install logwatch for log analysis
    apt install -y logwatch
    
    # Configure logwatch
    cat > /etc/logwatch/conf/logwatch.conf << 'EOF'
LogDir = /var/log
TmpDir = /var/cache/logwatch
MailTo = root
MailFrom = Logwatch
Print = Yes
Detail = Med
Service = All
Range = yesterday
Format = text
EOF

    # Configure rsyslog for better security logging
    cat > /etc/rsyslog.d/50-igel-security.conf << 'EOF'
# Security-related logging
auth,authpriv.*                 /var/log/auth.log
*.*;auth,authpriv.none          -/var/log/syslog
daemon.info                     /var/log/daemon.log
kern.*                         -/var/log/kern.log
mail.*                         -/var/log/mail.log
user.*                         -/var/log/user.log

# Log all failed login attempts
auth.info                      /var/log/failed-logins.log
EOF

    # Enhanced log rotation
    cat > /etc/logrotate.d/igel-security << 'EOF'
/var/log/auth.log
/var/log/failed-logins.log
/var/log/igel-*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    postrotate
        systemctl reload rsyslog
    endscript
}
EOF

    systemctl restart rsyslog
    
    log "✅ Enhanced logging configured"
}

# Disable unnecessary services and protocols
disable_unused_services() {
    log "=== Disabling Unnecessary Services ==="
    
    # List of services that are typically unnecessary on a router
    local services_to_disable=(
        "bluetooth"
        "cups"
        "cups-browsed"
        "avahi-daemon"
        "whoopsie"
        "apport"
        "snapd"
    )
    
    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            systemctl disable "$service" 2>/dev/null || true
            systemctl stop "$service" 2>/dev/null || true
            log "Disabled service: $service"
        fi
    done
    
    # Blacklist unused network protocols
    cat > /etc/modprobe.d/blacklist-rare-network.conf << 'EOF'
# Disable rarely used network protocols
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install net-pf-31 /bin/true
install bluetooth /bin/true
EOF

    log "✅ Unnecessary services disabled"
}

# Create security monitoring script
create_security_monitor() {
    log "=== Creating Security Monitoring Script ==="
    
    cat > /usr/local/bin/igel-security-check << 'EOF'
#!/bin/bash

# IGEL Security Check Script
# Performs security-related system checks

LOG_FILE="/var/log/igel-security-check.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_alert() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ALERT: $1" | tee -a "$LOG_FILE"
    # Could send to syslog or notification service
    logger -p user.warning "IGEL-SECURITY-ALERT: $1"
}

# Check for failed SSH attempts
check_ssh_attacks() {
    local failed_attempts
    failed_attempts=$(grep "Failed password" /var/log/auth.log | grep "$(date '+%b %d')" | wc -l)
    
    if [[ $failed_attempts -gt 10 ]]; then
        log_alert "High number of failed SSH attempts today: $failed_attempts"
    fi
    
    # Check for successful logins from new IPs
    local today_logins
    today_logins=$(grep "Accepted password" /var/log/auth.log | grep "$(date '+%b %d')" | awk '{print $11}' | sort -u)
    
    if [[ -n "$today_logins" ]]; then
        log "SSH logins today from: $today_logins"
    fi
}

# Check system resource usage
check_resources() {
    local cpu_usage mem_usage disk_usage
    
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    mem_usage=$(free | grep Mem | awk '{printf "%.0f\n", $3/$2 * 100.0}')
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [[ ${cpu_usage%.*} -gt 90 ]]; then
        log_alert "High CPU usage: ${cpu_usage}%"
    fi
    
    if [[ $mem_usage -gt 90 ]]; then
        log_alert "High memory usage: ${mem_usage}%"
    fi
    
    if [[ $disk_usage -gt 90 ]]; then
        log_alert "High disk usage: ${disk_usage}%"
    fi
}

# Check critical services
check_services() {
    local critical_services=("sshd" "tailscaled" "casaos" "NetworkManager" "ufw")
    
    for service in "${critical_services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log_alert "Critical service not running: $service"
        fi
    done
}

# Check network connectivity
check_network() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_alert "No internet connectivity"
    fi
    
    if ! tailscale status >/dev/null 2>&1; then
        log_alert "Tailscale not connected"
    fi
}

# Main security check
main() {
    log "=== Starting Security Check ==="
    check_ssh_attacks
    check_resources
    check_services
    check_network
    log "=== Security Check Complete ==="
}

main "$@"
EOF

    chmod +x /usr/local/bin/igel-security-check
    
    # Add to cron for regular checks
    cat > /etc/cron.d/igel-security-check << 'EOF'
# Run security check every hour
0 * * * * root /usr/local/bin/igel-security-check >/dev/null 2>&1
EOF

    log "✅ Security monitoring script created"
}

# Main hardening function
main() {
    case "${1:-all}" in
        "all")
            log "Starting comprehensive security hardening..."
            configure_fail2ban
            configure_auto_updates
            harden_ssh
            harden_kernel
            configure_logging
            disable_unused_services
            create_security_monitor
            log "✅ Security hardening completed"
            ;;
        "fail2ban")
            configure_fail2ban
            ;;
        "updates")
            configure_auto_updates
            ;;
        "ssh")
            harden_ssh
            ;;
        "kernel")
            harden_kernel
            ;;
        "logging")
            configure_logging
            ;;
        "services")
            disable_unused_services
            ;;
        "monitor")
            create_security_monitor
            ;;
        *)
            echo "Usage: $0 {all|fail2ban|updates|ssh|kernel|logging|services|monitor}"
            echo "  all       - Apply all security hardening measures"
            echo "  fail2ban  - Configure fail2ban for SSH protection"
            echo "  updates   - Configure automatic security updates"
            echo "  ssh       - Harden SSH configuration"
            echo "  kernel    - Apply kernel security settings"
            echo "  logging   - Configure enhanced logging"
            echo "  services  - Disable unnecessary services"
            echo "  monitor   - Create security monitoring"
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
