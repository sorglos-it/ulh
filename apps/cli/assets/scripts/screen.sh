#!/bin/bash

# screen - Terminal multiplexer alternative
# Install, update, uninstall, and configure screen on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install screen
install_screen() {
    log_info "Installing screen..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL screen || log_error "Failed"
    
    log_info "screen installed!"
    screen -v
}

# Update screen
update_screen() {
    log_info "Updating screen..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL screen || log_error "Failed"
    
    log_info "screen updated!"
    screen -v
}

# Uninstall screen
uninstall_screen() {
    log_info "Uninstalling screen..."
    detect_os
    
    $PKG_UNINSTALL screen || log_error "Failed"
    
    log_info "screen uninstalled!"
}

# Configure screen
configure_screen() {
    log_info "screen configuration"
    log_info "Edit ~/.screenrc"
    
    # Check if screen config file exists
    if [[ -f ~/.screenrc ]]; then
        log_info "Found ~/.screenrc"
    else
        log_info "Create ~/.screenrc for customization"
    fi
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_screen
        ;;
    update)
        update_screen
        ;;
    uninstall)
        uninstall_screen
        ;;
    config)
        configure_screen
        ;;
    *)
        print_usage screen && exit 1
esac
