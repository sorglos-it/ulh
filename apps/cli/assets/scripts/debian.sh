#!/bin/bash

# debian - Debian system management
# Update system packages and manage Debian distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Update system packages
update_debian() {
    log_info "Updating Debian..."
    detect_os
    
    apt-get update || true
    apt-get upgrade -y || log_error "Failed"
    apt-get autoremove -y || true
    
    log_info "Debian updated!"
}

# Perform distribution upgrade
dist_upgrade_debian() {
    log_info "Distribution upgrade..."
    detect_os
    
    apt-get update || true
    apt-get dist-upgrade -y || log_error "Failed"
    
    log_info "Debian dist-upgrade complete!"
}

# Route to appropriate action
case "$ACTION" in
    update)
        update_debian
        ;;
    dist-upgrade)
        dist_upgrade_debian
        ;;
    *)
        print_usage debian && exit 1
esac
