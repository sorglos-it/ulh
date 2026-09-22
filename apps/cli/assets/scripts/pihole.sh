#!/bin/bash

# pihole - DNS ad-blocking and network filtering
# Install, update, uninstall, and configure Pi-hole for all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_pihole() {
    log_info "Installing Pi-hole DNS ad-blocker..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "Pi-hole installation requires root privileges"
    fi
    
    detect_os
    
    # Update package manager
    log_info "Updating package manager..."
    $PKG_UPDATE || true
    
    # Install prerequisites
    log_info "Installing Pi-hole prerequisites..."
    $PKG_INSTALL curl wget || log_error "Failed to install prerequisites"
    
    # Download and run the official Pi-hole installer
    log_info "Downloading Pi-hole installer from official source..."
    curl -sSL https://install.pi-hole.net -o /tmp/pihole_installer.sh || log_error "Failed to download Pi-hole installer"
    
    # Run the installer
    log_info "Running Pi-hole installer (this may take a few minutes)..."
    bash /tmp/pihole_installer.sh --unattended || log_error "Pi-hole installation failed"
    
    # Clean up installer
    rm -f /tmp/pihole_installer.sh
    
    # Enable and start Pi-hole services
    log_info "Enabling Pi-hole services..."
    systemctl enable pihole-FTL || true
    systemctl enable dnsmasq || true
    systemctl enable lighttpd || true
    
    systemctl restart pihole-FTL || true
    systemctl restart dnsmasq || true
    systemctl restart lighttpd || true
    
    # Display completion message
    log_info "Pi-hole installation complete!"
    echo ""
    log_info "Pi-hole Admin Interface:"
    echo "  URL: http://localhost/admin/"
    echo "  or: http://$(hostname -I | awk '{print $1}')/admin/"
    echo ""
    log_warn "Default login credentials:"
    echo "  To retrieve your admin password, run:"
    echo "  pihole -a -p"
    echo ""
    log_info "Pi-hole is now running and blocking ads network-wide!"
}

update_pihole() {
    log_info "Updating Pi-hole to latest version..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "Pi-hole update requires root privileges"
    fi
    
    # Check if Pi-hole is installed
    if ! command -v pihole &> /dev/null; then
        log_error "Pi-hole is not installed. Please install it first with: pihole.sh install"
    fi
    
    # Run pihole gravity update (updates Pi-hole and gravity)
    log_info "Checking for updates and updating gravity database..."
    pihole -up || log_error "Failed to update Pi-hole"
    
    # Restart services
    log_info "Restarting Pi-hole services..."
    systemctl restart pihole-FTL || true
    systemctl restart dnsmasq || true
    systemctl restart lighttpd || true
    
    log_info "Pi-hole updated successfully!"
}

uninstall_pihole() {
    log_info "Uninstalling Pi-hole..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "Pi-hole uninstallation requires root privileges"
    fi
    
    # Check if Pi-hole is installed
    if ! command -v pihole &> /dev/null; then
        log_warn "Pi-hole does not appear to be installed"
        return
    fi
    
    # Confirmation (from CONFIRM parameter)
    CONFIRM="${CONFIRM:-no}"
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Uninstallation cancelled"
        return
    fi
    
    # Keep config (from KEEP_CONFIG parameter, default "yes")
    KEEP_CONFIG="${KEEP_CONFIG:-yes}"
    
    if [[ "$KEEP_CONFIG" == "yes" ]]; then
        log_info "Keeping Pi-hole configuration and data files..."
        pihole uninstall --keep-config || log_error "Failed to uninstall Pi-hole"
    else
        log_info "Removing all Pi-hole configuration and data..."
        pihole uninstall || log_error "Failed to uninstall Pi-hole"
    fi
    
    # Disable and stop services
    log_info "Stopping and disabling Pi-hole services..."
    systemctl disable pihole-FTL || true
    systemctl disable dnsmasq || true
    systemctl disable lighttpd || true
    
    systemctl stop pihole-FTL || true
    systemctl stop dnsmasq || true
    systemctl stop lighttpd || true
    
    log_info "Pi-hole uninstalled successfully!"
}

configure_pihole() {
    log_info "Pi-hole configuration information"
    echo ""
    
    # Check if Pi-hole is installed
    if ! command -v pihole &> /dev/null; then
        log_error "Pi-hole is not installed"
    fi
    
    # Get local IP address
    local_ip=$(hostname -I | awk '{print $1}')
    
    log_info "Admin Interface Access:"
    echo "  URL: http://$local_ip/admin/"
    echo "  or: http://localhost/admin/"
    echo ""
    
    # Check if services are running
    if systemctl is-active --quiet pihole-FTL; then
        log_info "Pi-hole status: RUNNING"
    else
        log_warn "Pi-hole status: NOT RUNNING"
        echo "  To start: sudo systemctl start pihole-FTL"
    fi
    
    echo ""
    log_info "DNS Configuration:"
    echo "  Set your device's DNS server to: $local_ip"
    echo "  or use your router to point all devices to this server"
    echo ""
    
    log_info "Common Administrative Tasks:"
    echo "  Gravity sync:       pihole -g"
    echo "  Update password:    pihole -a -p"
    echo "  Query DNS:          pihole -q <domain>"
    echo "  View logs:          pihole -t"
    echo "  Flush logs:         pihole -f"
    echo ""
    
    # Show Pi-hole version if available
    if pihole -v &> /dev/null; then
        log_info "Version Information:"
        pihole -v | grep -E "^  (Core|FTL|Web)" || true
    fi
}

case "$ACTION" in
    install)
        install_pihole
        ;;
    update)
        update_pihole
        ;;
    uninstall)
        uninstall_pihole
        ;;
    config)
        configure_pihole
        ;;
    *)
        print_usage pihole && exit 1
esac
