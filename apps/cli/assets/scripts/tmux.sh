#!/bin/bash

# tmux - Terminal multiplexer
# Install, update, uninstall, and configure tmux on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install tmux
install_tmux() {
    log_info "Installing tmux..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL tmux || log_error "Failed"
    
    log_info "tmux installed!"
    tmux -V
}

# Update tmux
update_tmux() {
    log_info "Updating tmux..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL tmux || log_error "Failed"
    
    log_info "tmux updated!"
    tmux -V
}

# Uninstall tmux
uninstall_tmux() {
    log_info "Uninstalling tmux..."
    detect_os
    
    $PKG_UNINSTALL tmux || log_error "Failed"
    
    log_info "tmux uninstalled!"
}

# Configure tmux
configure_tmux() {
    log_info "tmux configuration"
    log_info "Edit ~/.tmux.conf"
    
    # Check if configuration file exists
    if [[ -f ~/.tmux.conf ]]; then
        log_info "Found ~/.tmux.conf"
    else
        log_info "Create ~/.tmux.conf for customization"
    fi
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_tmux
        ;;
    update)
        update_tmux
        ;;
    uninstall)
        uninstall_tmux
        ;;
    config)
        configure_tmux
        ;;
    *)
        print_usage tmux && exit 1
esac
