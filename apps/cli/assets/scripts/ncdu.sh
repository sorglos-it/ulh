#!/bin/bash

set -e

FULL_PARAMS="$1"
ACTION="${FULL_PARAMS%%,*}"
PARAMS_REST="${FULL_PARAMS#*,}"

if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && export "$key=$val"
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../classes" && pwd)/colors.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../classes" && pwd)/bootstrap.sh"

detect_os() {
    source /etc/os-release 2>/dev/null || { msg_err "Cannot detect OS"; exit 1; }
    OS_DISTRO="${ID,,}"
    
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
        arch|archarm|manjaro|endeavouros)
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
            msg_err "Unsupported distribution: $OS_DISTRO"
            exit 1
            ;;
    esac
}

install_pkg() {
    msg_info "Installing ncdu..."
    detect_os
    
    $SUDO $PKG_UPDATE || true
    $SUDO $PKG_INSTALL ncdu || { msg_err "Installation failed"; exit 1; }
    
    msg_ok "ncdu installed successfully!"
}

update_pkg() {
    msg_info "Updating ncdu..."
    detect_os
    
    $SUDO $PKG_UPDATE || true
    $SUDO $PKG_INSTALL ncdu || { msg_err "Update failed"; exit 1; }
    
    msg_ok "ncdu updated successfully!"
}

uninstall_pkg() {
    msg_info "Uninstalling ncdu..."
    detect_os
    
    $SUDO $PKG_UNINSTALL ncdu || { msg_err "Uninstallation failed"; exit 1; }
    
    msg_ok "ncdu uninstalled successfully!"
}

case "$ACTION" in
    install) install_pkg ;;
    update) update_pkg ;;
    uninstall) uninstall_pkg ;;
    *) msg_err "Unknown action: $ACTION"; exit 1 ;;
esac
