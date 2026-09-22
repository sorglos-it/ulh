#!/bin/bash

# fail2ban - Intrusion prevention system
# Install, update, uninstall, and configure fail2ban on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install fail2ban
install_fail2ban() {
    log_info "Installing fail2ban..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL fail2ban || log_error "Failed"
    systemctl enable fail2ban
    systemctl start fail2ban
    
    log_info "fail2ban installed and started!"
}

# Update fail2ban
update_fail2ban() {
    log_info "Updating fail2ban..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL fail2ban || log_error "Failed"
    
    log_info "fail2ban updated!"
}

# Uninstall fail2ban
uninstall_fail2ban() {
    log_info "Uninstalling fail2ban..."
    detect_os
    
    systemctl stop fail2ban
    systemctl disable fail2ban
    $PKG_UNINSTALL fail2ban || log_error "Failed"
    
    log_info "fail2ban uninstalled!"
}

# Configure fail2ban
configure_fail2ban() {
    log_info "fail2ban configuration"
    log_info "Copy /etc/fail2ban/jail.conf to /etc/fail2ban/jail.local and edit"
    log_info "Then: systemctl restart fail2ban"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_fail2ban
        ;;
    update)
        update_fail2ban
        ;;
    uninstall)
        uninstall_fail2ban
        ;;
    config)
        configure_fail2ban
        ;;
    *)
        print_usage fail2ban && exit 1
esac
