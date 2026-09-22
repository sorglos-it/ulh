#!/bin/bash

# mariadb - MariaDB Database Server Management
# Install, update, uninstall, and configure MariaDB for all distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_mariadb() {
    log_info "Installing MariaDB..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL $PKG || log_error "Failed to install MariaDB"
    
    systemctl enable mariadb
    systemctl start mariadb
    
    log_info "MariaDB installed and started!"
}

update_mariadb() {
    log_info "Updating MariaDB..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL $PKG || log_error "Failed to update MariaDB"
    systemctl restart mariadb
    
    log_info "MariaDB updated!"
}

uninstall_mariadb() {
    log_warn "Uninstalling MariaDB..."
    detect_os
    
    systemctl stop mariadb || true
    systemctl disable mariadb || true
    $PKG_UNINSTALL $PKG || log_error "Failed to uninstall MariaDB"
    
    [[ "$DELETE_DATA" == "yes" ]] && rm -rf /var/lib/mysql || true
    [[ "$DELETE_CONFIG" == "yes" ]] && rm -rf /etc/mysql* || true
    
    log_info "MariaDB uninstalled!"
}

config_mariadb() {
    log_info "Configuring MariaDB..."
    detect_os
    
    [[ ! -f "$CONF_FILE" ]] && log_error "Config file not found: $CONF_FILE"
    
    [[ -n "$MAX_CONNECTIONS" ]] && sed -i "s/^max_connections.*/max_connections = $MAX_CONNECTIONS/" "$CONF_FILE"
    [[ -n "$INNODB_BUFFER" ]] && sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = $INNODB_BUFFER/" "$CONF_FILE"
    [[ -n "$BIND_ADDRESS" ]] && sed -i "s/^bind-address.*/bind-address = $BIND_ADDRESS/" "$CONF_FILE"
    
    systemctl restart mariadb
    log_info "MariaDB configured!"
}

case "$ACTION" in
    install)
        install_mariadb
        ;;
    update)
        update_mariadb
        ;;
    uninstall)
        uninstall_mariadb
        ;;
    config)
        config_mariadb
        ;;
    *)
        print_usage mariadb && exit 1
esac
