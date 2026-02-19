#!/bin/bash

# locate - Fast file search using indexed database
# Install, update, uninstall, and configure locate for all Linux distributions

set -e

FULL_PARAMS="$1"
ACTION="${FULL_PARAMS%%,*}"
PARAMS_REST="${FULL_PARAMS#*,}"

if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && export "$key=$val"
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}✗${NC} %s\n" "$1"
    exit 1
}

# Detect OS and package manager
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_DISTRO="${ID,,}"
    else
        log_error "Cannot detect OS"
    fi
    
    case "$OS_DISTRO" in
        ubuntu|debian|raspbian|linuxmint|pop)
            PKG_UPDATE="apt-get update"
            PKG_INSTALL="apt-get install -y"
            PKG_UNINSTALL="apt-get remove -y"
            LOCATE_PKG="plocate"
            DB_PATH="/var/lib/plocate/plocate.db"
            ;;
        fedora|rhel|centos|rocky|alma)
            PKG_UPDATE="dnf check-update || true"
            PKG_INSTALL="dnf install -y"
            PKG_UNINSTALL="dnf remove -y"
            LOCATE_PKG="mlocate"
            DB_PATH="/var/lib/mlocate/mlocate.db"
            ;;
        arch|manjaro|endeavouros)
            PKG_UPDATE="pacman -Sy"
            PKG_INSTALL="pacman -S --noconfirm"
            PKG_UNINSTALL="pacman -R --noconfirm"
            LOCATE_PKG="plocate"
            DB_PATH="/var/lib/plocate/plocate.db"
            ;;
        opensuse*|sles)
            PKG_UPDATE="zypper refresh"
            PKG_INSTALL="zypper install -y"
            PKG_UNINSTALL="zypper remove -y"
            LOCATE_PKG="mlocate"
            DB_PATH="/var/lib/mlocate/mlocate.db"
            ;;
        alpine)
            PKG_UPDATE="apk update"
            PKG_INSTALL="apk add"
            PKG_UNINSTALL="apk del"
            LOCATE_PKG="mlocate"
            DB_PATH="/var/lib/mlocate/mlocate.db"
            ;;
        *)
            log_error "Unsupported distribution: $OS_DISTRO"
            ;;
    esac
}

install_locate() {
    log_info "Installing locate package..."
    detect_os
    
    sudo $PKG_UPDATE || true
    sudo $PKG_INSTALL $LOCATE_PKG || log_error "Failed to install $LOCATE_PKG"
    
    log_info "Building locate database (this may take a moment)..."
    sudo updatedb || log_error "Failed to build locate database"
    
    log_info "locate installed and database initialized successfully!"
    locate --version 2>/dev/null || locate --help 2>/dev/null | head -2
}

update_locate() {
    log_info "Updating locate database..."
    detect_os
    
    sudo updatedb || log_error "Failed to update locate database"
    
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
    detect_os
    
    read -p "Remove locate database files? (y/n) " -n 1 -r
    echo
    
    sudo $PKG_UNINSTALL $LOCATE_PKG || log_error "Failed to uninstall $LOCATE_PKG"
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Removing database files..."
        sudo rm -f "$DB_PATH" 2>/dev/null || true
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
    printf "  sudo updatedb                - Rebuild entire database\n"
    printf "  sudo updatedb --prune-bind-mounts=no  - Include bind mounts\n"
    
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
        log_error "Unknown action: $ACTION"
        echo "Usage:"
        echo "  locate.sh install"
        echo "  locate.sh update"
        echo "  locate.sh uninstall"
        echo "  locate.sh config"
        exit 1
        ;;
esac
