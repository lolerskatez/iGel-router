#!/usr/bin/env python3
"""
IGEL M250C Router Management Dashboard
A comprehensive web interface for managing Tailscale/Headscale routing, 
exit nodes, system monitoring, and configuration.
"""

import os
import sys
import json
import subprocess
import logging
from datetime import datetime
from flask import Flask, render_template, request, jsonify, redirect, url_for, flash
from flask_httpauth import HTTPBasicAuth
import psutil
import sqlite3
from pathlib import Path

# Import API routes
from api.routes import api

# Configuration
app = Flask(__name__)
app.secret_key = os.environ.get('DASHBOARD_SECRET_KEY', 'igel-m250c-default-key-change-me')
auth = HTTPBasicAuth()

# Register API blueprint
app.register_blueprint(api)

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/igel-dashboard.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Constants
DATABASE_PATH = '/var/lib/igel-dashboard/dashboard.db'
CONFIG_PATH = '/etc/igel-dashboard'
TAILSCALE_CONFIG_PATH = '/var/lib/tailscale'

# User authentication (simple file-based for security)
USERS_FILE = '/etc/igel-dashboard/users.json'

@auth.verify_password
def verify_password(username, password):
    """Verify user credentials"""
    try:
        if os.path.exists(USERS_FILE):
            with open(USERS_FILE, 'r') as f:
                users = json.load(f)
                if username in users:
                    # In production, use proper password hashing
                    return users[username]['password'] == password
    except Exception as e:
        logger.error(f"Authentication error: {e}")
    return False

