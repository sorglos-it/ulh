#!/bin/bash

# nodejs - Node.js JavaScript runtime and npm package manager
# Install, update, uninstall, and configure Node.js on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install Node.js
install_nodejs() {
    log_info "Installing Node.js..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL nodejs npm || log_error "Failed"
    
    log_info "Node.js installed!"
}

# Update Node.js
update_nodejs() {
    log_info "Updating Node.js..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL nodejs npm || log_error "Failed"
    
    log_info "Node.js updated!"
}

# Uninstall Node.js
uninstall_nodejs() {
    log_info "Uninstalling Node.js..."
    detect_os
    
    $PKG_UNINSTALL nodejs npm || log_error "Failed"
    
    log_info "Node.js uninstalled!"
}

# Configure Node.js
configure_nodejs() {
    log_info "Node.js configured"
    log_info "See docs for configuration"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_nodejs
        ;;
    update)
        update_nodejs
        ;;
    uninstall)
        uninstall_nodejs
        ;;
    config)
        configure_nodejs
        ;;
    *)
        print_usage nodejs && exit 1
esac
