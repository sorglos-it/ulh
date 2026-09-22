#!/bin/bash

# wget - HTTP/FTP download utility
# Install, update, uninstall, and configure wget for all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_wget() {
    log_info "Installing wget..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL wget || log_error "Failed to install wget"
    
    log_info "wget installed successfully!"
    wget --version | head -1
}

update_wget() {
    log_info "Updating wget..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL wget || log_error "Failed to update wget"
    
    log_info "wget updated successfully!"
    wget --version | head -1
}

uninstall_wget() {
    log_info "Uninstalling wget..."
    detect_os
    
    $PKG_UNINSTALL wget || log_error "Failed to uninstall wget"
    
    log_info "wget uninstalled successfully!"
}

configure_wget() {
    log_info "wget configuration"
    log_info "No configuration available for wget"
    log_info "Use: wget [OPTIONS] <URL>"
    wget --help | head -20
}

case "$ACTION" in
    install)
        install_wget
        ;;
    update)
        update_wget
        ;;
    uninstall)
        uninstall_wget
        ;;
    config)
        configure_wget
        ;;
    *)
        print_usage wget && exit 1
esac
