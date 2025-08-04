# IGEL M250C Router - Optional Features Implementation

## Overview
The IGEL M250C Tailscale router installation script has been updated to make **ALL features optional except Tailscale**. This provides maximum flexibility for users who want different levels of functionality.

## ✅ What's Required
- **Tailscale VPN** - This is the only mandatory component as it's the core purpose of the router

## 🔧 What's Now Optional

### Web Management Interfaces
- **CasaOS** - Docker container management web UI (previously always installed)
- **Cockpit** - Advanced system management interface

### System Features
- **eMMC Storage** - Using internal eMMC for swap and logs
- **Security Hardening** - fail2ban, SSH hardening, automatic updates
- **System Monitoring** - Health monitoring service and alerts
- **Maintenance Scripts** - Automated backups, health checks, and updates
- **System Optimization** - Performance tuning and USB drive preservation

## 🚀 New Command Line Options

### Preset Configurations
```bash
# Minimal installation - Tailscale only
sudo ./install.sh --minimal

# Full installation - all features enabled  
sudo ./install.sh --full

# Interactive installation - user chooses features
sudo ./install.sh
```

### Individual Feature Controls
```bash
# Skip specific features
sudo ./install.sh --no-casaos --no-cockpit --no-monitoring

# Non-interactive minimal setup
sudo ./install.sh --non-interactive --minimal --tailscale-key=tskey-auth-...
```

### Complete Option List
- `--minimal` - Tailscale only (fastest, lightest installation)
- `--full` - Enable all features (comprehensive setup)
- `--no-casaos` - Skip CasaOS Docker management
- `--no-cockpit` - Skip Cockpit system management
- `--no-emmc` - Don't use eMMC storage
- `--no-security` - Skip security hardening
- `--no-monitoring` - Skip system monitoring
- `--no-maintenance` - Skip maintenance automation
- `--no-optimization` - Skip system optimizations

## 🔄 Interactive Configuration
When run without preset options, the script now prompts for each optional feature with clear descriptions:

```
╔═══════════════════════════════════════════════════════════════════════╗
║                      IGEL M250C Router Setup                          ║
║                   Interactive Configuration                           ║
╚═══════════════════════════════════════════════════════════════════════╝

This wizard will guide you through configuring your IGEL M250C as a
Tailscale subnet router. Only Tailscale is required - all other features are optional.

Web Management Interface - CasaOS
CasaOS provides a user-friendly web interface for managing Docker containers and services:
  • Easy Docker container management
  • App store for common applications  
  • File management and media server capabilities

Install CasaOS for container management? [y/N]:
```

## 📊 Configuration Summary
The script now shows exactly what will be installed:

```
╔═══════════════════════════════════════════════════════════════════════╗
║                        Configuration Summary                          ║
╚═══════════════════════════════════════════════════════════════════════╝

Device Hostname: igel-m250c-router
Use eMMC Storage: false
Install CasaOS: false  
Install Cockpit: false
Network Interface Mode: auto
Security Hardening: false
System Monitoring: false
Maintenance Scripts: false
System Optimization: false
Advertised Routes: 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12
Tailscale Auth Key: [Will prompt later]
```

## 🌐 Environment Variables
All options can also be set via environment variables:

```bash
export INSTALL_CASAOS=true
export INSTALL_COCKPIT=false
export ENABLE_SECURITY_HARDENING=true
export ENABLE_MONITORING=false
# ... etc

sudo ./install.sh --non-interactive
```

## ⚡ Installation Examples

### Minimal Router (Fastest)
```bash
# Just Tailscale VPN routing - perfect for dedicated routers
sudo ./install.sh --minimal --tailscale-key=tskey-auth-your-key
```

### Home Lab Router  
```bash
# Add Docker management for running services
sudo ./install.sh --no-cockpit --no-security --hostname=homelab-router
```

### Enterprise Router
```bash
# Full security and monitoring for production use
sudo ./install.sh --full --hostname=office-router
```

### Custom Configuration
```bash
# Pick exactly what you want
sudo ./install.sh --no-casaos --no-emmc --hostname=custom-router
```

## 🎯 Benefits

1. **Faster Installation** - Skip unneeded features for quicker setup
2. **Resource Efficiency** - Use only what you need on limited hardware
3. **Flexibility** - From minimal routers to full home labs
4. **User Choice** - Clear interactive prompts explain each feature
5. **Scripting Friendly** - Environment variables and presets for automation

## 🔧 What Changed in the Code

- Added 5 new configuration variables for optional features
- Updated interactive prompts to explain each feature clearly
- Made default responses "No" for optional features (except full preset)
- Added `--minimal` and `--full` preset options
- Updated help documentation with examples
- Modified main installation flow to respect feature flags
- Updated status display to show only installed components

## 🚦 Default Behavior
- **Interactive mode**: Prompts for each feature with clear descriptions
- **Non-interactive mode**: Requires explicit configuration via flags or environment variables
- **Minimal preset**: Only Tailscale (fastest, lightest)
- **Full preset**: All features enabled (comprehensive setup)

This update makes the IGEL router script much more flexible while keeping Tailscale as the core required component!
