#!/bin/bash

# syslog-ng - Advanced system logging daemon
# Install, update, uninstall, and configure syslog-ng on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install syslog-ng
install_syslog_ng() {
    log_info "Installing syslog-ng..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL syslog-ng || log_error "Failed"
    systemctl enable syslog-ng
    systemctl start syslog-ng
    
    log_info "syslog-ng installed and started!"
}

# Update syslog-ng
update_syslog_ng() {
    log_info "Updating syslog-ng..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL syslog-ng || log_error "Failed"
    
    log_info "syslog-ng updated!"
}

# Uninstall syslog-ng
uninstall_syslog_ng() {
    log_info "Uninstalling syslog-ng..."
    detect_os
    
    systemctl stop syslog-ng
    systemctl disable syslog-ng
    $PKG_UNINSTALL syslog-ng || log_error "Failed"
    
    log_info "syslog-ng uninstalled!"
}

# Configure syslog-ng
configure_syslog_ng() {
    log_info "syslog-ng configuration"
    log_info "Edit /etc/syslog-ng/syslog-ng.conf and restart: systemctl restart syslog-ng"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_syslog_ng
        ;;
    update)
        update_syslog_ng
        ;;
    uninstall)
        uninstall_syslog_ng
        ;;
    config)
        configure_syslog_ng
        ;;
    *)
        print_usage syslog-ng && exit 1
esac
