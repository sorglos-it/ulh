#!/bin/bash

# jq - JSON query processor
# Install, update, uninstall, and configure jq on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install jq
install_jq() {
    log_info "Installing jq..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL jq || log_error "Failed"
    
    log_info "jq installed!"
    jq --version
}

# Update jq
update_jq() {
    log_info "Updating jq..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL jq || log_error "Failed"
    
    log_info "jq updated!"
    jq --version
}

# Uninstall jq
uninstall_jq() {
    log_info "Uninstalling jq..."
    detect_os
    
    $PKG_UNINSTALL jq || log_error "Failed"
    
    log_info "jq uninstalled!"
}

# Configure jq
configure_jq() {
    log_info "jq - JSON query processor"
    log_info "Usage: jq '.field' file.json"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_jq
        ;;
    update)
        update_jq
        ;;
    uninstall)
        uninstall_jq
        ;;
    config)
        configure_jq
        ;;
    *)
        print_usage jq && exit 1
esac
