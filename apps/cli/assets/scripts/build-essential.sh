#!/bin/bash

# build-essential - C/C++ compiler and development tools
# Install, update, uninstall, and configure build-essential on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Package names per distribution family (sets PKG)
get_pkg_names() {
    detect_os
    case "$PKG_TYPE" in
        deb)
            PKG="build-essential"
            ;;
        rpm|zypper)
            PKG="gcc gcc-c++ make"
            ;;
        pacman)
            PKG="base-devel"
            ;;
        apk)
            PKG="build-base"
            ;;
        *)
            log_error "Unsupported distribution for build-essential: $OS_DISTRO"
            ;;
    esac
}

# Install build-essential tools
install_build_essential() {
    log_info "Installing build-essential..."
    get_pkg_names
    
    $PKG_UPDATE || true
    $PKG_INSTALL $PKG || log_error "Failed"
    
    log_info "build-essential installed!"
}

# Update build-essential tools
update_build_essential() {
    log_info "Updating build-essential..."
    get_pkg_names
    
    $PKG_UPDATE || true
    $PKG_INSTALL $PKG || log_error "Failed"
    
    log_info "build-essential updated!"
}

# Uninstall build-essential tools
uninstall_build_essential() {
    log_info "Uninstalling build-essential..."
    get_pkg_names
    
    $PKG_UNINSTALL $PKG || log_error "Failed"
    
    log_info "build-essential uninstalled!"
}

# Configure and show build-essential information
configure_build_essential() {
    log_info "build-essential includes: gcc, g++, make, gdb"
    gcc --version | head -1
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_build_essential
        ;;
    update)
        update_build_essential
        ;;
    uninstall)
        uninstall_build_essential
        ;;
    config)
        configure_build_essential
        ;;
    *)
        print_usage build-essential && exit 1
esac
