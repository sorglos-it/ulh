#!/bin/bash

# python - Python programming language
# Install, update, uninstall, and configure Python on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install Python
install_python() {
    log_info "Installing Python..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL python3 python3-pip || log_error "Failed"
    
    log_info "Python installed!"
}

# Update Python
update_python() {
    log_info "Updating Python..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL python3 python3-pip || log_error "Failed"
    
    log_info "Python updated!"
}

# Uninstall Python
uninstall_python() {
    log_info "Uninstalling Python..."
    detect_os
    
    $PKG_UNINSTALL python3 python3-pip || log_error "Failed"
    
    log_info "Python uninstalled!"
}

# Configure Python
configure_python() {
    log_info "Python configured"
    log_info "See docs for configuration"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_python
        ;;
    update)
        update_python
        ;;
    uninstall)
        uninstall_python
        ;;
    config)
        configure_python
        ;;
    *)
        print_usage python && exit 1
esac
