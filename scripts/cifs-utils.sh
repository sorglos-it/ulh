#!/bin/bash

# cifs-utils - Mount and manage SMB/CIFS network shares
# Install CIFS utilities to mount and manage SMB file shares from Windows and Samba servers

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

install_cifs() {
    log_info "Installing cifs-utils..."
    detect_os
    
    sudo $PKG_UPDATE || true
    sudo $PKG_INSTALL cifs-utils || log_error "Failed to install cifs-utils"
    
    log_info "cifs-utils installed successfully!"
    mount.cifs --version 2>/dev/null || log_info "mount.cifs is ready for use"
}

update_cifs() {
    log_info "Updating cifs-utils..."
    detect_os
    
    sudo $PKG_UPDATE || true
    sudo $PKG_INSTALL cifs-utils || log_error "Failed to update cifs-utils"
    
    log_info "cifs-utils updated successfully!"
    mount.cifs --version 2>/dev/null || log_info "mount.cifs is ready for use"
}

uninstall_cifs() {
    log_info "Uninstalling cifs-utils..."
    detect_os
    
    # Check for mounted shares
    if mount | grep -q "type cifs"; then
        printf "${YELLOW}⚠${NC} Found mounted CIFS shares. Unmount them first? (y/n): "
        read -r response
        if [[ "$response" =~ ^[Yy] ]]; then
            log_info "Unmounting CIFS shares..."
            mount | grep "type cifs" | awk '{print $3}' | while read -r mount_point; do
                sudo umount "$mount_point" || log_error "Failed to unmount $mount_point"
                log_info "Unmounted: $mount_point"
            done
        fi
    fi
    
    sudo $PKG_UNINSTALL cifs-utils || log_error "Failed to uninstall cifs-utils"
    
    log_info "cifs-utils uninstalled successfully!"
}

mount_smb() {
    log_info "SMB/CIFS Share Mounting"
    
    # Prompt for server address
    printf "${YELLOW}?${NC} Enter server address (IP or hostname) [e.g., 192.168.1.100 or fileserver.local]: "
    read -r SERVER
    if [[ -z "$SERVER" ]]; then
        log_error "Server address cannot be empty"
    fi
    
    # Prompt for share name
    printf "${YELLOW}?${NC} Enter SMB share name [e.g., shared, documents, media]: "
    read -r SHARE
    if [[ -z "$SHARE" ]]; then
        log_error "Share name cannot be empty"
    fi
    
    # Prompt for username
    printf "${YELLOW}?${NC} Enter username for authentication: "
    read -r USERNAME
    if [[ -z "$USERNAME" ]]; then
        log_error "Username cannot be empty"
    fi
    
    # Prompt for password (silent input)
    printf "${YELLOW}?${NC} Enter password for authentication: "
    read -rs PASSWORD
    echo
    if [[ -z "$PASSWORD" ]]; then
        log_error "Password cannot be empty"
    fi
    
    # Prompt for mount point with default
    MOUNT_DEFAULT="/mnt/${SERVER}/${SHARE}"
    printf "${YELLOW}?${NC} Enter mount point [default: ${MOUNT_DEFAULT}]: "
    read -r MOUNT_POINT
    MOUNT_POINT="${MOUNT_POINT:-$MOUNT_DEFAULT}"
    
    # Validate that mount point doesn't already exist
    if [[ -d "$MOUNT_POINT" ]] && mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log_error "Mount point $MOUNT_POINT is already in use"
    fi
    
    log_info "Preparing to mount: //$SERVER/$SHARE at $MOUNT_POINT"
    
    # Create mount point directory
    log_info "Creating mount point directory..."
    sudo mkdir -p "$MOUNT_POINT" || log_error "Failed to create mount point"
    
    # Create credentials directory
    log_info "Creating credentials directory..."
    sudo mkdir -p /etc/samba/ || log_error "Failed to create credentials directory"
    
    # Create credentials file
    log_info "Creating credentials file..."
    CREDS_FILE="/etc/samba/.smb_${SERVER}_${SHARE}"
    {
        echo "username=$USERNAME"
        echo "password=$PASSWORD"
    } | sudo tee "$CREDS_FILE" > /dev/null || log_error "Failed to create credentials file"
    
    # Secure credentials file
    sudo chmod 400 "$CREDS_FILE" || log_error "Failed to secure credentials file"
    
    # Backup fstab before modifying
    log_info "Backing up /etc/fstab..."
    sudo cp /etc/fstab "/etc/fstab.backup.$(date +%s)" || log_error "Failed to backup fstab"
    
    # Mount the share
    log_info "Mounting SMB share..."
    if sudo mount -t cifs -o rw,vers=3.0,credentials="$CREDS_FILE",uid=$(id -u),gid=$(id -g) "//$SERVER/$SHARE" "$MOUNT_POINT"; then
        log_info "SMB share mounted successfully!"
    else
        log_error "Failed to mount SMB share. Check credentials and server availability."
    fi
    
    # Test mount by listing contents
    log_info "Testing mount by listing contents..."
    if ls -la "$MOUNT_POINT" > /dev/null 2>&1; then
        log_info "Mount test successful!"
        ls -la "$MOUNT_POINT" | head -5
    else
        log_error "Mount test failed"
    fi
    
    # Check if entry already in fstab
    if grep -q "//.*$SHARE" /etc/fstab 2>/dev/null; then
        log_info "Mount entry already exists in fstab, skipping..."
    else
        # Add to fstab for persistent mounting
        log_info "Adding entry to /etc/fstab for persistent mounting..."
        FSTAB_ENTRY="//$SERVER/$SHARE $MOUNT_POINT cifs credentials=$CREDS_FILE,uid=$(id -u),gid=$(id -g),vers=3.0 0 0"
        echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab > /dev/null || log_error "Failed to add entry to fstab"
    fi
    
    # Display mount summary
    echo ""
    log_info "Mount Summary:"
    printf "  ${GREEN}Server:${NC} %s\n" "$SERVER"
    printf "  ${GREEN}Share:${NC} %s\n" "$SHARE"
    printf "  ${GREEN}Mount Point:${NC} %s\n" "$MOUNT_POINT"
    printf "  ${GREEN}Credentials:${NC} %s\n" "$CREDS_FILE"
    printf "  ${GREEN}Status:${NC} Active\n"
    echo ""
    
    # Show current mounts
    log_info "Current CIFS mounts:"
    mount | grep "type cifs" || log_info "No CIFS mounts found"
}

list_mounts() {
    log_info "Current CIFS Mounts:"
    if mount | grep -q "type cifs"; then
        mount | grep "type cifs"
    else
        log_info "No CIFS shares currently mounted"
    fi
}

case "$ACTION" in
    install)
        install_cifs
        ;;
    update)
        update_cifs
        ;;
    uninstall)
        uninstall_cifs
        ;;
    mountSMB)
        mount_smb
        ;;
    list)
        list_mounts
        ;;
    *)
        log_error "Unknown action: $ACTION"
        echo "Usage:"
        echo "  cifs-utils.sh install         # Install cifs-utils"
        echo "  cifs-utils.sh update          # Update cifs-utils"
        echo "  cifs-utils.sh uninstall       # Uninstall cifs-utils"
        echo "  cifs-utils.sh mountSMB        # Mount SMB/CIFS network share (interactive)"
        echo "  cifs-utils.sh list            # List mounted CIFS shares"
        exit 1
        ;;
esac
