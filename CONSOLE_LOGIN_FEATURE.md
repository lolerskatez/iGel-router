# IGEL M250C Router - Physical Console Login Screen

## Overview
The IGEL M250C router now features a dynamic login screen that displays current network information and web interface URLs when accessed via physical console (keyboard and monitor).

## ✅ **Physical Console Features**

### **Dynamic Information Display**
The login screen automatically shows:

#### **🌐 Network Information**
- **Local IP Address**: Current LAN IP for web interface access
- **Tailscale IP**: VPN IP address when connected
- **Hostname**: Device identifier on the network

#### **🔧 Web Interface URLs**
- **CasaOS**: Shows `http://IP-ADDRESS` with service status (✅/❌)
- **Cockpit**: Shows `https://IP-ADDRESS:9090` with service status (✅/❌)
- **Real-time status**: Green checkmark if running, red X if stopped

#### **📊 System Status**
- **Uptime**: How long the system has been running
- **Disk Usage**: Current storage utilization percentage
- **Memory Usage**: RAM usage (used/total)

### **Example Login Screen**
```
╔═══════════════════════════════════════════════════════════════════════╗
║                    IGEL M250C Tailscale Router                       ║
║                        Physical Console                               ║
╚═══════════════════════════════════════════════════════════════════════╝

🌐 Network Information:
   Local IP:     192.168.1.100
   Tailscale IP: 100.64.1.15
   Hostname:     igel-m250c-router

🔧 Web Interfaces:
   ✅ CasaOS:  http://192.168.1.100
   ✅ Cockpit: https://192.168.1.100:9090

👤 Available Users:
   root         - Full system administration
   app-services - Service management and monitoring

📊 System Status: up 2 days, 4 hours
💾 Disk Usage:   15%
🧠 Memory:       1.2G/3.8G

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

igel-m250c-router login:
```

## 🔄 **Automatic Updates**

### **Real-Time Network Changes**
The login screen updates automatically when:

#### **Network Events**
- **IP Address Changes**: DHCP renewals, static IP changes
- **Interface Up/Down**: Network connections established/lost
- **Tailscale Status**: VPN connection/disconnection
- **Service Status**: CasaOS/Cockpit start/stop

#### **Update Mechanisms**
1. **NetworkManager Dispatcher**: Immediate updates on network changes
2. **Systemd Service Hooks**: Updates when Tailscale service changes
3. **Periodic Timer**: Refresh every 5 minutes for status changes
4. **Boot Initialization**: Updated 30 seconds after system boot

### **Update Triggers**
- Interface up/down events
- DHCP lease changes
- Tailscale service start/stop
- CasaOS service state changes
- Cockpit service state changes
- Manual refresh commands

## 🛠️ **Manual Control**

### **Update Commands**
```bash
# Manually refresh login screen (available to both users)
update-console

# Direct update (root access)
/usr/local/bin/update-login-screen
```

### **Service Management**
```bash
# Check login screen update service
systemctl status igel-login-screen.service

# Check periodic update timer
systemctl status igel-login-screen.timer

# Manually trigger update
systemctl start igel-login-screen.service
```

## 🔧 **Technical Implementation**

### **Files Created**
- **`/usr/local/bin/update-login-screen`**: Main update script
- **`/usr/local/bin/update-console`**: User-friendly update command
- **`/etc/issue`**: Physical console login screen
- **`/etc/issue.net`**: Network login screen (simplified)

### **System Integration**
- **`igel-login-screen.service`**: Systemd service for updates
- **`igel-login-screen.timer`**: Periodic refresh timer
- **NetworkManager dispatcher**: Immediate network change detection
- **Tailscale service hooks**: VPN status change detection

### **Security Considerations**
- **Read-only information**: No sensitive data exposed
- **Limited sudo access**: app-services can run update commands safely
- **Service status only**: Shows running/stopped, not configuration details

## 📱 **Use Cases**

### **Data Center/Server Room**
- Quick identification of device IP without network tools
- Immediate access to web interfaces for configuration
- Visual confirmation of service status

### **Home Lab**
- Easy access to CasaOS for container management
- Quick Cockpit access for system administration
- Network troubleshooting information at a glance

### **Remote Locations**
- Local technician can quickly access web interfaces
- No need for network scanning or documentation lookup
- Immediate status verification of critical services

### **Troubleshooting**
- Visual confirmation of network connectivity
- Service status at login screen
- Quick access to management interfaces

## 🚀 **Benefits**

1. **Zero Configuration**: Automatically displays current information
2. **Always Current**: Updates immediately on network changes
3. **User Friendly**: Clear, visual presentation of essential information
4. **Service Aware**: Shows actual service status, not just installation
5. **Multiple Interfaces**: Adapts to show only installed services
6. **Manual Control**: Users can refresh on demand

## 🔍 **Monitoring & Logs**

### **Service Logs**
```bash
# Check login screen update logs
journalctl -u igel-login-screen.service

# Check timer execution
journalctl -u igel-login-screen.timer

# Check NetworkManager dispatcher logs
journalctl | grep "99-update-login-screen"
```

### **Status Verification**
```bash
# Verify current login screen content
cat /etc/issue

# Check update script directly
/usr/local/bin/update-login-screen

# Verify automatic updates are working
systemctl list-timers | grep igel-login-screen
```

This enhancement makes the IGEL M250C router much more user-friendly for physical access scenarios, providing immediate access to essential network information and web interface URLs without requiring additional tools or documentation.
