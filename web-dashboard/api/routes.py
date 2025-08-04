"""
API endpoints for IGEL M250C Router Dashboard
Handles VPN management, system control, and configuration
"""

from flask import Blueprint, request, jsonify
import subprocess
import json
import logging
from datetime import datetime

# Create blueprint for API routes
api = Blueprint('api', __name__, url_prefix='/api')
logger = logging.getLogger(__name__)

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

def log_action(user, action, details, success):
    """Log configuration changes to database"""
    try:
        import sqlite3
        conn = sqlite3.connect('/var/lib/igel-dashboard/dashboard.db')
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO config_changes (user, action, details, success)
            VALUES (?, ?, ?, ?)
        ''', (user, action, details, success))
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"Failed to log action: {e}")

# Tailscale Management Endpoints

@api.route('/tailscale/toggle-exit-node', methods=['POST'])
def toggle_exit_node():
    """Toggle Tailscale exit node functionality"""
    try:
        # Get current status
        status_result = run_command("tailscale status --json")
        if not status_result['success']:
            return jsonify({
                'success': False,
                'message': 'Failed to get Tailscale status'
            }), 500
        
        status_data = json.loads(status_result['stdout'])
        current_exit_node = status_data.get('Self', {}).get('ExitNodeOption', False)
        
        # Toggle exit node
        if current_exit_node:
            # Disable exit node
            result = run_command("tailscale set --exit-node=")
            action = "disable_exit_node"
            message = "Exit node disabled"
        else:
            # Enable exit node
            result = run_command("tailscale set --advertise-exit-node")
            action = "enable_exit_node"
            message = "Exit node enabled"
        
        if result['success']:
            log_action('dashboard', action, message, True)
            return jsonify({
                'success': True,
                'message': message,
                'exit_node_enabled': not current_exit_node
            })
        else:
            log_action('dashboard', action, f"Failed: {result['stderr']}", False)
            return jsonify({
                'success': False,
                'message': f"Failed to toggle exit node: {result['stderr']}"
            }), 500
            
    except Exception as e:
        logger.error(f"Error toggling exit node: {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500

@api.route('/tailscale/routes', methods=['GET', 'POST'])
def manage_routes():
    """Get or update Tailscale subnet routes"""
    if request.method == 'GET':
        try:
            # Get current advertised routes
            result = run_command("tailscale status --json")
            if result['success']:
                status_data = json.loads(result['stdout'])
                routes = status_data.get('Self', {}).get('PrimaryRoutes', [])
                return jsonify({
                    'success': True,
                    'routes': routes
                })
            else:
                return jsonify({
                    'success': False,
                    'message': 'Failed to get routes'
                }), 500
                
        except Exception as e:
            logger.error(f"Error getting routes: {e}")
            return jsonify({
                'success': False,
                'message': 'Internal server error'
            }), 500
    
    elif request.method == 'POST':
        try:
            data = request.get_json()
            routes = data.get('routes', [])
            
            if not routes:
                return jsonify({
                    'success': False,
                    'message': 'No routes provided'
                }), 400
            
            # Validate CIDR format
            import ipaddress
            for route in routes:
                try:
                    ipaddress.ip_network(route, strict=False)
                except ValueError:
                    return jsonify({
                        'success': False,
                        'message': f'Invalid CIDR format: {route}'
                    }), 400
            
            # Update routes
            routes_str = ','.join(routes)
            result = run_command(f'tailscale set --advertise-routes="{routes_str}"')
            
            if result['success']:
                log_action('dashboard', 'update_routes', f"Routes: {routes_str}", True)
                return jsonify({
                    'success': True,
                    'message': f'Routes updated: {routes_str}',
                    'routes': routes
                })
            else:
                log_action('dashboard', 'update_routes', f"Failed: {result['stderr']}", False)
                return jsonify({
                    'success': False,
                    'message': f"Failed to update routes: {result['stderr']}"
                }), 500
                
        except Exception as e:
            logger.error(f"Error updating routes: {e}")
            return jsonify({
                'success': False,
                'message': 'Internal server error'
            }), 500

@api.route('/tailscale/key-status', methods=['GET'])
def get_key_status():
    """Get Tailscale authentication key status"""
    try:
        # Check if machine is authenticated
        status_result = run_command("tailscale status --json")
        if not status_result['success']:
            return jsonify({
                'success': False,
                'message': 'Failed to get Tailscale status'
            }), 500
        
        status_data = json.loads(status_result['stdout'])
        backend_state = status_data.get('BackendState', 'Unknown')
        
        return jsonify({
            'success': True,
            'has_key': backend_state in ['Running', 'Starting'],
            'authenticated': backend_state == 'Running',
            'backend_state': backend_state
        })
        
    except Exception as e:
        logger.error(f"Error getting key status: {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500

@api.route('/tailscale/rotate-key', methods=['POST'])
def rotate_machine_key():
    """Rotate Tailscale machine key"""
    try:
        # Log out and back in to rotate key
        logout_result = run_command("tailscale logout")
        if not logout_result['success']:
            return jsonify({
                'success': False,
                'message': f"Failed to logout: {logout_result['stderr']}"
            }), 500
        
        # Note: This will require manual re-authentication
        log_action('dashboard', 'rotate_key', 'Machine key rotated', True)
        return jsonify({
            'success': True,
            'message': 'Machine key rotated. Manual re-authentication required.'
        })
        
    except Exception as e:
        logger.error(f"Error rotating key: {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500

# Headscale Management Endpoints

@api.route('/headscale/generate-key', methods=['POST'])
def generate_preauth_key():
    """Generate a Headscale pre-authentication key"""
    try:
        data = request.get_json() or {}
        namespace = data.get('namespace', 'default')
        expiration = data.get('expiration', '1h')
        reusable = data.get('reusable', True)
        
        # Build command
        cmd_parts = ['headscale', '--user', namespace, 'preauthkeys', 'create']
        if reusable:
            cmd_parts.append('--reusable')
        cmd_parts.extend(['--expiration', expiration])
        
        result = run_command(' '.join(cmd_parts))
        
        if result['success']:
            key = result['stdout'].strip()
            log_action('dashboard', 'generate_preauth_key', f"Namespace: {namespace}", True)
            return jsonify({
                'success': True,
                'key': key,
                'namespace': namespace,
                'expiration': expiration
            })
        else:
            return jsonify({
                'success': False,
                'message': f"Failed to generate key: {result['stderr']}"
            }), 500
            
    except Exception as e:
        logger.error(f"Error generating pre-auth key: {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500

@api.route('/headscale/nodes', methods=['GET'])
def get_headscale_nodes():
    """Get list of Headscale nodes"""
    try:
        result = run_command("headscale nodes list --output json")
        if result['success']:
            nodes = json.loads(result['stdout']) if result['stdout'] else []
            return jsonify({
                'success': True,
                'nodes': nodes,
                'count': len(nodes)
            })
        else:
            return jsonify({
                'success': False,
                'message': f"Failed to get nodes: {result['stderr']}"
            }), 500
            
    except Exception as e:
        logger.error(f"Error getting Headscale nodes: {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500

@api.route('/headscale/namespaces', methods=['GET', 'POST'])
def manage_namespaces():
    """Get or create Headscale namespaces"""
    if request.method == 'GET':
        try:
            result = run_command("headscale namespaces list --output json")
            if result['success']:
                namespaces = json.loads(result['stdout']) if result['stdout'] else []
                return jsonify({
                    'success': True,
                    'namespaces': namespaces,
                    'count': len(namespaces)
                })
            else:
                return jsonify({
                    'success': False,
                    'message': f"Failed to get namespaces: {result['stderr']}"
                }), 500
                
        except Exception as e:
            logger.error(f"Error getting namespaces: {e}")
            return jsonify({
                'success': False,
                'message': 'Internal server error'
            }), 500
    
    elif request.method == 'POST':
        try:
            data = request.get_json()
            namespace = data.get('namespace')
            
            if not namespace:
                return jsonify({
                    'success': False,
                    'message': 'Namespace name required'
                }), 400
            
            result = run_command(f'headscale namespaces create "{namespace}"')
            
            if result['success']:
                log_action('dashboard', 'create_namespace', f"Namespace: {namespace}", True)
                return jsonify({
                    'success': True,
                    'message': f'Namespace "{namespace}" created',
                    'namespace': namespace
                })
            else:
                return jsonify({
                    'success': False,
                    'message': f"Failed to create namespace: {result['stderr']}"
                }), 500
                
        except Exception as e:
            logger.error(f"Error creating namespace: {e}")
            return jsonify({
                'success': False,
                'message': 'Internal server error'
            }), 500

# System Management Endpoints

@api.route('/system/restart-service', methods=['POST'])
def restart_service():
    """Restart a system service"""
    try:
        data = request.get_json()
        service = data.get('service')
        
        allowed_services = ['tailscaled', 'headscale', 'headplane', 'casaos', 'cockpit']
        
        if service not in allowed_services:
            return jsonify({
                'success': False,
                'message': f'Service not allowed. Allowed: {", ".join(allowed_services)}'
            }), 400
        
        result = run_command(f'systemctl restart {service}')
        
        if result['success']:
            log_action('dashboard', 'restart_service', f"Service: {service}", True)
            return jsonify({
                'success': True,
                'message': f'Service {service} restarted'
            })
        else:
            return jsonify({
                'success': False,
                'message': f"Failed to restart {service}: {result['stderr']}"
            }), 500
            
    except Exception as e:
        logger.error(f"Error restarting service: {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500

@api.route('/system/logs/<service>')
def get_service_logs(service):
    """Get logs for a system service"""
    try:
        allowed_services = ['tailscaled', 'headscale', 'headplane', 'casaos', 'cockpit', 'igel-monitor']
        
        if service not in allowed_services:
            return jsonify({
                'success': False,
                'message': f'Service not allowed. Allowed: {", ".join(allowed_services)}'
            }), 400
        
        lines = request.args.get('lines', '50')
        result = run_command(f'journalctl -u {service} -n {lines} --no-pager')
        
        if result['success']:
            return jsonify({
                'success': True,
                'logs': result['stdout'],
                'service': service
            })
        else:
            return jsonify({
                'success': False,
                'message': f"Failed to get logs for {service}: {result['stderr']}"
            }), 500
            
    except Exception as e:
        logger.error(f"Error getting service logs: {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500
