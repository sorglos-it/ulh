#!/bin/bash

# vim - Vi IMproved text editor
# Install, update, uninstall, and configure vim on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install vim text editor
install_vim() {
    log_info "Installing vim..."
    detect_os
    $PKG_UPDATE || true
    $PKG_INSTALL vim || log_error "Failed to install vim"
    log_info "vim installed successfully!"
    vim --version | head -1
}

# Update vim to the latest version
update_vim() {
    log_info "Updating vim..."
    detect_os
    $PKG_UPDATE || true
    $PKG_INSTALL vim || log_error "Failed to update vim"
    log_info "vim updated successfully!"
    vim --version | head -1
}

# Uninstall vim from the system
uninstall_vim() {
    log_info "Uninstalling vim..."
    detect_os
    $PKG_UNINSTALL vim || log_error "Failed to uninstall vim"
    log_info "vim uninstalled successfully!"
}

# Display vim configuration information and instructions
configure_vim() {
    log_info "vim configuration"
    log_info "Edit ~/.vimrc for configuration"
    [[ -f ~/.vimrc ]] && log_info "Found ~/.vimrc" || log_info "No ~/.vimrc found - create with: vim ~/.vimrc"
}

# ============================================================================
# Main Action Dispatcher
# ============================================================================
case "$ACTION" in
    install) install_vim ;;
    update) update_vim ;;
    uninstall) uninstall_vim ;;
    config) configure_vim ;;
    *)
        print_usage vim && exit 1 ;;
esac
