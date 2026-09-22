#!/bin/bash

# htop - Interactive process viewer
# Install, update, uninstall, and configure htop on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install htop
install_htop() {
    log_info "Installing htop..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL htop || log_error "Failed"
    
    log_info "htop installed!"
    htop --version
}

# Update htop
update_htop() {
    log_info "Updating htop..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL htop || log_error "Failed"
    
    log_info "htop updated!"
    htop --version
}

# Uninstall htop
uninstall_htop() {
    log_info "Uninstalling htop..."
    detect_os
    
    $PKG_UNINSTALL htop || log_error "Failed"
    
    log_info "htop uninstalled!"
}

# Configure htop
configure_htop() {
    log_info "htop configuration"
    log_info "Edit ~/.config/htop/htoprc"
    
    # Check if htop config file exists
    if [[ -f ~/.config/htop/htoprc ]]; then
        log_info "Found htoprc"
    else
        log_info "Run 'htop' first to generate config"
    fi
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_htop
        ;;
    update)
        update_htop
        ;;
    uninstall)
        uninstall_htop
        ;;
    config)
        configure_htop
        ;;
    *)
        print_usage htop && exit 1
esac
