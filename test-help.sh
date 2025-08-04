#!/bin/bash
# Simple test to show the help output

# Source just the help function from install.sh
show_help() {
    cat << EOF
IGEL M250C Tailscale Router Setup

This script sets up an IGEL M250C thin client as a headless Tailscale subnet router
and exit node running Debian 12 from a USB drive. Only Tailscale is required - all
other features are optional.

USAGE:
    sudo ./install.sh [OPTIONS]

OPTIONS:
    -h, --help                 Show this help message
    --non-interactive          Run in non-interactive mode (requires environment variables)
    --tailscale-key=KEY        Tailscale auth key (starts with tskey-auth-)
    --hostname=NAME            Device hostname (default: igel-m250c-router)
    --routes=ROUTES            Comma-separated CIDR routes to advertise
    
    Optional Feature Controls:
    --no-casaos                Skip CasaOS installation (Docker web UI)
    --no-cockpit               Skip Cockpit installation (system management)
    --no-emmc                  Skip eMMC storage configuration
    --no-security              Skip security hardening
    --no-monitoring            Skip system monitoring service
    --no-maintenance           Skip maintenance scripts and automation
    --no-optimization          Skip system optimizations
    
    Preset Configurations:
    --minimal                  Minimal install (Tailscale only)
    --full                     Full install (all features enabled)

EXAMPLES:
    # Interactive installation (recommended):
    sudo ./install.sh

    # Minimal installation (Tailscale only):
    sudo ./install.sh --minimal

    # Full installation (all features):
    sudo ./install.sh --full

    # Custom installation with specific features:
    sudo ./install.sh --no-casaos --no-cockpit --hostname=my-router

    # Non-interactive with custom configuration:
    sudo ./install.sh --non-interactive --minimal \\
        --tailscale-key=tskey-auth-your-key-here \\
        --hostname=office-router \\
        --routes=192.168.1.0/24,10.0.0.0/8

ENVIRONMENT VARIABLES:
    You can also set configuration via environment variables:
    
    TAILSCALE_AUTH_KEY           Your Tailscale auth key
    DEVICE_HOSTNAME              Device hostname  
    ADVERTISED_ROUTES            Comma-separated routes
    INSTALL_CASAOS               true/false (install CasaOS)
    INSTALL_COCKPIT              true/false (install Cockpit)
    USE_EMMC                     true/false (use eMMC storage)
    ENABLE_SECURITY_HARDENING    true/false (security hardening)
    ENABLE_MONITORING            true/false (system monitoring)
    ENABLE_MAINTENANCE_SCRIPTS   true/false (maintenance automation)
    ENABLE_SYSTEM_OPTIMIZATION   true/false (system optimizations)
    INTERACTIVE_MODE             true/false (enable interactive prompts)

REQUIREMENTS:
    - IGEL M250C thin client
    - 64GB+ USB 3.0 drive with Debian 12 minimal/server
    - Internet connection
    - Tailscale account with auth key
    - Root access

For more information, see README.md or visit:
https://github.com/your-repo/igel-m250c-router

EOF
}

show_help
