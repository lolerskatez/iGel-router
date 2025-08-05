#!/bin/bash
# IGEL Dashboard Setup and Startup Script

set -e

DASHBOARD_DIR="/opt/igel-setup/web-dashboard"
CONFIG_DIR="/etc/igel-dashboard"
DATA_DIR="/var/lib/igel-dashboard"
LOG_FILE="/var/log/igel-dashboard-setup.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

setup_dashboard() {
    log "Setting up IGEL Dashboard..."
    
    # Create directories
    mkdir -p "$CONFIG_DIR" "$DATA_DIR"
    chown app-services:app-services "$DATA_DIR"
    
    # Create Python virtual environment
    if [[ ! -d "$DASHBOARD_DIR/venv" ]]; then
        log "Creating Python virtual environment..."
        cd "$DASHBOARD_DIR"
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip
        pip install -r requirements.txt
    fi
    
    # Create default users file
    if [[ ! -f "$CONFIG_DIR/users.json" ]]; then
        log "Creating default dashboard users..."
        cat > "$CONFIG_DIR/users.json" << EOF
{
    "admin": {
        "password": "admin123",
        "role": "administrator"
    },
    "user": {
        "password": "user123", 
        "role": "user"
    }
}
EOF
        chmod 600 "$CONFIG_DIR/users.json"
        chown root:root "$CONFIG_DIR/users.json"
        
        log "Default credentials created:"
        log "  Username: admin, Password: admin123"
        log "  Username: user, Password: user123"
        log "  Please change these default passwords!"
    fi
    
    # Install systemd service
    log "Installing dashboard systemd service..."
    
    # Install TailSentry dashboard service
    if [[ -f "$DASHBOARD_DIR/tailsentry-dashboard.service" ]]; then
        cp "$DASHBOARD_DIR/tailsentry-dashboard.service" /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable tailsentry-dashboard
    fi
    
    # Install or update IGEL dashboard service (compatibility)
    if [[ -f "$DASHBOARD_DIR/igel-dashboard.service" ]]; then
        cp "$DASHBOARD_DIR/igel-dashboard.service" /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable igel-dashboard
    fi
    
    # Set up log rotation
    cat > /etc/logrotate.d/tailsentry-dashboard << EOF
/var/log/tailsentry-dashboard*.log /var/log/igel-dashboard*.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 644 app-services app-services
    postrotate
        systemctl reload igel-dashboard >/dev/null 2>&1 || true
    endscript
}
EOF
    
    # Initialize database
    log "Initializing dashboard database..."
    cd "$DASHBOARD_DIR"
    source venv/bin/activate
    python3 -c "
from app import init_database
init_database()
print('Database initialized successfully')
"
    
    log "Dashboard setup completed"
}

start_dashboard() {
    log "Starting IGEL Dashboard service..."
    systemctl start igel-dashboard
    
    if systemctl is-active --quiet igel-dashboard; then
        log "Dashboard started successfully"
        log "Access the dashboard at: http://$(hostname -I | awk '{print $1}'):8088"
    else
        log "Failed to start dashboard service"
        return 1
    fi
}

stop_dashboard() {
    log "Stopping IGEL Dashboard service..."
    systemctl stop igel-dashboard
}

restart_dashboard() {
    log "Restarting IGEL Dashboard service..."
    systemctl restart igel-dashboard
}

show_status() {
    echo "IGEL Dashboard Status:"
    echo "====================="
    systemctl status igel-dashboard --no-pager
    echo
    echo "Dashboard URL: http://$(hostname -I | awk '{print $1}'):8088"
    echo "Log file: $LOG_FILE"
    echo "Service logs: journalctl -u igel-dashboard -f"
}

update_dashboard() {
    log "Updating dashboard dependencies..."
    cd "$DASHBOARD_DIR"
    source venv/bin/activate
    pip install --upgrade -r requirements.txt
    systemctl restart igel-dashboard
    log "Dashboard updated and restarted"
}

case "${1:-setup}" in
    setup)
        setup_dashboard
        start_dashboard
        ;;
    start)
        start_dashboard
        ;;
    stop)
        stop_dashboard
        ;;
    restart)
        restart_dashboard
        ;;
    status)
        show_status
        ;;
    update)
        update_dashboard
        ;;
    *)
        echo "Usage: $0 {setup|start|stop|restart|status|update}"
        echo
        echo "Commands:"
        echo "  setup   - Initial setup and start (default)"
        echo "  start   - Start the dashboard service"
        echo "  stop    - Stop the dashboard service"
        echo "  restart - Restart the dashboard service"
        echo "  status  - Show service status"
        echo "  update  - Update dependencies and restart"
        exit 1
        ;;
esac
