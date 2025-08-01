<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# IGEL M250C Tailscale Router Project Instructions

This project sets up an IGEL M250C thin client as a headless Tailscale subnet router and exit node. When working on this project, please follow these guidelines:

## Project Context
- Target hardware: IGEL M250C thin client with limited resources
- OS: Debian 12 minimal/server running from USB drive
- Purpose: Network routing, VPN gateway, and lightweight service hosting

## Code Style Guidelines
- Use bash scripting best practices with `set -euo pipefail`
- Include comprehensive error handling and logging
- Use consistent variable naming (UPPER_CASE for constants, lower_case for locals)
- Add comments for complex operations, especially hardware-specific configurations
- Follow systemd service file conventions for service definitions

## Hardware-Specific Considerations
- Memory is limited (2-4GB), optimize for low resource usage
- USB drive wear: minimize frequent writes, use eMMC when possible
- AMD GX-415GA CPU has modest performance, avoid CPU-intensive operations
- Network throughput is limited to ~100-200 Mbps for routing

## Key Components to Remember
1. **Tailscale**: Primary VPN solution with subnet routing and exit node capabilities
2. **CasaOS**: Web UI for service management (user-friendly interface)
3. **Cockpit**: Optional advanced system management (power users)
4. **eMMC optimization**: Use 3.5GB internal storage for swap/logs to reduce USB wear
5. **USB dongle support**: NetworkManager + ModemManager for connectivity options

## Script Organization
- Main installation script should be modular with clear functions
- Configuration files should be templated and parameterizable
- Include comprehensive logging throughout installation process
- Provide clear success/failure feedback to users

## Security Best Practices
- Enable UFW firewall with minimal required ports
- Use Tailscale's built-in security features
- Implement proper service isolation
- Regular security updates through automated processes

## Error Handling
- Check for required dependencies before proceeding
- Validate hardware compatibility (detect eMMC, check memory, etc.)
- Provide clear error messages with suggested remedies
- Include rollback procedures where applicable

## Documentation Standards
- Include comprehensive README with setup instructions
- Document all configuration options and environment variables
- Provide troubleshooting guide for common issues
- Include performance expectations and hardware limitations
