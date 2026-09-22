#!/bin/bash

# docker - Container platform
# Install, update, uninstall, and configure Docker on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install Docker
install_docker() {
    log_info "Installing Docker..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL docker.io docker || log_error "Failed"
    systemctl enable docker
    systemctl start docker
    
    log_info "Docker installed!"
}

# Update Docker
update_docker() {
    log_info "Updating Docker..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL docker.io docker || log_error "Failed"
    systemctl restart docker
    
    log_info "Docker updated!"
}

# Uninstall Docker
uninstall_docker() {
    log_info "Uninstalling Docker..."
    detect_os
    
    systemctl stop docker || true
    systemctl disable docker || true
    $PKG_UNINSTALL docker.io docker || log_error "Failed"
    
    # Optionally delete Docker images and containers data
    [[ "$DELETE_IMAGES" == "yes" ]] && rm -rf /var/lib/docker || true
    
    log_info "Docker uninstalled!"
}

# Configure Docker settings
configure_docker() {
    log_info "Docker configured"
    
    # Show storage driver if specified
    [[ -n "$STORAGE_DRIVER" ]] && log_info "Storage: $STORAGE_DRIVER"
    
    # Show logging driver if specified
    [[ -n "$LOG_DRIVER" ]] && log_info "Logging: $LOG_DRIVER"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_docker
        ;;
    update)
        update_docker
        ;;
    uninstall)
        uninstall_docker
        ;;
    config)
        configure_docker
        ;;
    *)
        print_usage docker && exit 1
esac
