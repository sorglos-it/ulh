#!/bin/bash

# net-tools - Network utilities (ifconfig, netstat, arp, route)
# Install, update, uninstall, and configure net-tools on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install net-tools
install_net_tools() {
    log_info "Installing net-tools..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL net-tools || log_error "Failed"
    
    log_info "net-tools installed!"
}

# Update net-tools
update_net_tools() {
    log_info "Updating net-tools..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL net-tools || log_error "Failed"
    
    log_info "net-tools updated!"
}

# Uninstall net-tools
uninstall_net_tools() {
    log_info "Uninstalling net-tools..."
    detect_os
    
    $PKG_UNINSTALL net-tools || log_error "Failed"
    
    log_info "net-tools uninstalled!"
}

# Configure net-tools
configure_net_tools() {
    log_info "net-tools includes: ifconfig, netstat, arp, route"
    ifconfig --version 2>/dev/null || log_info "Use 'ifconfig' for network info"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_net_tools
        ;;
    update)
        update_net_tools
        ;;
    uninstall)
        uninstall_net_tools
        ;;
    config)
        configure_net_tools
        ;;
    *)
        print_usage net-tools && exit 1
esac
