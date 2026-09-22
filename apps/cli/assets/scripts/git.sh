#!/bin/bash

# git - Version control system
# Install, update, uninstall, and configure git for all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"


install_git() {
    log_info "Installing git..."
    detect_os
    $PKG_UPDATE || true
    $PKG_INSTALL git || log_error "Failed to install git"
    log_info "git installed successfully!"
    git --version
}

update_git() {
    log_info "Updating git..."
    detect_os
    $PKG_UPDATE || true
    $PKG_INSTALL git || log_error "Failed to update git"
    log_info "git updated successfully!"
    git --version
}

uninstall_git() {
    log_info "Uninstalling git..."
    detect_os
    $PKG_UNINSTALL git || log_error "Failed to uninstall git"
    log_info "git uninstalled successfully!"
}

configure_git() {
    log_info "Configuring git..."
    [[ -z "$GIT_USER" ]] && log_error "GIT_USER not set"
    [[ -z "$GIT_EMAIL" ]] && log_error "GIT_EMAIL not set"
    
    git config --global user.name "$GIT_USER"
    git config --global user.email "$GIT_EMAIL"
    log_info "git configured: $GIT_USER <$GIT_EMAIL>"
    git config --global --list | grep user
}

case "$ACTION" in
    install) install_git ;;
    update) update_git ;;
    uninstall) uninstall_git ;;
    config) configure_git ;;
    *)
        print_usage git && exit 1 ;;
esac
