#!/bin/bash

# bind-utils - DNS tools and utilities
# Install, update, uninstall, and configure BIND utilities on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install BIND utilities
install_bind_utils() {
    log_info "Installing bind-utils..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL $PKG || log_error "Failed"
    
    log_info "bind-utils installed!"
}

# Update BIND utilities
update_bind_utils() {
    log_info "Updating bind-utils..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL $PKG || log_error "Failed"
    
    log_info "bind-utils updated!"
}

# Uninstall BIND utilities
uninstall_bind_utils() {
    log_info "Uninstalling bind-utils..."
    detect_os
    
    $PKG_UNINSTALL $PKG || log_error "Failed"
    
    log_info "bind-utils uninstalled!"
}

# Configure and show BIND utilities information
configure_bind_utils() {
    log_info "bind-utils includes: dig, nslookup, host"
    dig --version | head -1
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_bind_utils
        ;;
    update)
        update_bind_utils
        ;;
    uninstall)
        uninstall_bind_utils
        ;;
    config)
        configure_bind_utils
        ;;
    *)
        print_usage bind-utils && exit 1
esac
