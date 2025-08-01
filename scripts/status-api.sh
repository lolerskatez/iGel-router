#!/bin/bash

# IGEL Status API Server
# Provides JSON API for system status monitoring

set -euo pipefail

PORT="${1:-8080}"
LOG_FILE="/var/log/igel-status-api.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Generate system status JSON
get_system_status() {
    local timestamp=$(date -Iseconds)
    local hostname=$(hostname)
    local uptime=$(uptime -p)
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    # Memory info
    local mem_total=$(free -b | grep '^Mem:' | awk '{print $2}')
    local mem_used=$(free -b | grep '^Mem:' | awk '{print $3}')
    local mem_percent=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc -l)
    
    # Disk info
    local disk_total=$(df -B1 / | tail -1 | awk '{print $2}')
    local disk_used=$(df -B1 / | tail -1 | awk '{print $3}')
    local disk_percent=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    
    # Network info
    local ip_address=$(hostname -I | awk '{print $1}')
    local tailscale_ip=$(tailscale ip 2>/dev/null || echo "unknown")
    local tailscale_status=$(tailscale status >/dev/null 2>&1 && echo "connected" || echo "disconnected")
    
    # Service status
    local services_status=""
    local services=("tailscaled" "casaos" "cockpit.socket" "igel-monitor" "NetworkManager" "sshd")
    
    for service in "${services[@]}"; do
        local status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        services_status="$services_status\"$service\": \"$status\","
    done
    services_status=${services_status%,}  # Remove trailing comma
    
    # Generate JSON
    cat << EOF
{
    "timestamp": "$timestamp",
    "hostname": "$hostname",
    "system": {
        "uptime": "$uptime",
        "load_average": "$load",
        "memory": {
            "total_bytes": $mem_total,
            "used_bytes": $mem_used,
            "percent_used": $mem_percent
        },
        "disk": {
            "total_bytes": $disk_total,
            "used_bytes": $disk_used,
            "percent_used": $disk_percent
        }
    },
    "network": {
        "local_ip": "$ip_address",
        "tailscale_ip": "$tailscale_ip",
        "tailscale_status": "$tailscale_status"
    },
    "services": {
        $services_status
    }
}
EOF
}

# Simple HTTP server response
send_response() {
    local status_code="$1"
    local content_type="$2"
    local body="$3"
    
    cat << EOF
HTTP/1.1 $status_code
Content-Type: $content_type
Content-Length: $(echo -n "$body" | wc -c)
Connection: close

$body
EOF
}

# Handle HTTP request
handle_request() {
    local request_line
    read -r request_line
    
    local method=$(echo "$request_line" | awk '{print $1}')
    local path=$(echo "$request_line" | awk '{print $2}')
    
    log "Request: $method $path"
    
    # Skip headers
    while read -r line && [[ "$line" != $'\r' ]]; do
        :
    done
    
    case "$path" in
        "/status" | "/")
            local status_json
            status_json=$(get_system_status)
            send_response "200 OK" "application/json" "$status_json"
            ;;
        "/health")
            # Simple health check
            send_response "200 OK" "application/json" '{"status": "healthy", "timestamp": "'$(date -Iseconds)'"}'
            ;;
        *)
            send_response "404 Not Found" "application/json" '{"error": "Not found", "path": "'$path'"}'
            ;;
    esac
}

# Start simple HTTP server
start_server() {
    log "Starting IGEL Status API server on port $PORT"
    
    # Check if port is available
    if ss -tuln | grep -q ":$PORT "; then
        log "ERROR: Port $PORT is already in use"
        exit 1
    fi
    
    # Start server using netcat
    while true; do
        log "Listening on port $PORT..."
        {
            handle_request
        } | nc -l -p "$PORT" -q 1
        
        # Small delay to prevent tight loop
        sleep 0.1
    done
}

# Install as systemd service
install_service() {
    log "Installing IGEL Status API as systemd service..."
    
    # Copy script to system location
    cp "$0" /usr/local/bin/igel-status-api
    chmod +x /usr/local/bin/igel-status-api
    
    # Create systemd service
    cat > /etc/systemd/system/igel-status-api.service << EOF
[Unit]
Description=IGEL M250C Status API Server
After=network.target tailscaled.service

[Service]
Type=simple
ExecStart=/usr/local/bin/igel-status-api $PORT
Restart=always
RestartSec=10
User=root
WorkingDirectory=/tmp

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable igel-status-api.service
    systemctl start igel-status-api.service
    
    # Configure firewall
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$PORT/tcp" || true
    fi
    
    log "✅ IGEL Status API service installed and started"
    log "API available at: http://$(hostname -I | awk '{print $1}'):$PORT/status"
}

# Main function
main() {
    case "${1:-server}" in
        "server")
            start_server
            ;;
        "install")
            install_service
            ;;
        "test")
            get_system_status
            ;;
        *)
            echo "Usage: $0 {server|install|test} [port]"
            echo "  server   - Start the API server (default)"
            echo "  install  - Install as systemd service"
            echo "  test     - Test JSON output"
            echo ""
            echo "Default port: 8080"
            exit 1
            ;;
    esac
}

# Install bc for calculations if not present
if ! command -v bc >/dev/null 2>&1; then
    apt update && apt install -y bc >/dev/null 2>&1 || true
fi

main "$@"
