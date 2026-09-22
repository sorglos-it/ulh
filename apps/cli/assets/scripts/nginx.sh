#!/bin/bash

# nginx - Nginx Web Server Management
# Install, update, uninstall, and configure Nginx for all distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_nginx() {
    log_info "Installing Nginx..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL nginx || log_error "Failed to install Nginx"
    
    systemctl enable $SVC_NAME
    systemctl start $SVC_NAME
    
    log_info "Nginx installed and started!"
}

update_nginx() {
    log_info "Updating Nginx..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL nginx || log_error "Failed to update Nginx"
    systemctl restart $SVC_NAME
    
    log_info "Nginx updated!"
}

uninstall_nginx() {
    log_warn "Uninstalling Nginx..."
    detect_os
    
    systemctl stop $SVC_NAME || true
    systemctl disable $SVC_NAME || true
    $PKG_UNINSTALL nginx || log_error "Failed to uninstall Nginx"
    
    [[ "$DELETE_CONFIG" == "yes" ]] && rm -rf $CONF_DIR || true
    
    log_info "Nginx uninstalled!"
}

config_server() {
    log_info "Configuring Nginx server block..."
    detect_os
    
    [[ -z "$SERVER_NAME" ]] && log_error "SERVER_NAME not set"
    [[ -z "$ROOT_PATH" ]] && log_error "ROOT_PATH not set"
    
    log_info "Server: $SERVER_NAME"
    log_info "Root: $ROOT_PATH"
    log_info "Configure $CONF_DIR/sites-available/ manually"
    
    systemctl restart $SVC_NAME
    log_info "Configuration updated!"
}

case "$ACTION" in
    install)
        install_nginx
        ;;
    update)
        update_nginx
        ;;
    uninstall)
        uninstall_nginx
        ;;
    vhosts)
        config_server
        ;;
    *)
        print_usage nginx && exit 1
esac
