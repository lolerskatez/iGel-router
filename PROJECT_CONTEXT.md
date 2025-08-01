# IGEL M250C Tailscale Subnet Router - Development Context

## Project Overview

**Project Name**: IGEL M250C Tailscale Subnet Router  
**Version**: 1.0.0  
**Created**: July 31, 2025  
**Last Updated**: July 31, 2025  
**Status**: Production Ready  

### Purpose
This project transforms an IGEL M250C thin client into a headless Tailscale subnet router and exit node using USB-booted Debian 12. The system provides secure remote access to private networks and can serve as an exit node for internet traffic routing.

### Target Hardware
- **Primary**: IGEL M250C thin client
- **CPU**: AMD GX-415GA SoC (4-core, 1.5GHz, 15W TDP)
- **RAM**: 2GB standard (4GB upgrade recommended)
- **Storage**: 3.5GB eMMC + 64GB+ USB 3.0 boot drive
- **Network**: Gigabit Ethernet + USB dongle support
- **Performance**: 100-200 Mbps routing throughput

## Architecture Overview

### System Components

1. **Base OS**: Debian 12 minimal/server (USB-booted)
2. **VPN Layer**: Tailscale with subnet routing and exit node
3. **Management UI**: CasaOS (primary) + Cockpit (optional)
4. **Network Stack**: NetworkManager + systemd-networkd
5. **Storage Optimization**: eMMC for swap/logs
6. **Monitoring**: Custom health monitoring service
7. **Connectivity**: USB Wi-Fi/cellular dongle support

### Network Architecture
```
Internet ──┐
           │
    ┌──────▼──────┐
    │   Router    │
    │ (Gateway)   │
    └──────┬──────┘
           │ Ethernet
    ┌──────▼──────┐
    │ IGEL M250C  │
    │ Tailscale   │ ←─── USB Dongles (Wi-Fi/Cellular)
    │ Router      │
    └──────┬──────┘
           │ Tailscale VPN
    ┌──────▼──────┐
    │  Remote     │
    │  Clients    │
    └─────────────┘
```

## File Structure & Organization

### Directory Structure
```
iGel/
├── install.sh                    # Main installation script (428 lines)
├── README.md                     # User documentation
├── DEPLOYMENT.md                 # Deployment guide
├── PROJECT_CONTEXT.md            # This file
├── .github/
│   └── copilot-instructions.md   # AI assistant guidelines
├── .vscode/
│   └── tasks.json                # VS Code deployment tasks
├── configs/                      # Configuration templates
│   ├── tailscale/
│   │   ├── tailscaled.conf       # Daemon configuration template
│   │   └── connect.sh            # Connection helper script
│   ├── network/
│   │   ├── 10-ethernet.network   # Ethernet priority config
│   │   └── 20-wifi.network       # Wi-Fi priority config
│   └── systemd/
│       ├── igel-monitor.service  # System monitoring service
│       └── igel-emmc.service     # eMMC optimization service
├── scripts/                      # Utility scripts
│   ├── emmc-setup.sh            # eMMC configuration (320 lines)
│   ├── usb-dongle-setup.sh      # USB device support (380 lines)
│   ├── backup-config.sh         # Configuration backup (245 lines)
│   ├── network-setup.sh         # Network interface setup (260 lines)
│   └── maintenance.sh           # System maintenance (420 lines)
└── docs/                        # Documentation
    ├── hardware-specs.md        # Hardware specifications
    └── security-config.md       # Security configuration guide
```

### Key Files Description

#### Core Installation (`install.sh`)
- **Purpose**: Main installation orchestrator
- **Functions**: 15 major functions covering full system setup
- **Features**:
  - Pre-flight system validation
  - Automated package installation
  - Tailscale configuration with subnet routing
  - eMMC optimization
  - Web UI installation (CasaOS/Cockpit)
  - Firewall configuration
  - System monitoring setup
  - Error handling with rollback
- **Environment Variables**:
  - `TAILSCALE_AUTH_KEY`: Auth key for automated setup
  - `INSTALL_COCKPIT`: Enable/disable Cockpit (default: true)
  - `USE_EMMC`: Enable/disable eMMC usage (default: true)

