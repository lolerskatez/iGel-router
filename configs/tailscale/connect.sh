#!/bin/bash

# Tailscale Connection Script
# Helper script for connecting to Tailscale with proper subnet routing

set -euo pipefail

AUTH_KEY="${1:-}"
HOSTNAME="${2:-igel-m250c-router}"
ROUTES="${3:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"

if [[ -z "$AUTH_KEY" ]]; then
    echo "Usage: $0 <auth-key> [hostname] [routes]"
    echo "Example: $0 tskey-auth-... igel-router 192.168.1.0/24,10.0.0.0/8"
    exit 1
fi

echo "Connecting to Tailscale..."
echo "Hostname: $HOSTNAME"
echo "Routes: $ROUTES"

# Connect with subnet routing and exit node
tailscale up \
    --authkey="$AUTH_KEY" \
    --hostname="$HOSTNAME" \
    --advertise-routes="$ROUTES" \
    --advertise-exit-node \
    --accept-routes \
    --reset

echo "Tailscale connection completed"
tailscale status
