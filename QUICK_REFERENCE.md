# IGEL M250C Quick Reference Card

## Essential Commands

### Installation & Deployment
```bash
# Interactive installation (recommended) - guides you through configuration
sudo ./install.sh

# Non-interactive with options
sudo ./install.sh --non-interactive \
    --tailscale-key=tskey-auth-xxxxx \
    --hostname=my-router \
    --routes=192.168.1.0/24,10.0.0.0/8 \
    --no-cockpit

# Using environment variables
sudo TAILSCALE_AUTH_KEY='tskey-...' \
     DEVICE_HOSTNAME='office-router' \
     INSTALL_COCKPIT=false \
     ./install.sh

# Deploy from VS Code
Ctrl+Shift+P → "Tasks: Run Task" → "Deploy and Install"

# Manual deployment
scp -r . root@<igel-ip>:/opt/igel-setup/
ssh root@<igel-ip> "cd /opt/igel-setup && ./install.sh"
```

### System Management
```bash
# Service status
systemctl status tailscaled casaos cockpit.socket igel-monitor

# System health check
igel-health-check

# System maintenance
igel-maintenance health
igel-maintenance update

# Network management
igel-network-setup detect
igel-network-setup test

# Wireless management
igel-wireless scan                    # Scan for Wi-Fi networks
igel-wireless connect "MyWiFi"        # Connect to Wi-Fi network
igel-wireless status                  # Show wireless status
igel-wireless list                    # Show saved connections
```

# Network configuration
/usr/local/bin/igel-network-setup setup

# Configuration backup
/opt/igel-setup/scripts/backup-config.sh backup
```

### Troubleshooting
```bash
# Check logs
tail -f /var/log/igel-setup.log
tail -f /var/log/igel-monitor.log
journalctl -u tailscaled -f

# Network diagnostics
ip route show
tailscale status
nmcli connection show

# Resource monitoring
htop
df -h
free -h
```

## Key Configuration Files

| File | Purpose |
|------|---------|
| `/etc/sysctl.conf` | IP forwarding and network optimization |
| `/etc/NetworkManager/NetworkManager.conf` | Network interface management |
| `/etc/systemd/network/*.network` | Interface priority configuration |
| `/var/lib/tailscale/tailscaled.state` | Tailscale authentication state |
| `/etc/cron.d/igel-maintenance` | Automated maintenance schedule |

## Default Network Priorities

| Interface Type | Metric | Priority |
|----------------|--------|----------|
| Ethernet | 100 | Highest |
| Wi-Fi | 200 | Medium |
| Cellular/USB | 300 | Lowest |

## Web Interfaces

| Service | URL | Purpose |
|---------|-----|---------|
| CasaOS | `http://<ip>` | Service management |
| Cockpit | `https://<ip>:9090` | System administration |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAILSCALE_AUTH_KEY` | - | Automatic Tailscale authentication |
| `INSTALL_COCKPIT` | `true` | Install Cockpit web UI |
| `USE_EMMC` | `true` | Use eMMC for swap/logs |

## File Locations

### Scripts
- Main installer: `/opt/igel-setup/install.sh`
- Maintenance: `/usr/local/bin/igel-maintenance`
- Network setup: `/usr/local/bin/igel-network-setup`
- eMMC setup: `/opt/igel-setup/scripts/emmc-setup.sh`

### Logs
- Installation: `/var/log/igel-setup.log`
- Monitoring: `/var/log/igel-monitor.log`
- Maintenance: `/var/log/igel-maintenance.log`

### Backups
- Location: `/opt/igel-backups/`
- Format: `igel-config-YYYYMMDD_HHMMSS.tar.gz`

## Performance Specifications

| Metric | Value |
|--------|-------|
| Max Throughput | 100-200 Mbps |
| Memory Usage | 1.5-2.5 GB |
| CPU Usage | 20-40% average |
| Boot Time | 30-60 seconds |
| Power Consumption | ~15W |

## Common Issues & Solutions

### Tailscale Not Connecting
```bash
systemctl restart tailscaled
tailscale logout
tailscale up --advertise-routes=... --advertise-exit-node
```

### High Memory Usage
```bash
/usr/local/bin/igel-maintenance optimize
systemctl restart casaos
```

### USB Dongle Not Detected
```bash
/opt/igel-setup/scripts/usb-dongle-setup.sh detect
systemctl restart NetworkManager
lsusb
```

### eMMC Issues
```bash
/opt/igel-setup/scripts/emmc-setup.sh status
swapon --show
```

## Hardware Requirements

### Minimum
- IGEL M250C with 2GB RAM
- 32GB USB 3.0 drive
- Ethernet connection

### Recommended
- IGEL M250C with 4GB RAM
- 64GB USB 3.0 drive
- Gigabit Ethernet
- Compatible USB Wi-Fi dongle

### Supported USB Dongles

#### Wi-Fi
- Realtek RTL8188EUS (0bda:8179)
- Realtek RTL8192EU (0bda:818b)  
- Ralink RT5370 (148f:5370)
- Atheros AR9271 (0cf3:9271)

#### Cellular
- Huawei E3372, E8372
- ZTE MF79U, MF823, MF833
- Sierra Wireless EM7455, MC7455

## Security Checklist

- [ ] Change default SSH port
- [ ] Enable fail2ban
- [ ] Configure automatic security updates
- [ ] Review Tailscale ACLs
- [ ] Monitor authentication logs
- [ ] Regular configuration backups

## VS Code Tasks

| Task | Purpose |
|------|---------|
| Deploy to IGEL Device | Copy files to target device |
| Run Remote Installation | Execute installation remotely |
| Deploy and Install | Combined deployment and installation |
| Check IGEL Status | Verify service status |
| View IGEL Logs | Monitor installation logs |
| Backup IGEL Configuration | Create configuration backup |
| IGEL System Health Check | Run health diagnostics |
| Update IGEL System | Perform system updates |
| IGEL Network Setup | Configure network interfaces |

## Development Workflow

1. **Setup**: Clone repo, review documentation
2. **Development**: Make changes, test locally
3. **Testing**: Deploy to test device, validate
4. **Integration**: Merge changes, update docs
5. **Deployment**: Deploy to production device
6. **Monitoring**: Verify functionality, check logs

## Emergency Procedures

### Service Recovery
```bash
# Restart all critical services
systemctl restart tailscaled casaos igel-monitor

# Check for service failures
systemctl --failed

# Reset to last known good state
/opt/igel-setup/scripts/backup-config.sh restore <backup-file>
```

### Network Recovery
```bash
# Reset network configuration
/usr/local/bin/igel-network-setup setup

# Restart networking
systemctl restart NetworkManager
systemctl restart systemd-networkd
```

### System Recovery
```bash
# Boot from backup USB
# Re-run installation with known good configuration
# Restore from configuration backup
```

This quick reference provides immediate access to the most commonly needed information for maintaining and troubleshooting the IGEL M250C Tailscale router system.