#### Network Management (`scripts/network-setup.sh`)
- **Purpose**: Advanced network interface configuration
- **Features**:
  - Interface detection and prioritization
  - NetworkManager optimization
  - systemd-networkd configuration
  - Connectivity testing
- **Priority System**:
  - Ethernet: Metric 100 (highest priority)
  - Wi-Fi: Metric 200 (medium priority)
  - Cellular/USB: Metric 300 (lowest priority)

#### System Maintenance (`scripts/maintenance.sh`)
- **Purpose**: Automated system maintenance and health monitoring
- **Functions**:
  - Health checks (disk, memory, services)
  - System updates (OS + Tailscale)
  - Performance optimization
  - System cleanup
  - Alert monitoring
- **Automation**: Cron jobs for daily/weekly/monthly tasks

#### eMMC Management (`scripts/emmc-setup.sh`)
- **Purpose**: Optimize internal eMMC storage usage
- **Features**:
  - Device detection and validation
  - Swap partition creation
  - Log storage partition
  - Wear leveling considerations
- **Safety**: Preserves existing data, validates size requirements

#### USB Dongle Support (`scripts/usb-dongle-setup.sh`)
- **Purpose**: Enable Wi-Fi and cellular USB dongles
- **Supported Devices**:
  - Wi-Fi: Realtek RTL8188EUS, RTL8192EU, Ralink RT5370/5372
  - Cellular: Huawei, ZTE, Sierra Wireless, Quectel modems
- **Features**:
  - Automatic device detection
  - Mode switching support
  - Connection helpers

#### Configuration Backup (`scripts/backup-config.sh`)
- **Purpose**: System configuration backup and restore
- **Coverage**:
  - System configurations
  - Network settings
  - Tailscale state
  - CasaOS/Cockpit configs
  - Custom scripts and logs
- **Format**: Compressed tar.gz with metadata

## Design Decisions & Rationale

### Technology Choices

#### Tailscale over Traditional VPN
- **Reasoning**: Simplified mesh networking, automatic NAT traversal, modern cryptography
- **Benefits**: Zero-config peer-to-peer connections, automatic key rotation
- **Trade-offs**: Dependency on Tailscale service, vendor lock-in

#### CasaOS as Primary UI
- **Reasoning**: User-friendly interface, Docker integration, low resource usage
- **Benefits**: Easy service management, modern web UI, extensible
- **Trade-offs**: Less advanced than traditional solutions

#### USB Boot over eMMC Installation
- **Reasoning**: Preserves original IGEL firmware, easy recovery, larger storage
- **Benefits**: Non-destructive installation, easy updates, better performance
- **Trade-offs**: Potential USB wear, dependency on external storage

#### NetworkManager + systemd-networkd Combination
- **Reasoning**: Best of both worlds - GUI support + advanced configuration
- **Benefits**: USB dongle support, interface prioritization, automatic failover
- **Trade-offs**: Complexity, potential conflicts

### Architecture Decisions

#### Modular Script Design
- **Reasoning**: Maintainability, testability, flexibility
- **Implementation**: Separate scripts for major functions with clear interfaces
- **Benefits**: Easy debugging, selective execution, reusability

#### Configuration Template Approach
- **Reasoning**: Consistency, version control, easy customization
- **Implementation**: Template files in `configs/` directory
- **Benefits**: Reproducible deployments, documentation as code

#### Comprehensive Error Handling
- **Reasoning**: Production reliability, user experience
- **Implementation**: Trap handlers, rollback procedures, detailed logging
- **Benefits**: Graceful failure handling, easier troubleshooting

#### Multi-level Monitoring
- **Reasoning**: Proactive maintenance, system reliability
- **Implementation**: Real-time monitoring + scheduled health checks
- **Benefits**: Early problem detection, automated maintenance

## Development Standards & Conventions

### Shell Scripting Standards
- **Error Handling**: `set -euo pipefail` in all scripts
- **Logging**: Consistent timestamp format with color coding
- **Variable Naming**: `UPPER_CASE` for constants, `lower_case` for locals
- **Function Structure**: Clear purpose, parameter validation, error handling
- **Documentation**: Function comments, usage examples, troubleshooting notes

