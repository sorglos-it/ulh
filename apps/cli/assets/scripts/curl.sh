#!/bin/bash

# curl - HTTP requests utility
# Install, update, uninstall, and configure curl for all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_curl() {
    log_info "Installing curl..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL curl || log_error "Failed to install curl"
    
    log_info "curl installed successfully!"
    curl --version | head -1
}

update_curl() {
    log_info "Updating curl..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL curl || log_error "Failed to update curl"
    
    log_info "curl updated successfully!"
    curl --version | head -1
}

uninstall_curl() {
    log_info "Uninstalling curl..."
    detect_os
    
    $PKG_UNINSTALL curl || log_error "Failed to uninstall curl"
    
    log_info "curl uninstalled successfully!"
}

configure_curl() {
    log_info "curl configuration"
    log_info "No configuration available for curl"
    log_info "Use: curl [OPTIONS] <URL>"
    curl --help | head -20
}

case "$ACTION" in
    install)
        install_curl
        ;;
    update)
        update_curl
        ;;
    uninstall)
        uninstall_curl
        ;;
    config)
        configure_curl
        ;;
    *)
        print_usage curl && exit 1
esac
