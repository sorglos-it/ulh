#!/bin/bash

# ruby - Ruby programming language
# Install, update, uninstall, and configure Ruby on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"


# Install Ruby
install_ruby() {
    log_info "Installing Ruby..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL ruby ruby-dev || log_error "Failed"
    
    log_info "Ruby installed!"
}

# Update Ruby
update_ruby() {
    log_info "Updating Ruby..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL ruby ruby-dev || log_error "Failed"
    
    log_info "Ruby updated!"
}

# Uninstall Ruby
uninstall_ruby() {
    log_info "Uninstalling Ruby..."
    detect_os
    
    $PKG_UNINSTALL ruby ruby-dev || log_error "Failed"
    
    log_info "Ruby uninstalled!"
}

# Configure Ruby
configure_ruby() {
    log_info "Ruby configured"
    log_info "See docs for configuration"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_ruby
        ;;
    update)
        update_ruby
        ;;
    uninstall)
        uninstall_ruby
        ;;
    config)
        configure_ruby
        ;;
    *)
        print_usage ruby && exit 1
esac
