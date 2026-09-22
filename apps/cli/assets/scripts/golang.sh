#!/bin/bash

# golang - Go programming language
# Install, update, uninstall, and configure Go on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install Go
install_golang() {
    log_info "Installing Go..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL golang-go || log_error "Failed"
    
    log_info "Go installed!"
}

# Update Go
update_golang() {
    log_info "Updating Go..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL golang-go || log_error "Failed"
    
    log_info "Go updated!"
}

# Uninstall Go
uninstall_golang() {
    log_info "Uninstalling Go..."
    detect_os
    
    $PKG_UNINSTALL golang-go || log_error "Failed"
    
    log_info "Go uninstalled!"
}

# Configure Go
configure_golang() {
    log_info "Go configured"
    log_info "See docs for configuration"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_golang
        ;;
    update)
        update_golang
        ;;
    uninstall)
        uninstall_golang
        ;;
    config)
        configure_golang
        ;;
    *)
        print_usage golang && exit 1
esac
