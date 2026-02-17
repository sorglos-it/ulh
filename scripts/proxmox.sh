#!/bin/bash

# Proxmox VE Management Script
# Manage VMs, LXC containers, and system configuration

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

log_warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}✗${NC} %s\n" "$1"
    exit 1
}

stop_all_vms_lxc() {
    log_info "Stopping all VMs and LXC containers..."
    
    log_info "Step 1: Stopping all VMs..."
    for vmid in $(qm list | awk 'NR>1 {print $1}'); do
        log_info "Stopping VM $vmid..."
        qm stop "$vmid" || log_warn "Failed to stop VM $vmid"
    done
    
    log_info "Step 2: Stopping all LXC containers..."
    for ctid in $(pct list | awk 'NR>1 {print $1}'); do
        log_info "Stopping LXC $ctid..."
        pct stop "$ctid" || log_warn "Failed to stop LXC $ctid"
    done
    
    log_info "All VMs and LXC containers stopped successfully!"
}

change_language() {
    log_info "Changing system language..."
    
    [[ -z "$LANGUAGE" ]] && log_error "LANGUAGE not set"
    
    log_info "Setting language to: $LANGUAGE..."
    
    log_info "Step 1: Reconfiguring locales..."
    sudo dpkg-reconfigure --frontend=noninteractive locales || log_warn "dpkg-reconfigure failed"
    
    log_info "Step 2: Updating /etc/default/locale..."
    echo "LANG=$LANGUAGE.UTF-8" | sudo tee /etc/default/locale >/dev/null || log_error "Failed to set LANG"
    echo "LANGUAGE=$LANGUAGE:${LANGUAGE%_*}" | sudo tee -a /etc/default/locale >/dev/null || log_error "Failed to set LANGUAGE"
    echo "LC_ALL=$LANGUAGE.UTF-8" | sudo tee -a /etc/default/locale >/dev/null || log_error "Failed to set LC_ALL"
    
    log_info "Step 3: Updating Proxmox datacenter config..."
    echo "language: ${LANGUAGE%_*}" | sudo tee -a /etc/pve/datacenter.cfg >/dev/null || log_error "Failed to update datacenter.cfg"
    
    log_info "Language changed to: $LANGUAGE"
    log_warn "Rebooting system in 5 seconds..."
    
    sleep 5
    sudo reboot || log_error "Failed to reboot"
}

install_qemu_guest_agent() {
    log_info "Installing QEMU Guest Agent..."
    
    log_info "Step 1: Updating package lists..."
    sudo apt-get update >/dev/null 2>&1 || log_error "Failed to update package lists"
    
    log_info "Step 2: Installing qemu-guest-agent..."
    sudo apt-get install -y qemu-guest-agent || log_error "Failed to install qemu-guest-agent"
    
    log_info "Step 3: Starting QEMU Guest Agent service..."
    sudo systemctl start qemu-guest-agent || log_error "Failed to start service"
    
    log_info "Step 4: Enabling QEMU Guest Agent service..."
    sudo systemctl enable qemu-guest-agent || log_error "Failed to enable service"
    
    log_info "QEMU Guest Agent installed and enabled successfully!"
}

enable_lxc_root_ssh() {
    log_info "Enabling SSH root login for LXC containers..."
    
    log_info "Configuring SSH for root access..."
    
    echo "PermitRootLogin yes" | sudo tee -a /etc/ssh/sshd_config >/dev/null || log_error "Failed to set PermitRootLogin"
    echo "PasswordAuthentication yes" | sudo tee -a /etc/ssh/sshd_config >/dev/null || log_error "Failed to set PasswordAuthentication"
    
    log_info "Restarting SSH service..."
    sudo systemctl restart sshd || log_error "Failed to restart SSH service"
    
    log_info "SSH root login enabled successfully!"
    log_warn "WARNING: This allows direct root SSH access. Consider using SSH keys instead!"
}

lxc_to_template() {
    log_info "Converting LXC container to template..."
    
    [[ -z "$CTID" ]] && log_error "CTID not set"
    
    log_info "Converting container $CTID to template..."
    
    if pct set "$CTID" -template 1; then
        log_info "Container $CTID converted to template successfully!"
    else
        log_error "Failed to convert container $CTID to template"
    fi
}

template_to_lxc() {
    log_info "Converting template to LXC container..."
    
    [[ -z "$CTID" ]] && log_error "CTID not set"
    
    log_info "Converting template $CTID to container..."
    
    if pct set "$CTID" -template 0; then
        log_info "Template $CTID converted to container successfully!"
    else
        log_error "Failed to convert template $CTID to container"
    fi
}

unlock_lxc() {
    log_info "Unlocking LXC container..."
    
    [[ -z "$CTID" ]] && log_error "CTID not set"
    
    log_info "Unlocking container $CTID..."
    
    if pct unlock "$CTID"; then
        log_info "Container $CTID unlocked successfully!"
    else
        log_error "Failed to unlock container $CTID"
    fi
}

case "$ACTION" in
    stop-all)
        stop_all_vms_lxc
        ;;
    
    language)
        change_language
        ;;
    
    qemu-guest-agent)
        install_qemu_guest_agent
        ;;
    
    lxc-ssh-root)
        enable_lxc_root_ssh
        ;;
    
    lxc-to-template)
        lxc_to_template
        ;;
    
    template-to-lxc)
        template_to_lxc
        ;;
    
    unlock-lxc)
        unlock_lxc
        ;;
    
    *)
        log_error "Unknown action: $ACTION"
        echo "Usage:"
        echo "  proxmox.sh stop-all"
        echo "  proxmox.sh language,LANGUAGE=de_DE"
        echo "  proxmox.sh qemu-guest-agent"
        echo "  proxmox.sh lxc-ssh-root"
        echo "  proxmox.sh lxc-to-template,CTID=100"
        echo "  proxmox.sh template-to-lxc,CTID=100"
        echo "  proxmox.sh unlock-lxc,CTID=100"
        exit 1
        ;;
esac
