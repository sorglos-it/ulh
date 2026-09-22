#!/bin/bash

# postgres - PostgreSQL relational database
# Install, update, uninstall, and configure PostgreSQL for all distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_postgres() {
    log_info "Installing PostgreSQL..."
    detect_os
    
    # Update package manager
    $PKG_UPDATE || true
    
    # Install PostgreSQL
    $PKG_INSTALL $PKG || log_error "Failed to install PostgreSQL"
    
    # Enable and start service
    systemctl enable $SERVICE
    systemctl start $SERVICE
    
    log_info "PostgreSQL installed and started!"
    psql --version || true
}

update_postgres() {
    log_info "Updating PostgreSQL..."
    detect_os
    
    # Update package manager
    $PKG_UPDATE || true
    
    # Update PostgreSQL
    $PKG_INSTALL $PKG || log_error "Failed to update PostgreSQL"
    
    # Restart service
    systemctl restart $SERVICE
    
    log_info "PostgreSQL updated!"
}

uninstall_postgres() {
    log_warn "Uninstalling PostgreSQL..."
    detect_os
    
    # Stop and disable service
    systemctl stop $SERVICE || true
    systemctl disable $SERVICE || true
    
    # Uninstall PostgreSQL
    $PKG_UNINSTALL $PKG || log_error "Failed to uninstall PostgreSQL"
    
    # Remove data if requested
    [[ "$DELETE_DATA" == "yes" ]] && rm -rf /var/lib/pgsql* || true
    [[ "$DELETE_CONFIG" == "yes" ]] && rm -rf /etc/postgresql* || true
    
    log_info "PostgreSQL uninstalled!"
}

config_postgres() {
    log_info "Configuring PostgreSQL..."
    detect_os
    
    # Display connection information
    log_info "PostgreSQL Configuration:"
    log_info "Default user: postgres"
    log_info "Default port: 5432"
    log_info "Socket location: /var/run/postgresql"
    
    # Ensure service is enabled and running
    systemctl enable $SERVICE
    systemctl start $SERVICE
    
    log_info "PostgreSQL configured and running!"
}

case "$ACTION" in
    install)
        install_postgres
        ;;
    update)
        update_postgres
        ;;
    uninstall)
        uninstall_postgres
        ;;
    config)
        config_postgres
        ;;
    *)
        print_usage postgres && exit 1
esac
