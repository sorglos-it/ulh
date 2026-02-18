#!/bin/bash

# adguard-home - DNS ad-blocking with advanced filtering
# Install, update, uninstall, and configure AdGuard Home for all Linux distributions

set -e

FULL_PARAMS="$1"
ACTION="${FULL_PARAMS%%,*}"
PARAMS_REST="${FULL_PARAMS#*,}"

if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && export "$key=$val"
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
log_info() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}✗${NC} %s\n" "$1"
    exit 1
}

log_warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
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
            ;;
        fedora|rhel|centos|rocky|alma)
            PKG_UPDATE="dnf check-update || true"
            PKG_INSTALL="dnf install -y"
            PKG_UNINSTALL="dnf remove -y"
            ;;
        arch|manjaro|endeavouros)
            PKG_UPDATE="pacman -Sy"
            PKG_INSTALL="pacman -S --noconfirm"
            PKG_UNINSTALL="pacman -R --noconfirm"
            ;;
        opensuse*|sles)
            PKG_UPDATE="zypper refresh"
            PKG_INSTALL="zypper install -y"
            PKG_UNINSTALL="zypper remove -y"
            ;;
        alpine)
            PKG_UPDATE="apk update"
            PKG_INSTALL="apk add"
            PKG_UNINSTALL="apk del"
            ;;
        *)
            log_error "Unsupported distribution: $OS_DISTRO"
            ;;
    esac
}

install_adguard() {
    log_info "Installing AdGuard Home..."
    detect_os
    
    # Install dependencies
    sudo $PKG_UPDATE || true
    sudo $PKG_INSTALL curl wget || true
    
    # Download and run official installer
    log_info "Downloading official AdGuard Home installer..."
    if command -v curl &> /dev/null; then
        curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v || log_error "Installation failed"
    elif command -v wget &> /dev/null; then
        wget --no-verbose -O - https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v || log_error "Installation failed"
    else
        log_error "curl or wget required for installation"
    fi
    
    log_info "AdGuard Home installed successfully!"
    log_info "Access web interface: http://localhost:3000/"
    log_info "Default username: admin"
}

update_adguard() {
    log_info "Updating AdGuard Home..."
    detect_os
    
    # Run installer script for update
    log_info "Checking for updates..."
    if command -v curl &> /dev/null; then
        curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v || log_error "Update failed"
    elif command -v wget &> /dev/null; then
        wget --no-verbose -O - https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v || log_error "Update failed"
    else
        log_error "curl or wget required for update"
    fi
    
    # Restart service
    if systemctl is-active --quiet AdGuardHome; then
        sudo systemctl restart AdGuardHome || log_error "Failed to restart AdGuard Home"
    fi
    
    log_info "AdGuard Home updated successfully!"
}

uninstall_adguard() {
    log_warn "Uninstalling AdGuard Home..."
    
    # Confirmation prompt
    read -p "Are you sure you want to uninstall AdGuard Home? (yes/no) [no]: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Uninstall cancelled"
        return 0
    fi
    
    # Stop service
    if systemctl is-active --quiet AdGuardHome; then
        sudo systemctl stop AdGuardHome || log_warn "Could not stop service"
    fi
    
    # Ask about config
    read -p "Keep AdGuard Home configuration? (yes/no) [yes]: " keep_config
    if [[ "$keep_config" != "no" ]]; then
        log_info "Configuration will be preserved"
    fi
    
    # Run official uninstall if available
    if [[ -f "/opt/AdGuardHome/AdGuardHome" ]]; then
        sudo /opt/AdGuardHome/AdGuardHome -s uninstall || log_warn "Uninstall script had issues"
    fi
    
    log_info "AdGuard Home uninstalled successfully!"
}

configure_adguard() {
    log_info "AdGuard Home configuration"
    log_info ""
    log_info "Web Interface: http://localhost:3000/"
    log_info "API: http://localhost:3000/api/"
    log_info "Default username: admin"
    log_info ""
    
    if systemctl is-active --quiet AdGuardHome; then
        log_info "Service status: RUNNING"
    else
        log_info "Service status: STOPPED"
    fi
    
    log_info ""
    log_info "To access AdGuard Home:"
    log_info "  1. Open http://localhost:3000/ in your browser"
    log_info "  2. Complete initial setup wizard"
    log_info "  3. Set as DNS server (usually on router or client)"
    log_info ""
}

case "$ACTION" in
    install)
        install_adguard
        ;;
    update)
        update_adguard
        ;;
    uninstall)
        uninstall_adguard
        ;;
    config)
        configure_adguard
        ;;
    *)
        log_error "Unknown action: $ACTION"
        echo "Usage:"
        echo "  adguard-home.sh install"
        echo "  adguard-home.sh update"
        echo "  adguard-home.sh uninstall"
        echo "  adguard-home.sh config"
        exit 1
        ;;
esac
