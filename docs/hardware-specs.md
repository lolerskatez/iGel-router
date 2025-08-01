# IGEL M250C Hardware Specifications

## Overview
The IGEL M250C is a compact thin client designed for VDI (Virtual Desktop Infrastructure) environments. This document outlines its hardware specifications and compatibility for use as a Tailscale subnet router.

## Hardware Specifications

### Processor
- **Model**: AMD GX-415GA SoC (System-on-Chip)
- **Architecture**: x86-64 (AMD64)
- **Cores**: 4 cores
- **Base Clock**: 1.5 GHz
- **TDP**: 15W
- **Features**: Hardware-accelerated video decoding, low power consumption

### Memory
- **Standard**: 2GB DDR3L-1600
- **Maximum**: 4GB DDR3L-1600 (via upgrade)
- **Form Factor**: SO-DIMM
- **Upgrade**: Single slot, user-accessible

### Storage
- **Primary**: 3.5GB eMMC (soldered, non-removable)
- **Boot**: USB 3.0 external drive (64GB+ recommended)
- **eMMC Usage**: Swap space, log storage, temporary files

### Network Connectivity
- **Ethernet**: Realtek RTL8111G Gigabit Ethernet
- **Speed**: 10/100/1000 Mbps
- **Features**: Wake-on-LAN, Auto-MDI/MDIX

### USB Ports
- **USB 3.0**: 2 ports (Type-A)
- **USB 2.0**: 2 ports (Type-A)
- **Power**: 5V/0.9A per port
- **Use Cases**: Wi-Fi dongles, cellular modems, external storage

### Display Outputs
- **VGA**: 1x VGA port (1920x1200 max)
- **DVI**: 1x DVI-D port (1920x1200 max)
- **Audio**: 3.5mm headphone/line out

### Power
- **Consumption**: ~15W typical, ~20W maximum
- **Input**: 12V DC, 3A external adapter
- **Efficiency**: Energy Star certified

### Physical Dimensions
- **Width**: 165mm (6.5")
- **Depth**: 165mm (6.5")
- **Height**: 35mm (1.4")
- **Weight**: 0.8kg (1.76 lbs)
- **Mounting**: VESA 75x75mm compatible

## Compatibility for Router Use

### Performance Expectations
- **Routing Throughput**: 100-200 Mbps (CPU-limited)
- **Concurrent Connections**: 50-100 typical
- **VPN Overhead**: ~10-20% performance impact
- **Memory Usage**: 1-2GB for routing + services

### Network Interface Support
- **Ethernet**: Full Gigabit support with hardware offloading
- **Wi-Fi Dongles**: USB 2.0/3.0 adapters supported
- **Cellular Modems**: USB modems with ModemManager support
- **Multiple Interfaces**: Bonding and failover supported

### Thermal Considerations
- **Operating Temperature**: 0°C to 40°C (32°F to 104°F)
- **Fanless Design**: Passive cooling only
- **Ventilation**: Ensure adequate airflow around device
- **Mounting**: Vertical orientation recommended for best cooling

### Power Efficiency
- **24/7 Operation**: Designed for continuous use
- **Power Management**: ACPI support for sleep states
- **UPS Compatibility**: Works with standard 12V UPS systems

## USB Dongle Compatibility

### Tested Wi-Fi Dongles
| Vendor ID | Product ID | Chipset | Notes |
|-----------|------------|---------|-------|
| 0bda:8179 | RTL8188EUS | Realtek | Good Linux support |
| 0bda:818b | RTL8192EU | Realtek | Dual-band capable |
| 148f:5370 | RT5370 | Ralink | Stable performance |
| 148f:5372 | RT5372 | Ralink | High power output |
| 0cf3:9271 | AR9271 | Atheros | Monitor mode support |

### Cellular Modem Support
- **Huawei**: E3372, E8372, most USB modems
- **ZTE**: MF79U, MF823, MF833
- **Sierra Wireless**: EM7455, MC7455
- **Quectel**: EC25, EG25-G

### USB Storage
- **Boot Drive**: 64GB+ USB 3.0 recommended
- **Performance**: Class 10 or better
- **Brands**: SanDisk, Kingston, Samsung tested
- **Format**: ext4 for OS, FAT32 for compatibility

## BIOS/UEFI Configuration

### Boot Settings
- **Boot Mode**: UEFI preferred, Legacy BIOS supported
- **Secure Boot**: Disable for custom OS installation
- **USB Boot**: Enable USB HDD/USB FDD boot options
- **Network Boot**: PXE available if needed

### Power Management
- **Wake-on-LAN**: Enable for remote management
- **USB Power**: Enable USB power in S3/S4 states
- **Auto Power On**: Configure for automatic startup
- **Watchdog**: Hardware watchdog timer available

### Performance Settings
- **CPU States**: C-states can be disabled for consistent performance
- **Memory Settings**: Leave at default (1600 MHz)
- **Graphics**: Reduce graphics memory allocation (128MB minimum)

## Upgrade Recommendations

### Memory Upgrade
- **Part**: 4GB DDR3L-1600 SO-DIMM
- **Brands**: Crucial, Kingston, G.Skill
- **Speed**: PC3L-12800 (1600 MHz)
- **Voltage**: 1.35V low voltage

### Installation Process
1. Power off and unplug device
2. Remove bottom panel (4 screws)
3. Remove existing 2GB module
4. Install 4GB module in same slot
5. Reassemble and test

### Benefits of 4GB RAM
- Better performance with multiple services
- More buffer space for network routing
- Improved system responsiveness
- Support for additional Docker containers

## Cooling and Maintenance

### Passive Cooling System
- **Heat Sink**: Large aluminum heat sink on CPU
- **Thermal Interface**: Thermal pad (replaceable)
- **Airflow**: Natural convection cooling
- **Orientation**: Vertical recommended

### Maintenance Schedule
- **Dust Cleaning**: Every 6 months
- **Thermal Check**: Annual thermal pad inspection
- **Fan Cleaning**: N/A (fanless design)
- **Connector Check**: Annual port/connector cleaning

### Temperature Monitoring
```bash
# Monitor CPU temperature
sensors | grep -i temp

# Check system temperature
cat /sys/class/thermal/thermal_zone*/temp

# Monitor continuously
watch -n 1 'sensors | grep -i temp'
```

## Known Limitations

### Hardware Constraints
- **RAM**: Maximum 4GB (cannot exceed)
- **Storage**: eMMC is not upgradeable
- **Graphics**: Limited GPU acceleration
- **USB**: No USB-C ports

### Performance Considerations
- **CPU**: Single-threaded performance is modest
- **Memory**: DDR3L is slower than DDR4
- **Storage**: eMMC speed is limited (~50 MB/s)
- **Network**: CPU becomes bottleneck at high throughput

### Compatibility Issues
- **Some USB 3.0 devices**: May require USB 2.0 mode
- **High-power devices**: May exceed USB power budget
- **Bluetooth**: Not built-in, requires USB adapter
- **Audio**: Limited to analog output only

## Troubleshooting Hardware Issues

### Common Problems
1. **Boot Failures**: Check USB drive health and format
2. **USB Detection**: Try different ports, check power requirements
3. **Network Issues**: Verify cable and port configuration
4. **Overheating**: Ensure adequate ventilation

### Diagnostic Commands
```bash
# Hardware information
lshw -short
lscpu
lsmem
lsusb
lspci

# Temperature monitoring
sensors
acpi -t

# Storage health
smartctl -a /dev/sda
```

This hardware specification document provides comprehensive information for deploying the IGEL M250C as a reliable Tailscale subnet router.
