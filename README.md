# IGEL M250C Tailscale Subnet Router

This project sets up an IGEL M250C thin client as a headless Tailscale subnet router and exit node using a USB-booted Debian OS.

## Features

✅ **Tailscale Integration**: Installed and configured with `--advertise-routes` and `--advertise-exit-node`  
✅ **CasaOS Web UI**: User-friendly web interface for managing services  
✅ **Optional Cockpit**: Advanced web UI (port 9090) for system and network management  
✅ **eMMC Optimization**: Automatically detects and uses onboard 3.5GB eMMC for swap or logs to reduce USB wear  
✅ **USB Dongle Support**: Includes NetworkManager, ModemManager, and usb-modeswitch for Wi-Fi or cellular connectivity  
✅ **System Monitoring**: Built-in monitoring service for system health  
✅ **Firewall Configuration**: Automated UFW setup with appropriate port access  
✅ **Network Optimization**: Advanced network interface prioritization and routing  
✅ **Automated Maintenance**: Scheduled health checks, updates, and system optimization  
✅ **Pre-flight Validation**: Hardware compatibility and system requirement checks  
✅ **Error Recovery**: Comprehensive error handling with rollback capabilities  

## Requirements

- **Hardware**: IGEL M250C thin client (preferably upgraded to 4GB RAM)
- **Storage**: 64GB+ USB 3.0 stick for OS installation
- **OS**: Debian 12 minimal/server installed on USB (eMMC left untouched)
- **Network**: Internet access via LAN or supported USB dongle

## Quick Start

### Interactive Installation (Recommended)

The easiest way to set up your IGEL M250C router is using the interactive installer:

```bash
# Make the script executable
chmod +x install.sh

# Run interactive installation (will guide you through configuration)
sudo ./install.sh
```

The interactive installer will prompt you to configure:
- **Device hostname** (how it appears in Tailscale)  
- **Tailscale authentication key** (from your Tailscale admin panel)
- **Network routes** to advertise (with smart defaults)
- **eMMC storage usage** (recommended for better performance)
- **Management interfaces** (CasaOS always included, Cockpit optional)

### Non-Interactive Installation

For automated deployments or when you want to pre-configure everything:

```bash
# Full automated installation
sudo ./install.sh --non-interactive \
    --tailscale-key=tskey-auth-your-key-here \
    --hostname=office-router \
    --routes=192.168.1.0/24,10.0.0.0/8 \
    --no-cockpit

# Using environment variables
sudo TAILSCALE_AUTH_KEY='tskey-your-key-here' \
     DEVICE_HOSTNAME='home-router' \
     INSTALL_COCKPIT=false \
     ./install.sh --non-interactive
```

### Command Line Options

```bash
sudo ./install.sh [OPTIONS]

OPTIONS:
    -h, --help                 Show help message
    --non-interactive          Skip interactive prompts  
    --tailscale-key=KEY        Tailscale auth key
    --hostname=NAME            Device hostname
    --routes=ROUTES            Comma-separated CIDR routes
    --no-cockpit               Skip Cockpit installation
    --no-emmc                  Skip eMMC configuration
```

