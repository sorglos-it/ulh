#!/bin/bash

# mysql - MySQL relational database
# Install, update, uninstall, and configure MySQL for all distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_mysql() {
    log_info "Installing MySQL..."
    detect_os
    
    # Update package manager
    $PKG_UPDATE || true
    
    # Install MySQL
    $PKG_INSTALL $PKG || log_error "Failed to install MySQL"
    
    # Enable and start service
    systemctl enable $SERVICE
    systemctl start $SERVICE
    
    log_info "MySQL installed and started!"
    mysql --version || true
}

update_mysql() {
    log_info "Updating MySQL..."
    detect_os
    
    # Update package manager
    $PKG_UPDATE || true
    
    # Update MySQL
    $PKG_INSTALL $PKG || log_error "Failed to update MySQL"
    
    # Restart service
    systemctl restart $SERVICE
    
    log_info "MySQL updated!"
}

uninstall_mysql() {
    log_warn "Uninstalling MySQL..."
    detect_os
    
    # Stop and disable service
    systemctl stop $SERVICE || true
    systemctl disable $SERVICE || true
    
    # Uninstall MySQL
    $PKG_UNINSTALL $PKG || log_error "Failed to uninstall MySQL"
    
    # Remove data if requested
    [[ "$DELETE_DATA" == "yes" ]] && rm -rf /var/lib/mysql* || true
    [[ "$DELETE_CONFIG" == "yes" ]] && rm -rf /etc/mysql* || true
    
    log_info "MySQL uninstalled!"
}

config_mysql() {
    log_info "Configuring MySQL..."
    detect_os
    
    # Display connection information
    log_info "MySQL Configuration:"
    log_info "Default user: root"
    log_info "Default port: 3306"
    log_info "Socket location: /var/run/mysqld/mysqld.sock"
    
    # Ensure service is enabled and running
    systemctl enable $SERVICE
    systemctl start $SERVICE
    
    log_info "MySQL configured and running!"
}

case "$ACTION" in
    install)
        install_mysql
        ;;
    update)
        update_mysql
        ;;
    uninstall)
        uninstall_mysql
        ;;
    config)
        config_mysql
        ;;
    *)
        print_usage mysql && exit 1
esac