### Configuration Management
- **File Naming**: Descriptive names with numeric prefixes for ordering
- **Template Format**: Here-documents for multi-line configurations
- **Version Control**: All configurations tracked in git
- **Validation**: Syntax checking before deployment

### Testing Strategy
- **Unit Testing**: Individual script functions tested in isolation
- **Integration Testing**: Full installation tested on target hardware
- **Regression Testing**: Previous functionality verified after changes
- **Performance Testing**: Resource usage and throughput validation

## System Integration Points

### Service Dependencies
```
tailscaled ──┐
             ├─── igel-monitor
casaos ──────┘

NetworkManager ─── usb-modeswitch
                └─ ModemManager

systemd-networkd ─── systemd-resolved
```

### Configuration Interactions
- **Network**: NetworkManager configs override systemd-networkd for USB devices
- **Firewall**: UFW rules coordinate with Tailscale interface
- **Storage**: eMMC swap complements USB root filesystem
- **Monitoring**: Service status affects health check results

### Data Flow
1. **Network Traffic**: Physical → NetworkManager → Tailscale → Remote clients
2. **Configuration**: Templates → Runtime configs → Active services
3. **Monitoring**: Service status → Health checks → Log aggregation → Alerts
4. **Maintenance**: Scheduled tasks → System updates → Performance optimization

## Performance Characteristics

### Resource Usage (Typical)
- **CPU**: 20-40% average, 60-80% during routing peaks
- **Memory**: 1.5-2.5GB used (out of 4GB with upgrade)
- **Disk**: <2GB for OS, logs rotated to prevent growth
- **Network**: 100-200 Mbps routing throughput

### Scaling Limitations
- **CPU Bound**: Single-threaded Tailscale daemon limits throughput
- **Memory Bound**: Large routing tables consume RAM
- **Storage Bound**: USB wear limits write-heavy applications
- **Thermal Bound**: Fanless design limits sustained load

### Optimization Strategies
- **Network Buffers**: Tuned for routing workload
- **Swap Usage**: Minimized to reduce USB wear
- **Process Priorities**: Critical services prioritized
- **Cache Management**: Memory caches cleared under pressure

## Security Model

### Attack Surface
- **Network**: SSH, HTTP/HTTPS, Tailscale
- **Physical**: USB ports, console access
- **Software**: Package repositories, container images
- **Configuration**: Service credentials, certificates

### Mitigation Strategies
- **Network**: Firewall rules, service binding, VPN encryption
- **Physical**: Secure mounting, port blocking (if needed)
- **Software**: Automated updates, package verification
- **Configuration**: File permissions, credential rotation

### Monitoring Points
- **Authentication**: SSH login attempts, service access
- **Network**: Connection attempts, traffic patterns
- **System**: Resource usage, service status
- **Configuration**: File changes, permission modifications

## Deployment Scenarios

### Development Environment
- **Hardware**: Virtual machine or spare hardware
- **Network**: Local network with internet access
- **Purpose**: Feature development, testing, validation

### Staging Environment
- **Hardware**: Identical to production (IGEL M250C)
- **Network**: Isolated test network
- **Purpose**: Integration testing, performance validation

### Production Environment
- **Hardware**: IGEL M250C with 4GB RAM upgrade
- **Network**: Production network with proper routing
- **Purpose**: Live traffic routing, remote access

### Emergency Recovery
- **Hardware**: Backup IGEL device with identical configuration
- **Network**: Same network segment as primary
- **Purpose**: Service continuity during primary device failure

## Troubleshooting Framework

### Diagnostic Hierarchy
1. **Service Level**: Individual service status and logs
2. **System Level**: Resource usage, kernel messages
3. **Network Level**: Interface status, routing tables
4. **Application Level**: Tailscale connectivity, web UI access

### Common Issues & Solutions

#### Tailscale Connection Problems
- **Symptoms**: Unable to connect to network, peers not visible
- **Diagnosis**: `tailscale status`, service logs, network connectivity
- **Solutions**: Re-authentication, firewall rules, network configuration

