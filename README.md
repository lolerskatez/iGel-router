# TailSentry - Universal Tailscale Router Solution

TailSentry transforms any compatible hardware into a powerful headless Tailscale subnet router and exit node using a Debian-based Linux distribution.

## Features

✅ **Flexible VPN Options**: Choose between Tailscale, self-hosted Headscale, or both  
✅ **Hardware Agnostic**: Works on virtually any Debian-compatible device  
✅ **WiFi Management**: Connect to external networks or create access points  
✅ **"Coffee Shop" Mode**: Share connections through secure VPN even on restrictive networks  
✅ **CasaOS Web UI**: User-friendly web interface for managing services  
✅ **Web Dashboard**: Built-in TailSentry dashboard for router management  
✅ **Optional Cockpit**: Advanced web UI for system and network management  
✅ **Storage Optimization**: Smart secondary storage configuration for improved performance  
✅ **USB Dongle Support**: Includes NetworkManager, ModemManager, and usb-modeswitch for Wi-Fi or cellular connectivity  
✅ **System Monitoring**: Built-in monitoring service for system health  
✅ **Firewall Configuration**: Automated UFW setup with appropriate port access  
✅ **Network Optimization**: Advanced network interface prioritization and routing  
✅ **Automated Maintenance**: Scheduled health checks, updates, and system optimization  
✅ **Pre-flight Validation**: Hardware compatibility and system requirement checks  
✅ **Error Recovery**: Comprehensive error handling with rollback capabilities  

## Requirements

- **Hardware**: Any compatible device (Raspberry Pi, old PC, thin client, etc.)
- **Minimum Specs**: 2 CPU cores, 2GB RAM, 8GB storage
- **OS**: Debian 12 minimal/server
- **Network**: Internet access via LAN or supported WiFi/cellular

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
- **Secondary storage usage** (for improved performance)
- **Management interfaces** (CasaOS always included, Cockpit optional)
- **WiFi connectivity options**

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
    --no-casaos                Skip CasaOS installation
```

### Getting Your Tailscale Auth Key
   - Visit [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
   - Generate a new auth key with appropriate permissions
   - Copy and paste it when prompted during installation

### Access web interfaces
- **TailSentry Dashboard**: http://your-device-ip:8088
- **CasaOS**: http://your-device-ip (port 80)
- **Cockpit** (if installed): https://your-device-ip:9090

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAILSCALE_AUTH_KEY` | - | Tailscale authentication key for automated setup |
| `INSTALL_COCKPIT` | `true` | Install Cockpit web management interface |
| `INSTALL_CASAOS` | `true` | Install CasaOS container management |
| `USE_SECONDARY_STORAGE` | `false` | Use secondary storage device if available |
| `DEVICE_HOSTNAME` | `tailsentry-router` | Device hostname in Tailscale |
| `ADVERTISED_ROUTES` | `192.168.0.0/16,10.0.0.0/8,172.16.0.0/12` | Networks to route through VPN |

### Network Routes

The setup advertises the following subnet routes by default:
- `192.168.0.0/16` - Private Class C networks
- `10.0.0.0/8` - Private Class A networks  
- `172.16.0.0/12` - Private Class B networks

## WiFi Management

TailSentry includes comprehensive WiFi management capabilities:

### WiFi Client Mode
- Connect to external WiFi networks (e.g., apartment complexes, coffee shops)
- Scan, connect, and manage credentials through the web dashboard
- Persist connections across reboots

### Access Point Mode
- Create your own WiFi network with your TailSentry device (requires compatible hardware)
- Configure SSID, password, and channel through the web dashboard
- Share internet with local devices

### "Coffee Shop" Gateway Mode
- Connect to a public WiFi network and share it via Tailscale
- Perfect for sharing a single WiFi connection among multiple devices
- Bypass common captive portal restrictions
- Maintain privacy through encrypted Tailscale tunnel

## What Gets Installed

### Core Components
- **Tailscale**: VPN mesh networking with subnet routing and exit node capabilities
- **TailSentry Dashboard**: Web-based management interface
- **CasaOS**: Container and service management
- **NetworkManager + ModemManager**: USB dongle and wireless connectivity support

### Optional Components
- **Cockpit**: Advanced system management web interface
- **System Monitor**: Custom monitoring service for health checks
- **Headscale**: Self-hosted Tailscale coordination server (optional)

### System Optimizations
- IP forwarding enabled for routing functionality
- Secondary storage configuration for swap and logs
- Reduced journal logging to minimize storage wear
- UFW firewall with appropriate port access
- Log rotation configuration

## File Structure

```
TailSentry/
├── install.sh              # Main installation script
├── configs/                # Configuration files
│   ├── tailscale/          # Tailscale configuration templates
│   ├── network/            # Network configuration files
│   └── systemd/            # Systemd service files
├── scripts/                # Additional utility scripts
│   ├── wifi-manager.sh     # WiFi management script
│   ├── gateway-setup.sh    # Coffee shop gateway setup
│   ├── backup-config.sh    # Configuration backup script
│   ├── network-setup.sh    # Network interface configuration
│   └── maintenance.sh      # System maintenance and updates
├── web-dashboard/          # Web interface code
│   ├── app.py              # Flask application
│   ├── api/                # API endpoints
│   ├── static/             # Static assets
│   └── templates/          # HTML templates
└── docs/                   # Documentation
```

## Usage Examples

### Basic Setup
```bash
# Interactive setup (recommended)
sudo ./install.sh

# Follow the prompts to configure your router
```

### WiFi Gateway (Coffee Shop Mode)
```bash
# Set up through the dashboard or use:
sudo tailsentry-gateway wlan0 "CoffeeShopWiFi" "password123"
```

### Setup with WiFi Access Point
```bash
# Set up a TailSentry with AP mode:
sudo ./install.sh
# Then use the dashboard or:
sudo tailsentry-wifi start-ap wlan0 "TailSentryAP" "securepassword"
```

## Post-Installation

### Tailscale Administration
1. Log into your Tailscale admin console
2. Navigate to the "Machines" tab
3. Find your TailSentry device
4. Enable "Subnet routes" and "Exit node" as needed

### Service Management
```bash
# Check service status
systemctl status tailscaled casaos cockpit.socket tailsentry-monitor

# View logs
tail -f /var/log/tailsentry-setup.log
tail -f /var/log/tailsentry-monitor.log

# Restart services
systemctl restart tailscaled
systemctl restart casaos
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

**WiFi connection issues:**
```bash
# Check WiFi interface status
sudo tailsentry-wifi status wlan0

# Scan for networks
sudo tailsentry-wifi scan wlan0

# Restart connection
sudo nmcli radio wifi off
sudo nmcli radio wifi on
```

### Log Files

- Main setup log: `/var/log/tailsentry-setup.log`
- Monitor log: `/var/log/tailsentry-monitor.log`
- WiFi log: `/var/log/tailsentry-wifi.log`
- System logs: `journalctl -u [service-name]`

## Hardware Compatibility

TailSentry has been tested on:
- Raspberry Pi 3/4/5
- IGEL M250C thin clients
- Intel NUC
- Various x86_64 and ARM devices

### Performance Expectations
- Raspberry Pi 3B+: ~80-150 Mbps routing throughput
- Raspberry Pi 4/5: ~300-500 Mbps routing throughput
- x86 (2+ cores): ~200-1000+ Mbps (CPU dependent)

## Security Considerations

- UFW firewall enabled with minimal required ports
- Tailscale handles VPN encryption and authentication
- Regular security updates via automated system updates
- Log rotation prevents disk space exhaustion

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is provided under the MIT License. See LICENSE file for details.