def init_database():
    """Initialize SQLite database for dashboard data"""
    os.makedirs(os.path.dirname(DATABASE_PATH), exist_ok=True)
    
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()
    
    # System status history
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS system_status (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            cpu_usage REAL,
            memory_usage REAL,
            disk_usage REAL,
            temperature REAL,
            network_bytes_sent INTEGER,
            network_bytes_recv INTEGER
        )
    ''')
    
    # Tailscale status history
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tailscale_status (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            status TEXT,
            self_ip TEXT,
            exit_node_enabled BOOLEAN,
            subnet_routes TEXT,
            connected_peers INTEGER
        )
    ''')
    
    # Configuration changes log
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS config_changes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            user TEXT,
            action TEXT,
            details TEXT,
            success BOOLEAN
        )
    ''')
    
    conn.commit()
    conn.close()

def run_command(command, timeout=30):
    """Safely run system commands with timeout"""
    try:
        result = subprocess.run(
            command, 
            shell=True, 
            capture_output=True, 
            text=True, 
            timeout=timeout
        )
        return {
            'success': result.returncode == 0,
            'stdout': result.stdout.strip(),
            'stderr': result.stderr.strip(),
            'returncode': result.returncode
        }
    except subprocess.TimeoutExpired:
        return {
            'success': False,
            'stdout': '',
            'stderr': 'Command timed out',
            'returncode': -1
        }
    except Exception as e:
        return {
            'success': False,
            'stdout': '',
            'stderr': str(e),
            'returncode': -1
        }

def get_system_info():
    """Get current system information"""
    try:
        # CPU and memory info
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        # Network statistics
        net_io = psutil.net_io_counters()
        
        # System uptime
        boot_time = datetime.fromtimestamp(psutil.boot_time())
        uptime = datetime.now() - boot_time
        
        # Temperature (if available)
        temperature = None
        try:
            temp_result = run_command("cat /sys/class/thermal/thermal_zone0/temp")
            if temp_result['success']:
                temperature = int(temp_result['stdout']) / 1000.0
        except:
            pass
        
        return {
            'cpu_percent': cpu_percent,
            'memory_percent': memory.percent,
            'memory_used': memory.used,
            'memory_total': memory.total,
            'disk_percent': (disk.used / disk.total) * 100,
            'disk_used': disk.used,
            'disk_total': disk.total,
            'network_bytes_sent': net_io.bytes_sent,
            'network_bytes_recv': net_io.bytes_recv,
            'uptime': str(uptime).split('.')[0],
            'temperature': temperature
        }
    except Exception as e:
        logger.error(f"Error getting system info: {e}")
        return {}

def get_tailscale_status():
    """Get Tailscale connection status and configuration"""
    try:
        # Basic status
        status_result = run_command("tailscale status --json")
        if not status_result['success']:
            return {'connected': False, 'error': status_result['stderr']}
        
        status_data = json.loads(status_result['stdout'])
        
        # Get current routes
        routes_result = run_command("tailscale status --json")
        advertised_routes = []
        if routes_result['success']:
            try:
                routes_data = json.loads(routes_result['stdout'])
                if 'Self' in routes_data and 'PrimaryRoutes' in routes_data['Self']:
                    advertised_routes = routes_data['Self']['PrimaryRoutes']
            except:
                pass
        
        # Check exit node status
        exit_node_result = run_command("tailscale status --json")
        exit_node_enabled = False
        if exit_node_result['success']:
            try:
                exit_data = json.loads(exit_node_result['stdout'])
                exit_node_enabled = exit_data.get('Self', {}).get('ExitNodeOption', False)
            except:
                pass
        
        # Get peer count
        peer_count = len(status_data.get('Peer', {}))
        
        return {
            'connected': True,
            'self_ip': status_data.get('Self', {}).get('TailscaleIPs', ['Unknown'])[0],
            'hostname': status_data.get('Self', {}).get('HostName', 'Unknown'),
            'exit_node_enabled': exit_node_enabled,
            'advertised_routes': advertised_routes,
            'peer_count': peer_count,
            'peers': status_data.get('Peer', {}),
            'backend_state': status_data.get('BackendState', 'Unknown')
        }
    except Exception as e:
        logger.error(f"Error getting Tailscale status: {e}")
        return {'connected': False, 'error': str(e)}

def get_headscale_status():
    """Get Headscale server status if installed"""
    try:
        # Check if Headscale is installed and running
        service_result = run_command("systemctl is-active headscale")
        if service_result['success'] and service_result['stdout'] == 'active':
            # Get node list
            nodes_result = run_command("headscale nodes list --output json")
            nodes = []
            if nodes_result['success']:
                try:
                    nodes = json.loads(nodes_result['stdout'])
                except:
                    pass
            
            # Get namespace list
            namespaces_result = run_command("headscale namespaces list --output json")
            namespaces = []
            if namespaces_result['success']:
                try:
                    namespaces = json.loads(namespaces_result['stdout'])
                except:
                    pass
            
            return {
                'installed': True,
                'running': True,
                'nodes': nodes,
                'namespaces': namespaces,
                'node_count': len(nodes)
            }
        else:
            return {
                'installed': True,
                'running': False,
                'error': service_result['stderr']
            }
    except Exception as e:
        logger.error(f"Error getting Headscale status: {e}")
        return {'installed': False, 'error': str(e)}

# Routes
@app.route('/')
@auth.login_required
def dashboard():
    """Main dashboard page"""
    system_info = get_system_info()
    tailscale_status = get_tailscale_status()
    headscale_status = get_headscale_status()
    
    return render_template('dashboard.html',
                         system_info=system_info,
                         tailscale_status=tailscale_status,
                         headscale_status=headscale_status)

@app.route('/api/system/status')
@auth.login_required
def api_system_status():
    """API endpoint for system status"""
    return jsonify(get_system_info())

@app.route('/api/tailscale/status')
@auth.login_required
def api_tailscale_status():
    """API endpoint for Tailscale status"""
    return jsonify(get_tailscale_status())

@app.route('/api/headscale/status')
@auth.login_required
def api_headscale_status():
    """API endpoint for Headscale status"""
    return jsonify(get_headscale_status())

if __name__ == '__main__':
    # Initialize database
    init_database()
    
    # Run the application
    app.run(
        host='0.0.0.0',
        port=int(os.environ.get('DASHBOARD_PORT', 8088)),
        debug=os.environ.get('FLASK_ENV') == 'development'
    )
