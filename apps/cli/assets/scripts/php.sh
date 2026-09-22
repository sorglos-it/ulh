#!/bin/bash

# php - PHP programming language
# Install, update, uninstall, and configure PHP on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install PHP
install_php() {
    log_info "Installing PHP..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL php php-cli || log_error "Failed"
    
    log_info "PHP installed!"
}

# Update PHP
update_php() {
    log_info "Updating PHP..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL php php-cli || log_error "Failed"
    
    log_info "PHP updated!"
}

# Uninstall PHP
uninstall_php() {
    log_info "Uninstalling PHP..."
    detect_os
    
    $PKG_UNINSTALL php php-cli || log_error "Failed"
    
    log_info "PHP uninstalled!"
}

# Configure PHP
configure_php() {
    log_info "PHP configured"
    log_info "See docs for configuration"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_php
        ;;
    update)
        update_php
        ;;
    uninstall)
        uninstall_php
        ;;
    config)
        configure_php
        ;;
    *)
        print_usage php && exit 1
esac