### Getting Your Tailscale Auth Key
   - Visit [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
   - Generate a new auth key with appropriate permissions
   - Copy and paste it when prompted during installation

4. **Access web interfaces**:
   - **CasaOS**: http://your-device-ip (port 80)
   - **Cockpit** (if installed): https://your-device-ip:9090

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAILSCALE_AUTH_KEY` | - | Tailscale authentication key for automated setup |
| `INSTALL_COCKPIT` | `true` | Install Cockpit web management interface |
| `USE_EMMC` | `true` | Use eMMC storage for swap and log optimization |

### Network Routes

The setup advertises the following subnet routes by default:
- `192.168.0.0/16` - Private Class C networks
- `10.0.0.0/8` - Private Class A networks  
- `172.16.0.0/12` - Private Class B networks

## What Gets Installed

### Core Components
- **Tailscale**: VPN mesh networking with subnet routing and exit node capabilities
- **CasaOS**: Web-based service management dashboard
- **NetworkManager + ModemManager**: USB dongle and wireless connectivity support

### Optional Components
- **Cockpit**: Advanced system management web interface
- **System Monitor**: Custom monitoring service for health checks

### System Optimizations
- IP forwarding enabled for routing functionality
- eMMC configured as swap space (if available)
- Reduced journal logging to minimize USB wear
- UFW firewall with appropriate port access
- Log rotation configuration

## File Structure

```
iGel/
├── install.sh              # Main installation script
├── configs/                 # Configuration files
│   ├── tailscale/          # Tailscale configuration templates
│   ├── network/            # Network configuration files
│   └── systemd/            # Systemd service files
├── scripts/                # Additional utility scripts
│   ├── emmc-setup.sh       # eMMC configuration script
│   ├── usb-dongle-setup.sh # USB dongle setup script
│   ├── backup-config.sh    # Configuration backup script
│   ├── network-setup.sh    # Network interface configuration
│   └── maintenance.sh      # System maintenance and updates
└── docs/                   # Documentation
    ├── hardware-specs.md   # Hardware specifications
    └── security-config.md  # Security configuration guide
```

## Usage Examples

### Basic Setup
```bash
# Interactive setup (recommended)
sudo ./install.sh

# Follow the prompts to enter your Tailscale auth key
```

### Automated Setup with Tailscale Key
```bash
sudo TAILSCALE_AUTH_KEY='tskey-auth-...' ./install.sh
```

### Minimal Installation (no Cockpit, no eMMC)
```bash
sudo INSTALL_COCKPIT=false USE_EMMC=false ./install.sh
```

## Post-Installation

### Tailscale Administration
1. Log into your Tailscale admin console
2. Navigate to the "Machines" tab
3. Find your IGEL device (hostname: `igel-m250c-router`)
4. Enable "Subnet routes" and "Exit node" as needed

### Service Management
```bash
# Check service status
systemctl status tailscaled casaos cockpit.socket igel-monitor

# View logs
tail -f /var/log/igel-setup.log
tail -f /var/log/igel-monitor.log

# Restart services
systemctl restart tailscaled
systemctl restart casaos

# Run system maintenance
/usr/local/bin/igel-maintenance health
/usr/local/bin/igel-maintenance update
```

### Network Testing
```bash
# Test Tailscale connectivity
tailscale status
tailscale ping [device-name]

# Test routing
ip route show
iptables -t nat -L
```

## Troubleshooting

### Common Issues

**Tailscale not connecting:**
```bash
# Check service status
systemctl status tailscaled

# Check logs
journalctl -u tailscaled -f

# Re-authenticate
tailscale logout
tailscale up --advertise-routes=192.168.0.0/16,10.0.0.0/8,172.16.0.0/12 --advertise-exit-node
```

**CasaOS not accessible:**
```bash
# Check service status
systemctl status casaos

# Check if port is open
netstat -tlnp | grep :80

# Restart service
systemctl restart casaos
```

**USB dongle not recognized:**
```bash
# Check USB devices
lsusb

# Check network interfaces
ip link show

# Restart NetworkManager
systemctl restart NetworkManager
```

### Log Files

- Main setup log: `/var/log/igel-setup.log`
- Monitor log: `/var/log/igel-monitor.log`
- System logs: `journalctl -u [service-name]`

## Hardware Notes

### IGEL M250C Specifications
- **CPU**: AMD GX-415GA (Quad-core, 1.5GHz)
- **RAM**: 2GB standard (upgradeable to 4GB recommended)
- **Storage**: 3.5GB eMMC + USB boot drive
- **Network**: Gigabit Ethernet, optional USB Wi-Fi/cellular
- **Ports**: 4x USB, VGA, DVI, audio

### Performance Expectations
- **Routing throughput**: ~100-200 Mbps (depending on CPU load)
- **Power consumption**: ~15W typical
- **Boot time**: ~30-60 seconds from USB

## Security Considerations

- UFW firewall enabled with minimal required ports
- Tailscale handles VPN encryption and authentication
- Regular security updates via automated system updates
- Log rotation prevents disk space exhaustion

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is provided as-is for educational and personal use.
