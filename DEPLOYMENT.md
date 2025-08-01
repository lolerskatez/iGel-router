# IGEL M250C Deployment Guide

## Quick Start Deployment

This guide walks you through deploying the IGEL M250C as a Tailscale subnet router from development to production.

## Prerequisites

### Hardware Setup
1. **IGEL M250C** with 4GB RAM upgrade (recommended)
2. **64GB+ USB 3.0 drive** for Debian 12 installation
3. **Network connection** (Ethernet or supported USB dongle)
4. **Tailscale account** with auth key ready

### Software Requirements
- **Debian 12** minimal/server installed on USB drive
- **SSH access** to the IGEL device
- **Root privileges** on the target device

## Deployment Methods

### Method 1: Direct Installation (Recommended)

1. **Copy files to IGEL device**:
   ```bash
   # From your development machine
   scp -r . root@<igel-ip>:/opt/igel-setup/
   ```

2. **Run installation**:
   ```bash
   ssh root@<igel-ip>
   cd /opt/igel-setup
   chmod +x *.sh scripts/*.sh configs/tailscale/connect.sh
   
   # Interactive installation (recommended for first-time setup)
   ./install.sh
   # The interactive installer guides you through all configuration options
   
   # Non-interactive installation
   ./install.sh --non-interactive \
       --tailscale-key=tskey-auth-your-key-here \
       --hostname=production-router \
       --routes=192.168.1.0/24,10.0.0.0/8
   ```

3. **Configure Tailscale** (if no auth key provided):
   ```bash
   tailscale up --advertise-routes=192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 --advertise-exit-node --accept-routes
   ```

### Method 2: VS Code Tasks

1. **Open project in VS Code**
2. **Run task**: `Ctrl+Shift+P` → "Tasks: Run Task" → "Deploy and Install"
3. **Enter IGEL IP** when prompted
4. **Monitor progress** in the terminal

### Method 3: Automated with Auth Key

```bash
# Set environment variables
export TAILSCALE_AUTH_KEY="tskey-auth-..."
export IGEL_HOST="192.168.1.100"

# Run automated deployment
ssh root@$IGEL_HOST "mkdir -p /opt/igel-setup"
scp -r . root@$IGEL_HOST:/opt/igel-setup/
ssh root@$IGEL_HOST "cd /opt/igel-setup && chmod +x *.sh scripts/*.sh configs/tailscale/connect.sh && TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY' ./install.sh"
```

## Configuration Options

### Environment Variables
Set these before running `install.sh`:

```bash
# Tailscale authentication key (skip manual auth)
export TAILSCALE_AUTH_KEY="tskey-auth-..."

# Install Cockpit web management interface
export INSTALL_COCKPIT="true"  # default: true

# Use eMMC for swap and log storage  
export USE_EMMC="true"         # default: true
```

### Custom Configuration
Edit configuration files before deployment:

- `configs/tailscale/tailscaled.conf` - Tailscale daemon settings
- `configs/network/*.network` - Network interface priority
- `configs/systemd/*.service` - System service definitions

## Post-Deployment Tasks

### 1. Verify Installation
```bash
# Check service status
ssh root@<igel-ip> "systemctl status tailscaled casaos cockpit.socket igel-monitor"

# Check Tailscale status
ssh root@<igel-ip> "tailscale status"

# View installation logs
ssh root@<igel-ip> "tail -50 /var/log/igel-setup.log"
```

