# IGEL M250C Router - System Enhancements for Debian Minimal

## Overview
The installation script has been enhanced to provide a complete system setup starting from Debian minimal, including essential utilities and a dedicated service management user.

## ✅ **New System Enhancements**

### **1. Essential System Packages**
Added comprehensive package installation for minimal Debian systems:

#### **Core System Utilities**
- `sudo` - Administrative privileges management
- `nano`, `vim-tiny` - Text editors for configuration
- `curl`, `wget` - Network download utilities  
- `htop`, `tree`, `less` - System monitoring and navigation
- `git`, `unzip`, `zip`, `rsync` - Development and file management
- `openssh-server`, `openssh-client` - Secure remote access
- `cron`, `logrotate` - Task scheduling and log management

#### **Network & Security**
- `iptables`, `iptables-persistent` - Firewall rules persistence
- `fail2ban` - Intrusion prevention system
- `network-manager` - Network connection management
- `ufw` - Simplified firewall management

#### **Development & Monitoring**
- `python3`, `python3-pip`, `python3-venv` - Python runtime and package management
- `build-essential`, `pkg-config` - Compilation tools
- `jq`, `bc` - JSON processing and calculations
- `procps`, `psmisc` - Process management utilities

#### **Docker & Container Support**
- `docker-ce`, `docker-ce-cli`, `containerd.io` - Container platform
- `docker-buildx-plugin`, `docker-compose-plugin` - Extended Docker functionality

### **2. App-Services User**
Created dedicated `app-services` user for service management:

#### **User Configuration**
```bash
# User creation with home directory
useradd -m -s /bin/bash -c "Application Services User" app-services

# Group memberships
usermod -a -G docker app-services
usermod -a -G systemd-journal app-services
```

#### **Home Directory Setup**
- **SSH Directory**: `/home/app-services/.ssh` (proper permissions)
- **Local Bin**: `/home/app-services/.local/bin` (custom scripts)
- **Data Directory**: `/home/app-services/casaos-data` (CasaOS integration)

#### **Custom Bash Environment**
Enhanced `.bashrc` with:
- Useful aliases (`ll`, `la`, `ts` for Tailscale status)
- Router management shortcuts (`router-status`, `router-health`)
- PATH updates for local scripts
- Welcome message explaining available commands

### **3. Sudo Permissions**
Configured targeted sudo access for `app-services` user:

#### **Service Management (No Password)**
```bash
# Service control
/bin/systemctl status *, start/stop/restart casaos, cockpit.socket

# Tailscale monitoring
/usr/bin/tailscale status, ip, netcheck

# Log access
/bin/cat /var/log/igel-*.log, /bin/tail /var/log/igel-*.log
/bin/journalctl -u tailscaled, casaos, cockpit.socket

# Custom IGEL scripts
/usr/local/bin/igel-*, /usr/local/bin/router-*
```

### **4. Custom Management Scripts**
Created user-friendly scripts for the `app-services` user:

#### **CasaOS Management (`casa-manage`)**
```bash
casa-manage status   # Show CasaOS and Docker container status
casa-manage logs     # View CasaOS service logs
casa-manage restart  # Restart CasaOS service
```

#### **Router Status (`router-status`)**
- System uptime and resource usage
- Service status (Tailscale, CasaOS, Cockpit)
- Network interface information
- Memory and disk usage

#### **Router Health (`router-health`)**
- Comprehensive health diagnostics
- Disk and memory usage warnings
- Connectivity tests (Tailscale, Internet)
- Integration with full health check script when available

### **5. SSH Security Configuration**
Enhanced SSH setup for secure access:

#### **Access Control**
- Root login enabled (for system administration)
- `app-services` user SSH access
- Public key authentication enabled
- User restrictions: `AllowUsers root app-services`

#### **Service Integration**
- SSH service enabled and started
- Automatic restart after configuration changes
- Backup of original SSH configuration

### **6. System Service Integration**
Enhanced service management and monitoring:

#### **Docker Integration**
- Docker installed and configured
- `app-services` user added to docker group
- Container management capabilities for CasaOS

#### **Time Synchronization**
- `systemd-timesyncd` enabled for accurate timekeeping
- Important for VPN and log accuracy

#### **Automated Maintenance**
- Log rotation configured
- Cron jobs for maintenance tasks
- System monitoring and alerting

## 🔧 **Updated Installation Flow**

### **Installation Sequence**
1. **Root & Pre-flight checks** ✓
2. **Create app-services user** ⭐ NEW
3. **Interactive configuration** ✓
4. **System information** ✓
5. **Update system packages** ⭐ ENHANCED
6. **Configure IP forwarding** ✓
7. **Install & configure Tailscale** ✓
8. **Optional features** (eMMC, CasaOS, Cockpit, etc.) ✓
9. **Configure firewall** ✓
10. **Create monitoring & maintenance** ✓

### **Key Benefits**

#### **For System Administrators (root)**
- Complete system control and configuration
- All original IGEL router functionality preserved
- Enhanced security and monitoring capabilities

#### **For Service Management (app-services)**
- Safe, limited access for monitoring and basic management
- User-friendly commands for common tasks
- Docker container management capabilities
- Log access without full system privileges

#### **For Debian Minimal Systems**
- Complete package set for router functionality
- No missing dependencies or utilities
- Production-ready system from minimal installation

## 🚀 **Usage Examples**

### **SSH Access**
```bash
# Full administration
ssh root@router-ip

# Service management  
ssh app-services@router-ip
```

### **Service Management (app-services user)**
```bash
# Check overall router status
router-status

# Run health diagnostics
router-health

# Manage CasaOS containers
casa-manage status
casa-manage restart

# Check Tailscale
tailscale status  # (via sudo)
```

### **System Administration (root user)**
```bash
# Full IGEL management tools
igel-health-check
igel-maintenance health
igel-network-setup detect

# Direct service management
systemctl status tailscaled casaos cockpit.socket
```

## 🔒 **Security Model**

- **Root**: Full system administration
- **app-services**: Limited service management with specific sudo permissions
- **SSH**: Restricted to authorized users only
- **Firewall**: UFW configured with minimal required ports
- **Services**: Non-privileged where possible, specific privileges where needed

This enhancement provides a robust, secure, and user-friendly foundation for the IGEL M250C router while maintaining all existing functionality and adding powerful new management capabilities.
