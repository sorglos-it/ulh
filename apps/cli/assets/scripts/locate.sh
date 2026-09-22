#!/bin/bash

# locate - Fast file search using indexed database
# Install, update, uninstall, and configure locate for all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Package that provides locate on this distribution (sets LOCATE_PKG)
get_pkg_names() {
    detect_os
    case "$PKG_TYPE" in
        deb|pacman)
            LOCATE_PKG="plocate"
            ;;
        rpm)
            # Fedora uses plocate, RHEL/CentOS/Rocky/Alma 8 and 9 use mlocate
            if is_os fedora; then LOCATE_PKG="plocate"; else LOCATE_PKG="mlocate"; fi
            ;;
        *)
            log_error "Unsupported distribution for locate: $OS_DISTRO"
            ;;
    esac
}

install_locate() {
    log_info "Installing locate package..."
    get_pkg_names
    
    $PKG_UPDATE || true
    $PKG_INSTALL $LOCATE_PKG || log_error "Failed to install $LOCATE_PKG"
    
    log_info "Building locate database (this may take a moment)..."
    updatedb || log_error "Failed to build locate database"
    
    log_info "locate installed and database initialized successfully!"
    locate --version 2>/dev/null || locate --help 2>/dev/null | head -2
}

update_locate() {
    log_info "Updating locate database..."
    detect_os
    
    updatedb || log_error "Failed to update locate database"
    
    log_info "locate database updated successfully!"
    
    # Show database statistics
    if [[ -f "$DB_PATH" ]]; then
        local db_size=$(du -h "$DB_PATH" 2>/dev/null | cut -f1)
        local mod_time=$(stat -c %y "$DB_PATH" 2>/dev/null | cut -d' ' -f1,2)
        log_info "Database location: $DB_PATH"
        log_info "Database size: $db_size"
        log_info "Last updated: $mod_time"
    fi
}

uninstall_locate() {
    log_info "Uninstalling locate..."
    get_pkg_names
    
    # Confirm (from CONFIRM parameter)
    CONFIRM="${CONFIRM:-no}"
    
    $PKG_UNINSTALL $LOCATE_PKG || log_error "Failed to uninstall $LOCATE_PKG"
    
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Removing database files..."
        rm -f "$DB_PATH" 2>/dev/null || true
    fi
    
    log_info "locate uninstalled successfully!"
}

configure_locate() {
    log_info "locate configuration and usage"
    detect_os
    
    printf "\n${YELLOW}Database Information:${NC}\n"
    if [[ -f "$DB_PATH" ]]; then
        local db_size=$(du -h "$DB_PATH" 2>/dev/null | cut -f1)
        local mod_time=$(stat -c %y "$DB_PATH" 2>/dev/null)
        printf "  Location: %s\n" "$DB_PATH"
        printf "  Size: %s\n" "$db_size"
        printf "  Last updated: %s\n" "$mod_time"
    else
        printf "  Database not found. Run 'locate install' to initialize.\n"
    fi
    
    printf "\n${YELLOW}Basic Usage Examples:${NC}\n"
    printf "  locate filename              - Find files by name\n"
    printf "  locate -i filename           - Case-insensitive search\n"
    printf "  locate -r 'regex.*pattern'   - Search using regex\n"
    printf "  locate -c filename           - Count matching files\n"
    printf "  locate -e filename           - Only show existing files\n"
    printf "  locate -S                    - Show database statistics\n"
    
    printf "\n${YELLOW}Manual Database Update:${NC}\n"
    printf "  updatedb                - Rebuild entire database\n"
    printf "  updatedb --prune-bind-mounts=no  - Include bind mounts\n"
    
    printf "\n${YELLOW}Configuration Files:${NC}\n"
    if [[ -d /etc/updatedb.conf.d ]]; then
        printf "  /etc/updatedb.conf.d/        - Config directory\n"
    fi
    if [[ -f /etc/updatedb.conf ]]; then
        printf "  /etc/updatedb.conf           - Main config file\n"
    fi
    
    printf "\n${YELLOW}Cron Auto-Update:${NC}\n"
    printf "  Database is automatically updated via cron\n"
    printf "  Typical schedule: daily or every few hours\n"
}

case "$ACTION" in
    install)
        install_locate
        ;;
    update)
        update_locate
        ;;
    uninstall)
        uninstall_locate
        ;;
    config)
        configure_locate
        ;;
    *)
        print_usage locate && exit 1
esac