### 2. Configure Tailscale Admin Console
1. Log into [Tailscale Admin Console](https://login.tailscale.com/admin)
2. Navigate to **Machines** tab
3. Find your IGEL device (`igel-m250c-router`)
4. **Enable subnet routes** and **exit node** as needed
5. **Approve** the advertised routes

### 3. Access Web Interfaces
- **CasaOS**: `http://<igel-ip>` (port 80)
- **Cockpit**: `https://<igel-ip>:9090` (if installed)

### 4. Test Connectivity
```bash
# From another Tailscale device
tailscale ping igel-m250c-router

# Test subnet routing
ping 192.168.1.1  # Should route through IGEL device

# Test exit node (if configured)
curl ipinfo.io   # Should show IGEL device's public IP
```

## Maintenance and Monitoring

### Regular Maintenance Tasks

1. **System Updates**:
   ```bash
   ssh root@<igel-ip> "apt update && apt upgrade -y"
   ```

2. **Configuration Backup**:
   ```bash
   ssh root@<igel-ip> "/opt/igel-setup/scripts/backup-config.sh backup"
   ```

3. **Service Health Check**:
   ```bash
   ssh root@<igel-ip> "systemctl is-active tailscaled casaos igel-monitor"
   ```

### Monitoring Dashboard
The installation includes a monitoring service that logs:
- Tailscale connectivity status
- Disk usage alerts (>85%)
- Memory usage alerts (>90%)
- System health metrics

View monitoring logs:
```bash
ssh root@<igel-ip> "tail -f /var/log/igel-monitor.log"
```

## Troubleshooting Common Issues

### Tailscale Connection Problems
```bash
# Check Tailscale service
systemctl status tailscaled

# Restart Tailscale
systemctl restart tailscaled

# Re-authenticate
tailscale logout
tailscale up --advertise-routes=192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 --advertise-exit-node
```

### CasaOS Not Accessible
```bash
# Check CasaOS service
systemctl status casaos

# Restart CasaOS
systemctl restart casaos

# Check port availability
netstat -tlnp | grep :80
```

### USB Dongle Issues
```bash
# Run USB dongle detection
/opt/igel-setup/scripts/usb-dongle-setup.sh detect

# Restart NetworkManager
systemctl restart NetworkManager

# Check USB devices
lsusb
```

### eMMC Configuration Issues
```bash
# Check eMMC status
/opt/igel-setup/scripts/emmc-setup.sh status

# Reconfigure eMMC
/opt/igel-setup/scripts/emmc-setup.sh setup
```

## Performance Optimization

### For High-Throughput Scenarios
1. **Disable unnecessary services**:
   ```bash
   systemctl disable bluetooth
   systemctl disable cups
   ```

2. **Optimize network buffers**:
   ```bash
   echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
   echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
   sysctl -p
   ```

3. **Use wired connection** for best performance

### For Low-Power Scenarios
1. **Reduce monitoring frequency**:
   Edit `/usr/local/bin/igel-monitor.sh` and increase sleep interval

2. **Disable Cockpit** if not needed:
   ```bash
   export INSTALL_COCKPIT=false
   ```

## Security Considerations

### Firewall Configuration
The installation automatically configures UFW with:
- SSH (port 22) - allowed
- HTTP (port 80) - allowed for CasaOS
- HTTPS (port 443) - allowed for CasaOS
- Cockpit (port 9090) - allowed if installed
- Tailscale interface - fully allowed

### Additional Security Measures
1. **Change default SSH port**:
   ```bash
   sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
   systemctl restart sshd
   ufw allow 2222
   ufw delete allow ssh
   ```

2. **Enable automatic security updates**:
   ```bash
   apt install unattended-upgrades
   dpkg-reconfigure -plow unattended-upgrades
   ```

3. **Configure fail2ban**:
   ```bash
   apt install fail2ban
   systemctl enable fail2ban
   ```

## Scaling and Load Balancing

### Multiple IGEL Devices
For redundancy, deploy multiple IGEL devices:

1. **Use different hostnames**:
   ```bash
   export HOSTNAME="igel-router-01"  # Second device: igel-router-02
   ```

2. **Configure different route priorities** in Tailscale admin console

3. **Implement health checks** between devices

### Load Distribution
- **Split subnets** across multiple devices
- **Use DNS round-robin** for exit node traffic
- **Configure failover** in Tailscale admin console

## Integration with Existing Infrastructure

### Network Infrastructure
- **VLAN support**: Configure via NetworkManager
- **DHCP reservations**: Set static IP in router
- **DNS integration**: Configure custom DNS in Tailscale

### Monitoring Integration
- **SNMP**: Install snmpd for network monitoring
- **Prometheus**: Export metrics via node_exporter
- **Grafana**: Create dashboards for visualization

This deployment guide provides comprehensive instructions for getting your IGEL M250C Tailscale router up and running in any environment.
