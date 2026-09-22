#!/bin/bash

# pikvm-v3 - PiKVM v3 management for Raspberry Pi 4
# Update system and manage PiKVM-specific features (OLED, VNC, ISO mounting)

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Update system packages
update_pikvm() {
    log_info "Updating PiKVM v3..."
    detect_os
    
    pacman -Syu --noconfirm || log_error "Failed"
    
    log_info "PiKVM v3 updated!"
}

# Mount ISO storage directory with write permissions
mount_iso() {
    log_info "Mounting ISO directory..."
    detect_os
    
    mount -o remount,rw /mnt/msd || log_error "Failed"
    
    log_info "ISO directory mounted (rw)!"
}

# Dismount ISO storage directory (read-only)
dismount_iso() {
    log_info "Dismounting ISO directory..."
    detect_os
    
    mount -o remount,ro /mnt/msd || log_error "Failed"
    
    log_info "ISO directory dismounted (ro)!"
}

# Enable OLED display service
enable_oled() {
    log_info "Enabling OLED..."
    detect_os
    
    systemctl enable --now pikvm-oled || log_error "Failed"
    
    log_info "OLED enabled!"
}

# Enable VNC service
enable_vnc() {
    log_info "Enabling VNC..."
    detect_os
    
    systemctl enable --now vncserver-x11-serviced || log_error "Failed"
    
    log_info "VNC enabled!"
}

# Route to appropriate action
case "$ACTION" in
    update)
        update_pikvm
        ;;
    mount-iso)
        mount_iso
        ;;
    dismount-iso)
        dismount_iso
        ;;
    oled-enable)
        enable_oled
        ;;
    vnc-enable)
        enable_vnc
        ;;
    *)
        print_usage pikvm-v3 && exit 1
esac
