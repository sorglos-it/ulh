#!/bin/bash

# wireguard - VPN tunnel management
# Install, update, uninstall, and configure WireGuard VPN on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install WireGuard
install_wireguard() {
    log_info "Installing wireguard..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL $PKG || log_error "Failed"
    
    log_info "wireguard installed!"
}

# Update WireGuard
update_wireguard() {
    log_info "Updating wireguard..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL $PKG || log_error "Failed"
    
    log_info "wireguard updated!"
}

# Uninstall WireGuard
uninstall_wireguard() {
    log_info "Uninstalling wireguard..."
    detect_os
    
    $PKG_UNINSTALL $PKG || log_error "Failed"
    
    log_info "wireguard uninstalled!"
}

# Configure WireGuard
configure_wireguard() {
    log_info "wireguard configuration"
    log_info "Generate keys: wg genkey | tee privatekey | wg pubkey > publickey"
    log_info "Create /etc/wireguard/wg0.conf and bring up: wg-quick up wg0"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_wireguard
        ;;
    update)
        update_wireguard
        ;;
    uninstall)
        uninstall_wireguard
        ;;
    config)
        configure_wireguard
        ;;
    *)
        print_usage wireguard && exit 1
esac
