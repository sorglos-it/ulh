#!/bin/bash

# tigervnc - VNC remote desktop server
# Install, update, uninstall, and configure TigerVNC server

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
parse_parameters "$1"

install_tigervnc() {
    log_info "Installing TigerVNC..."
    detect_os

    $PKG_UPDATE || true

    case "$PKG_TYPE" in
        deb)
            # Remove conflicting old tigervncserver package first if present
            log_info "Removing old tigervncserver package if present..."
            apt-get remove -y tigervncserver 2>/dev/null || true
            
            # Now install new packages
            $PKG_INSTALL tigervnc-standalone-server tigervnc-common tigervnc-tools || log_error "Failed to install TigerVNC"
            ;;
        rpm)
            $PKG_INSTALL tigervnc-server || log_error "Failed to install TigerVNC"
            ;;
        pacman)
            $PKG_INSTALL tigervnc || log_error "Failed to install TigerVNC"
            ;;
        zypper)
            $PKG_INSTALL tigervnc || log_error "Failed to install TigerVNC"
            ;;
        apk)
            $PKG_INSTALL tigervnc || log_error "Failed to install TigerVNC"
            ;;
        *)
            log_error "Unsupported package manager"
            ;;
    esac

    log_info "TigerVNC installed successfully!"
    vncserver -version 2>&1 | head -1 || true
}

update_tigervnc() {
    log_info "Updating TigerVNC..."
    detect_os

    $PKG_UPDATE || true

    case "$PKG_TYPE" in
        deb)
            # Remove conflicting old tigervncserver package first if present
            log_info "Removing old tigervncserver package if present..."
            apt-get remove -y tigervncserver 2>/dev/null || true
            
            # Now update packages
            $PKG_INSTALL tigervnc-standalone-server tigervnc-common tigervnc-tools || log_error "Failed to update"
            ;;
        rpm)
            $PKG_INSTALL tigervnc-server || log_error "Failed to update"
            ;;
        pacman)
            $PKG_INSTALL tigervnc || log_error "Failed to update"
            ;;
        zypper)
            $PKG_INSTALL tigervnc || log_error "Failed to update"
            ;;
        apk)
            apk upgrade tigervnc || log_error "Failed to update"
            ;;
        *)
            log_error "Unsupported package manager"
            ;;
    esac

    log_info "TigerVNC updated successfully!"
}

uninstall_tigervnc() {
    log_info "Uninstalling TigerVNC..."
    detect_os

    # Stop running VNC services
    for svc in $(systemctl list-units --type=service --all 2>/dev/null | grep -oP 'vncserver@[^ ]+' || true); do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    done

    case "$PKG_TYPE" in
        deb)
            # Remove both new and old packages
            $PKG_UNINSTALL tigervnc-standalone-server tigervnc-common tigervnc-tools tigervncserver 2>/dev/null || true
            ;;
        rpm)
            $PKG_UNINSTALL tigervnc-server 2>/dev/null || true
            ;;
        pacman)
            $PKG_UNINSTALL tigervnc 2>/dev/null || true
            ;;
        zypper)
            $PKG_UNINSTALL tigervnc 2>/dev/null || true
            ;;
        apk)
            $PKG_UNINSTALL tigervnc 2>/dev/null || true
            ;;
        *)
            log_error "Unsupported package manager"
            ;;
    esac

    log_info "TigerVNC uninstalled successfully!"
    log_warn "User configs (~/.vnc/) were NOT removed. Delete manually if needed."
}

config_tigervnc() {
    log_info "Configuring TigerVNC..."

    # Parameters from execute.sh
    local DISPLAY_NUM="${VNC_DISPLAY:-1}"
    local VNC_USER_NAME="${VNC_USER:-}"
    local RESOLUTION="${VNC_GEOMETRY:-1920x1080}"
    local SESSION="${VNC_SESSION:-}"
    local VNC_PORT=$((5900 + DISPLAY_NUM))

    if [[ -z "$VNC_USER_NAME" ]]; then
        log_error "VNC user cannot be empty"
    fi

    # Setup user mapping
    local USERS_FILE="/etc/tigervnc/vncserver.users"
    mkdir -p /etc/tigervnc

    log_info "Setting display :${DISPLAY_NUM} → user ${VNC_USER_NAME}"

    # Remove old mapping for this display if exists
    if [[ -f "$USERS_FILE" ]]; then
        sed -i "/^:${DISPLAY_NUM}=/d" "$USERS_FILE"
    fi
    echo ":${DISPLAY_NUM}=${VNC_USER_NAME}" >> "$USERS_FILE"

    # Create user config directory
    local USER_HOME
    USER_HOME=$(eval echo "~${VNC_USER_NAME}")
    local CONFIG_DIR="${USER_HOME}/.config/tigervnc"
    mkdir -p "$CONFIG_DIR"

    # Write user config
    local CONFIG_FILE="${CONFIG_DIR}/config"
    log_info "Writing config to ${CONFIG_FILE}"

    cat > "$CONFIG_FILE" <<EOF
geometry=${RESOLUTION}
localhost
alwaysshared
EOF

    if [[ -n "$SESSION" ]]; then
        echo "session=${SESSION}" >> "$CONFIG_FILE"
    fi

    chown -R "${VNC_USER_NAME}:" "$CONFIG_DIR"

    # Set VNC password if not exists
    local PASSWD_FILE="${CONFIG_DIR}/passwd"
    if [[ ! -f "$PASSWD_FILE" ]]; then
        log_warn "No VNC password set. Run 'vncpasswd' as user ${VNC_USER_NAME} to set one."
    fi

    # Enable and start systemd service
    local SVC="vncserver@:${DISPLAY_NUM}.service"
    log_info "Enabling service ${SVC}..."
    systemctl enable "$SVC" 2>/dev/null || true
    systemctl restart "$SVC" 2>/dev/null || true

    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        log_info "VNC server running on port ${VNC_PORT}"
    else
        log_warn "Service not started. Set password first: su - ${VNC_USER_NAME} -c vncpasswd"
    fi

    echo ""
    echo "  Configuration:"
    echo "  ├─ User: ${VNC_USER_NAME}"
    echo "  ├─ Display: :${DISPLAY_NUM}"
    echo "  ├─ Port: ${VNC_PORT}"
    echo "  ├─ Resolution: ${RESOLUTION}"
    echo "  ├─ Session: ${SESSION:-default}"
    echo "  └─ Config: ${CONFIG_FILE}"
}

case "$ACTION" in
    install)   install_tigervnc ;;
    update)    update_tigervnc ;;
    uninstall) uninstall_tigervnc ;;
    config)    config_tigervnc ;;
    *)         print_usage tigervnc && exit 1 ;;
esac
