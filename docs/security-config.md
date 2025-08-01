# Security Configuration for IGEL M250C Router

## Default Security Settings Applied

### Firewall (UFW)
- SSH (port 22): Allowed from any
- HTTP (port 80): Allowed for CasaOS
- HTTPS (port 443): Allowed for CasaOS
- Cockpit (port 9090): Allowed if installed
- Tailscale interface: Fully allowed
- All other ports: Denied by default

### System Hardening
- Regular security updates enabled
- Unnecessary services disabled
- Log rotation configured
- System monitoring active

## Additional Security Recommendations

### 1. Change Default SSH Port
```bash
# Edit SSH configuration
nano /etc/ssh/sshd_config

# Change port (example: use port 2222)
Port 2222

# Restart SSH service
systemctl restart sshd

# Update firewall
ufw allow 2222
ufw delete allow 22
```

### 2. Enable Fail2Ban
```bash
# Install fail2ban
apt install fail2ban

# Configure for SSH protection
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
EOF

# Enable and start fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

### 3. Disable Unused Services
```bash
# Check running services
systemctl list-units --type=service --state=running

# Disable unused services (examples)
systemctl disable bluetooth
systemctl disable cups
systemctl disable avahi-daemon
```

### 4. Configure Automatic Security Updates
```bash
# Install unattended-upgrades
apt install unattended-upgrades

# Configure automatic security updates
dpkg-reconfigure -plow unattended-upgrades

# Edit configuration
nano /etc/apt/apt.conf.d/50unattended-upgrades
```

### 5. Set Up Log Monitoring
```bash
# Install logwatch
apt install logwatch

# Configure daily email reports (optional)
echo "root: your-email@domain.com" >> /etc/aliases
newaliases
```

### 6. Network Security
```bash
# Disable unused network protocols
echo "install dccp /bin/true" >> /etc/modprobe.d/blacklist-rare-network.conf
echo "install sctp /bin/true" >> /etc/modprobe.d/blacklist-rare-network.conf
echo "install rds /bin/true" >> /etc/modprobe.d/blacklist-rare-network.conf
echo "install tipc /bin/true" >> /etc/modprobe.d/blacklist-rare-network.conf

# Enable SYN flood protection
echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 2048" >> /etc/sysctl.conf
echo "net.ipv4.tcp_synack_retries = 3" >> /etc/sysctl.conf

# Apply changes
sysctl -p
```

### 7. File System Security
```bash
# Set restrictive permissions on sensitive files
chmod 600 /etc/ssh/sshd_config
chmod 600 /var/lib/tailscale/tailscaled.state

# Enable file system monitoring (optional)
apt install aide
aide --init
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

## Tailscale-Specific Security

### Access Control Lists (ACLs)
Configure Tailscale ACLs in the admin console to restrict access:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:trusted"],
      "dst": ["igel-m250c-router:*"]
    },
    {
      "action": "accept", 
      "src": ["*"],
      "dst": ["igel-m250c-router:80,443,9090"]
    }
  ],
  "tagOwners": {
    "tag:trusted": ["your-email@domain.com"]
  }
}
```

### Key Expiry
- Set reasonable key expiry times in Tailscale admin console
- Enable automatic key renewal if supported

### Device Authorization
- Require admin approval for new devices
- Regularly review and remove unused devices

## Monitoring and Alerting

### System Monitoring
The installed monitoring service tracks:
- Service status (Tailscale, CasaOS, etc.)
- Resource usage (CPU, memory, disk)
- Network connectivity
- Security events

### Log Analysis
Important logs to monitor:
- `/var/log/auth.log` - Authentication attempts
- `/var/log/syslog` - System events
- `/var/log/igel-setup.log` - Installation events
- `/var/log/igel-monitor.log` - System monitoring

### Security Alerts
Consider setting up alerts for:
- Failed SSH login attempts
- High resource usage
- Service failures
- Network connectivity issues
- Tailscale disconnections

## Backup and Recovery

### Configuration Backup
```bash
# Create configuration backup
/opt/igel-setup/scripts/backup-config.sh backup

# Schedule regular backups
echo "0 1 * * * root /opt/igel-setup/scripts/backup-config.sh backup" >> /etc/crontab
```

### Recovery Plan
1. Keep USB installation media ready
2. Document network configuration
3. Store Tailscale auth keys securely
4. Test recovery procedures regularly

## Compliance Considerations

### Network Isolation
- Use VLANs to separate traffic types
- Implement network segmentation
- Monitor inter-network communications

### Audit Trail
- Enable comprehensive logging
- Implement log forwarding if required
- Maintain configuration change records

### Access Management
- Use strong authentication
- Implement principle of least privilege
- Regular access reviews

This security configuration provides a solid foundation for running the IGEL M250C as a secure Tailscale router.