#### High Resource Usage
- **Symptoms**: System slowdown, service failures
- **Diagnosis**: `htop`, `iotop`, memory usage analysis
- **Solutions**: Service restart, cache clearing, load balancing

#### USB Dongle Issues
- **Symptoms**: Device not detected, connection failures
- **Diagnosis**: `lsusb`, NetworkManager logs, mode switch status
- **Solutions**: Driver installation, manual mode switching, USB reset

#### eMMC Problems
- **Symptoms**: Swap failures, filesystem errors
- **Diagnosis**: `dmesg`, filesystem checks, SMART data
- **Solutions**: Filesystem repair, partition recreation, device replacement

### Log Analysis Strategy
- **System Logs**: `/var/log/syslog` for general system events
- **Service Logs**: `journalctl -u service-name` for specific services
- **Custom Logs**: `/var/log/igel-*.log` for installation and monitoring
- **Network Logs**: NetworkManager and Tailscale specific logs

## Future Development Considerations

### Potential Enhancements
1. **Web Dashboard**: Custom monitoring dashboard
2. **Container Support**: Docker/Podman integration
3. **Load Balancing**: Multiple device coordination
4. **Advanced Routing**: Policy-based routing, QoS
5. **Remote Management**: SSH tunneling, remote console

### Scalability Improvements
1. **Clustering**: Multiple IGEL devices in HA configuration
2. **Load Distribution**: Traffic splitting across devices
3. **Central Management**: Configuration management system
4. **Monitoring Integration**: Prometheus/Grafana integration

### Hardware Variations
1. **Newer Models**: IGEL M350C, M365C support
2. **Alternative Hardware**: Raspberry Pi, Intel NUC adaptations
3. **Performance Variants**: Higher-spec devices for increased throughput

### Software Evolution
1. **OS Updates**: Debian version upgrades
2. **Tailscale Features**: New capabilities integration
3. **Container Technologies**: Kubernetes, serverless functions
4. **Security Enhancements**: Zero-trust architecture, certificate management

## Development Workflow

### Local Development
1. **Setup**: Clone repository, review documentation
2. **Testing**: VM-based testing, script validation
3. **Integration**: Feature integration, conflict resolution
4. **Documentation**: Update context, README, comments

### Deployment Process
1. **Preparation**: Configuration review, backup creation
2. **Staging**: Test deployment in staging environment
3. **Production**: Controlled rollout with monitoring
4. **Validation**: Functional testing, performance verification

### Maintenance Cycle
1. **Monitoring**: Daily automated health checks
2. **Updates**: Weekly system updates, monthly full maintenance
3. **Backups**: Daily configuration backups
4. **Reviews**: Monthly performance and security reviews

## Dependencies & External Services

### Critical Dependencies
- **Tailscale Service**: VPN mesh networking
- **Debian Repositories**: Package management
- **CasaOS Project**: Web UI updates
- **Hardware Vendor**: Driver support

### Optional Dependencies
- **Cockpit Project**: Advanced management UI
- **USB Device Vendors**: Driver updates
- **DNS Providers**: Resolution services

### Risk Mitigation
- **Local Repositories**: Mirror critical packages
- **Offline Capabilities**: Essential functions work without internet
- **Alternative Solutions**: Backup options for critical components
- **Documentation**: Comprehensive troubleshooting guides

## Change Management

### Version Control Strategy
- **Main Branch**: Production-ready code
- **Development Branch**: Active development
- **Feature Branches**: Individual feature development
- **Release Tags**: Stable release points

### Testing Requirements
- **Script Validation**: Syntax and logic testing
- **Integration Testing**: Full system deployment
- **Performance Validation**: Resource usage verification
- **Security Review**: Vulnerability assessment

### Release Process
1. **Development**: Feature development and testing
2. **Integration**: Merge and integration testing
3. **Staging**: Full deployment testing
4. **Documentation**: Update all documentation
5. **Release**: Tag and deploy to production

This context file provides comprehensive information for continuing development of the IGEL M250C Tailscale router project. It captures the current state, design decisions, and future considerations necessary for effective project maintenance and enhancement.
