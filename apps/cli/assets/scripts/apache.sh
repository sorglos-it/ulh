#!/bin/bash

# apache - Apache Web Server Management
# Install, update, uninstall, and configure Apache for all distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_apache() {
    log_info "Installing Apache..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL apache2 httpd || log_error "Failed to install Apache"
    
    systemctl enable $SVC_NAME
    systemctl start $SVC_NAME
    
    log_info "Apache installed and started!"
}

update_apache() {
    log_info "Updating Apache..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL apache2 httpd || log_error "Failed to update Apache"
    systemctl restart $SVC_NAME
    
    log_info "Apache updated!"
}

uninstall_apache() {
    log_warn "Uninstalling Apache..."
    detect_os
    
    systemctl stop $SVC_NAME || true
    systemctl disable $SVC_NAME || true
    $PKG_UNINSTALL apache2 httpd || log_error "Failed to uninstall Apache"
    
    [[ "$DELETE_CONFIG" == "yes" ]] && rm -rf $CONF_DIR || true
    
    log_info "Apache uninstalled!"
}

config_vhosts() {
    log_info "Configuring Virtual Hosts..."
    detect_os
    
    [[ -z "$VHOST_NAME" ]] && log_error "VHOST_NAME not set"
    [[ -z "$VHOST_ROOT" ]] && log_error "VHOST_ROOT not set"
    
    log_info "Virtual Host: $VHOST_NAME"
    log_info "Root: $VHOST_ROOT"
    log_info "Configure $CONF_DIR manually"
    
    systemctl restart $SVC_NAME
    log_info "Configuration updated!"
}

case "$ACTION" in
    install)
        install_apache
        ;;
    update)
        update_apache
        ;;
    uninstall)
        uninstall_apache
        ;;
    vhosts)
        config_vhosts
        ;;
    *)
        print_usage apache && exit 1
esac
