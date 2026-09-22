#!/bin/bash

# logrotate - Log file rotation and compression
# Install, update, uninstall, and configure logrotate on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install logrotate
install_logrotate() {
    log_info "Installing logrotate..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL logrotate || log_error "Failed"
    
    log_info "logrotate installed!"
}

# Update logrotate
update_logrotate() {
    log_info "Updating logrotate..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL logrotate || log_error "Failed"
    
    log_info "logrotate updated!"
}

# Uninstall logrotate
uninstall_logrotate() {
    log_info "Uninstalling logrotate..."
    detect_os
    
    $PKG_UNINSTALL logrotate || log_error "Failed"
    
    log_info "logrotate uninstalled!"
}

# Configure logrotate
configure_logrotate() {
    log_info "logrotate configuration"
    log_info "Edit /etc/logrotate.conf or /etc/logrotate.d/"
    log_info "Logrotate runs daily via cron"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_logrotate
        ;;
    update)
        update_logrotate
        ;;
    uninstall)
        uninstall_logrotate
        ;;
    config)
        configure_logrotate
        ;;
    *)
        print_usage logrotate && exit 1
esac
