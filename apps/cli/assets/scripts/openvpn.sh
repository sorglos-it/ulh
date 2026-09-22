#!/bin/bash

# openvpn - Virtual Private Network
# Install, update, uninstall, and configure OpenVPN on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install OpenVPN
install_openvpn() {
    log_info "Installing openvpn..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL openvpn || log_error "Failed"
    systemctl enable openvpn
    
    log_info "openvpn installed!"
}

# Update OpenVPN
update_openvpn() {
    log_info "Updating openvpn..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL openvpn || log_error "Failed"
    
    log_info "openvpn updated!"
}

# Uninstall OpenVPN
uninstall_openvpn() {
    log_info "Uninstalling openvpn..."
    detect_os
    
    systemctl disable openvpn || true
    $PKG_UNINSTALL openvpn || log_error "Failed"
    
    log_info "openvpn uninstalled!"
}

# Configure OpenVPN
configure_openvpn() {
    log_info "openvpn configuration"
    log_info "Place .ovpn file in /etc/openvpn/"
    log_info "Start with: systemctl start openvpn@<profile-name>"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_openvpn
        ;;
    update)
        update_openvpn
        ;;
    uninstall)
        uninstall_openvpn
        ;;
    config)
        configure_openvpn
        ;;
    *)
        print_usage openvpn && exit 1
esac
