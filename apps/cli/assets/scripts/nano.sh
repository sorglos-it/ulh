#!/bin/bash

# nano - Simple text editor
# Install, update, uninstall, and configure nano on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install nano
install_nano() {
    log_info "Installing nano..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL nano || log_error "Failed"
    
    log_info "nano installed!"
    nano --version | head -1
}

# Update nano
update_nano() {
    log_info "Updating nano..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL nano || log_error "Failed"
    
    log_info "nano updated!"
    nano --version | head -1
}

# Uninstall nano
uninstall_nano() {
    log_info "Uninstalling nano..."
    detect_os
    
    $PKG_UNINSTALL nano || log_error "Failed"
    
    log_info "nano uninstalled!"
}

# Configure nano
configure_nano() {
    log_info "nano configuration"
    log_info "Edit ~/.nanorc for configuration"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_nano
        ;;
    update)
        update_nano
        ;;
    uninstall)
        uninstall_nano
        ;;
    config)
        configure_nano
        ;;
    *)
        print_usage nano && exit 1
esac
