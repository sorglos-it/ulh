#!/bin/bash

# ulh Script Template
# Copy to assets/scripts/<name>.sh and add an entry to assets/catalog.yaml
# Parameter format: action,VAR1=val1,VAR2=val2

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Action functions
install_package() {
    log_info "Installing package..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL package_name || log_error "Failed to install"
    
    log_info "Package installed!"
}

update_package() {
    log_info "Updating package..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL package_name || log_error "Failed to update"
    
    log_info "Package updated!"
}

uninstall_package() {
    log_warn "Uninstalling package..."
    detect_os
    
    $PKG_UNINSTALL package_name || log_error "Failed to uninstall"
    
    log_info "Package uninstalled!"
}

configure_package() {
    log_info "Configuring package..."
    
    # Configuration logic here
    # Access variables passed from catalog.yaml prompts:
    # - $VAR_NAME (any variable defined in catalog.yaml actions)
    
    log_info "Configuration complete!"
}

# Main switch
case "$ACTION" in
    install)
        install_package
        ;;
    update)
        update_package
        ;;
    uninstall)
        uninstall_package
        ;;
    config)
        configure_package
        ;;
    *)
        # Prints the actions and their parameters from catalog.yaml.
        # Pass the script name explicitly if the file gets renamed.
        print_usage && exit 1
        ;;
esac
