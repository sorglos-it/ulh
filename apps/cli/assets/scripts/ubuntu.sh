#!/bin/bash

# ubuntu - Ubuntu system management
# Update system packages and manage Ubuntu Pro subscription

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Update system packages
update_ubuntu() {
    log_info "Updating Ubuntu..."
    detect_os
    
    apt-get update || true
    apt-get upgrade -y || log_error "Failed"
    apt-get autoremove -y || true
    
    log_info "Ubuntu updated!"
}

# Attach Ubuntu Pro subscription
attach_pro() {
    log_info "Attaching Ubuntu Pro..."

    # Verify Pro key is provided
    [[ -z "$KEY" ]] && log_error "Pro key not set"
    
    pro attach "$KEY" || log_error "Failed"
    
    log_info "Ubuntu Pro attached!"
}

# Detach Ubuntu Pro subscription
detach_pro() {
    log_info "Detaching Ubuntu Pro..."
    detect_os
    
    pro detach --assume-yes || log_error "Failed"
    
    log_info "Ubuntu Pro detached!"
}

# Route to appropriate action
case "$ACTION" in
    update)
        update_ubuntu
        ;;
    pro)
        attach_pro
        ;;
    detach)
        detach_pro
        ;;
    *)
        print_usage ubuntu && exit 1
esac
