import subprocess
import json
import os
from flask import Blueprint, request, jsonify, current_app

wifi_api = Blueprint('wifi_api', __name__)

# Path to the WiFi manager script
WIFI_MANAGER = '/usr/local/bin/wifi-manager.sh'

@wifi_api.route('/scan', methods=['GET'])
def scan_wifi_networks():
    """Scan for available WiFi networks"""
    interface = request.args.get('interface', 'wlan0')
    
    try:
        # Run the WiFi scan command
        result = subprocess.run(
            [WIFI_MANAGER, 'scan', interface],
            capture_output=True, text=True, check=True
        )
        
        # Parse output into structured data
        networks = []
        for line in result.stdout.splitlines():
            if line and ':' in line:
                parts = line.split(':')
                if len(parts) >= 3:
                    ssid, signal, security = parts[0], parts[1], parts[2]
                    networks.append({
                        'ssid': ssid,
                        'signal': int(signal),
                        'security': security
                    })
        
        return jsonify({
            'success': True,
            'networks': sorted(networks, key=lambda x: x['signal'], reverse=True)
        })
    except subprocess.CalledProcessError as e:
        return jsonify({
            'success': False,
            'error': f"Failed to scan WiFi networks: {e.stderr}"
        }), 500

@wifi_api.route('/connect', methods=['POST'])
def connect_to_wifi():
    """Connect to a WiFi network"""
    data = request.json
    
    if not data or not all(k in data for k in ['interface', 'ssid', 'password']):
        return jsonify({
            'success': False,
            'error': 'Missing required parameters'
        }), 400
    
    interface = data['interface']
    ssid = data['ssid']
    password = data['password']
    hidden = data.get('hidden', 'no')
    
    try:
        result = subprocess.run(
            [WIFI_MANAGER, 'connect', interface, ssid, password, hidden],
            capture_output=True, text=True, check=True
        )
        
        return jsonify({
            'success': True,
            'message': f"Connected to {ssid}",
            'details': result.stdout
        })
    except subprocess.CalledProcessError as e:
        return jsonify({
            'success': False,
            'error': f"Failed to connect to WiFi: {e.stderr}"
        }), 500

@wifi_api.route('/status', methods=['GET'])
def wifi_status():
    """Get WiFi connection status"""
    interface = request.args.get('interface', 'wlan0')
    
    try:
        result = subprocess.run(
            [WIFI_MANAGER, 'status', interface],
            capture_output=True, text=True, check=True
        )
        
        # Parse the JSON output from the script
        status = json.loads(result.stdout)
        return jsonify({
            'success': True,
            'status': status
        })
    except subprocess.CalledProcessError as e:
        return jsonify({
            'success': False,
            'error': f"Failed to get WiFi status: {e.stderr}"
        }), 500
    except json.JSONDecodeError:
        return jsonify({
            'success': False,
            'error': 'Invalid status data format'
        }), 500

@wifi_api.route('/interfaces', methods=['GET'])
def list_interfaces():
    """List all network interfaces"""
    try:
        result = subprocess.run(
            [WIFI_MANAGER, 'list'],
            capture_output=True, text=True, check=True
        )
        
        # Parse the JSON output from the script
        interfaces = json.loads(result.stdout)
        return jsonify({
            'success': True,
            'interfaces': interfaces
        })
    except subprocess.CalledProcessError as e:
        return jsonify({
            'success': False,
            'error': f"Failed to list interfaces: {e.stderr}"
        }), 500
    except json.JSONDecodeError:
        return jsonify({
            'success': False,
            'error': 'Invalid interface data format'
        }), 500

@wifi_api.route('/ap/start', methods=['POST'])
def start_ap():
    """Start WiFi access point"""
    data = request.json
    
    if not data or not all(k in data for k in ['interface', 'ssid', 'password']):
        return jsonify({
            'success': False,
            'error': 'Missing required parameters'
        }), 400
    
    interface = data['interface']
    ssid = data['ssid']
    password = data['password']
    channel = data.get('channel', '6')
    
    try:
        result = subprocess.run(
            [WIFI_MANAGER, 'start-ap', interface, ssid, password, channel],
            capture_output=True, text=True, check=True
        )
        
        return jsonify({
            'success': True,
            'message': f"Started AP {ssid} on {interface}",
            'details': result.stdout
        })
    except subprocess.CalledProcessError as e:
        return jsonify({
            'success': False,
            'error': f"Failed to start AP: {e.stderr}"
        }), 500

@wifi_api.route('/ap/stop', methods=['POST'])
def stop_ap():
    """Stop WiFi access point"""
    data = request.json
    
    if not data or 'interface' not in data:
        return jsonify({
            'success': False,
            'error': 'Missing interface parameter'
        }), 400
    
    interface = data['interface']
    
    try:
        result = subprocess.run(
            [WIFI_MANAGER, 'stop-ap', interface],
            capture_output=True, text=True, check=True
        )
        
        return jsonify({
            'success': True,
            'message': f"Stopped AP on {interface}",
            'details': result.stdout
        })
    except subprocess.CalledProcessError as e:
        return jsonify({
            'success': False,
            'error': f"Failed to stop AP: {e.stderr}"
        }), 500

@wifi_api.route('/gateway', methods=['POST'])
def setup_gateway():
    """Set up WiFi gateway (coffee shop mode)"""
    data = request.json
    
    if not data or not all(k in data for k in ['interface', 'ssid', 'password']):
        return jsonify({
            'success': False,
            'error': 'Missing required parameters'
        }), 400
    
    interface = data['interface']
    ssid = data['ssid']
    password = data['password']
    
    try:
        result = subprocess.run(
            [WIFI_MANAGER, 'gateway', interface, ssid, password],
            capture_output=True, text=True, check=True
        )
        
        return jsonify({
            'success': True,
            'message': f"Set up WiFi gateway on {interface} connected to {ssid}",
            'details': result.stdout
        })
    except subprocess.CalledProcessError as e:
        return jsonify({
            'success': False,
            'error': f"Failed to set up gateway: {e.stderr}"
        }), 500

@wifi_api.route('/wan', methods=['GET'])
def detect_wan():
    """Detect the WAN/Internet interface"""
    try:
        result = subprocess.run(
            [WIFI_MANAGER, 'wan'],
            capture_output=True, text=True, check=True
        )
        
        wan_interface = result.stdout.strip()
        if wan_interface:
            return jsonify({
                'success': True,
                'interface': wan_interface
            })
        else:
            return jsonify({
                'success': False,
                'error': 'No WAN interface detected'
            }), 404
    except subprocess.CalledProcessError as e:
        return jsonify({
            'success': False,
            'error': f"Failed to detect WAN interface: {e.stderr}"
        }), 500
