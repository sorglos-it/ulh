#!/bin/bash

# rsyslog - Advanced system logging daemon
# Install, update, uninstall, and configure rsyslog on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install rsyslog
install_rsyslog() {
    log_info "Installing rsyslog..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL rsyslog || log_error "Failed"
    systemctl enable rsyslog
    systemctl start rsyslog
    
    log_info "rsyslog installed and started!"
}

# Update rsyslog
update_rsyslog() {
    log_info "Updating rsyslog..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL rsyslog || log_error "Failed"
    
    log_info "rsyslog updated!"
}

# Uninstall rsyslog
uninstall_rsyslog() {
    log_info "Uninstalling rsyslog..."
    detect_os
    
    systemctl stop rsyslog
    systemctl disable rsyslog
    $PKG_UNINSTALL rsyslog || log_error "Failed"
    
    log_info "rsyslog uninstalled!"
}

# Configure rsyslog
configure_rsyslog() {
    log_info "rsyslog configuration"
    log_info "Edit /etc/rsyslog.conf and restart: systemctl restart rsyslog"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_rsyslog
        ;;
    update)
        update_rsyslog
        ;;
    uninstall)
        uninstall_rsyslog
        ;;
    config)
        configure_rsyslog
        ;;
    *)
        print_usage rsyslog && exit 1
esac
