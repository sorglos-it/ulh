#!/bin/bash

# perl - Perl programming language
# Install, update, uninstall, and configure Perl on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install Perl
install_perl() {
    log_info "Installing Perl..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL perl perl-modules || log_error "Failed"
    
    log_info "Perl installed!"
}

# Update Perl
update_perl() {
    log_info "Updating Perl..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL perl perl-modules || log_error "Failed"
    
    log_info "Perl updated!"
}

# Uninstall Perl
uninstall_perl() {
    log_info "Uninstalling Perl..."
    detect_os
    
    $PKG_UNINSTALL perl perl-modules || log_error "Failed"
    
    log_info "Perl uninstalled!"
}

# Configure Perl
configure_perl() {
    log_info "Perl configured"
    log_info "See docs for configuration"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_perl
        ;;
    update)
        update_perl
        ;;
    uninstall)
        uninstall_perl
        ;;
    config)
        configure_perl
        ;;
    *)
        print_usage perl && exit 1
esac
