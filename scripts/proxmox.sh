#!/bin/bash

# proxmox - Guest agent and container management for Proxmox hosts
# Manages qemu-guest-agent (for guests) and VM/LXC container operations

set -e

# Parse action and parameters
FULL_PARAMS="$1"
ACTION="${FULL_PARAMS%%,*}"
PARAMS_REST="${FULL_PARAMS#*,}"

# Export any additional parameters
if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && export "$key=$val"
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Log informational messages with green checkmark
log_info() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

# Log warning messages with yellow warning sign
log_warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
}

# Log error messages with red X and exit
log_error() {
    printf "${RED}✗${NC} %s\n" "$1"
    exit 1
}

# Detect distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
    else
        log_error "Cannot detect distribution"
    fi
}

# Install qemu-guest-agent
install_guest_agent() {
    log_info "Installing qemu-guest-agent..."
    
    detect_distro
    
    case "${OS_ID}" in
        debian | ubuntu)
            sudo apt-get update -qq
            sudo apt-get install -y qemu-guest-agent
            ;;
        rhel | centos | rocky | fedora | alma)
            sudo dnf install -y qemu-guest-agent
            ;;
        arch | manjaro)
            sudo pacman -S --noconfirm qemu-guest-agent
            ;;
        suse | opensuse | opensuse-leap | opensuse-tumbleweed)
            sudo zypper install -y qemu-guest-agent
            ;;
        alpine)
            sudo apk add --no-cache qemu-guest-agent
            ;;
        *)
            log_error "Unsupported distribution: ${OS_ID}"
            ;;
    esac
    
    # Start and enable service
    log_info "Starting and enabling qemu-guest-agent service..."
    sudo systemctl start qemu-guest-agent
    sudo systemctl enable qemu-guest-agent
    
    log_info "qemu-guest-agent installed successfully"
}

# Update qemu-guest-agent
update_guest_agent() {
    log_info "Updating qemu-guest-agent..."
    
    detect_distro
    
    case "${OS_ID}" in
        debian | ubuntu)
            sudo apt-get update -qq
            sudo apt-get upgrade -y qemu-guest-agent
            ;;
        rhel | centos | rocky | fedora | alma)
            sudo dnf upgrade -y qemu-guest-agent
            ;;
        arch | manjaro)
            sudo pacman -Syu --noconfirm qemu-guest-agent
            ;;
        suse | opensuse | opensuse-leap | opensuse-tumbleweed)
            sudo zypper update -y qemu-guest-agent
            ;;
        alpine)
            sudo apk upgrade qemu-guest-agent
            ;;
        *)
            log_error "Unsupported distribution: ${OS_ID}"
            ;;
    esac
    
    # Restart service
    log_info "Restarting qemu-guest-agent service..."
    sudo systemctl restart qemu-guest-agent
    
    log_info "qemu-guest-agent updated successfully"
}

# Uninstall qemu-guest-agent
uninstall_guest_agent() {
    log_warn "This will remove qemu-guest-agent from this guest VM."
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Uninstall cancelled"
        return 0
    fi
    
    log_info "Uninstalling qemu-guest-agent..."
    
    detect_distro
    
    # Stop and disable service
    log_info "Stopping and disabling qemu-guest-agent service..."
    sudo systemctl stop qemu-guest-agent || true
    sudo systemctl disable qemu-guest-agent || true
    
    case "${OS_ID}" in
        debian | ubuntu)
            sudo apt-get remove -y qemu-guest-agent
            sudo apt-get autoremove -y
            ;;
        rhel | centos | rocky | fedora | alma)
            sudo dnf remove -y qemu-guest-agent
            ;;
        arch | manjaro)
            sudo pacman -R --noconfirm qemu-guest-agent
            ;;
        suse | opensuse | opensuse-leap | opensuse-tumbleweed)
            sudo zypper remove -y qemu-guest-agent
            ;;
        alpine)
            sudo apk del qemu-guest-agent
            ;;
        *)
            log_error "Unsupported distribution: ${OS_ID}"
            ;;
    esac
    
    log_info "qemu-guest-agent uninstalled successfully"
}

# Check if running on Proxmox host (has pct and qm commands)
check_proxmox_host() {
    if ! command -v pct &> /dev/null || ! command -v qm &> /dev/null; then
        log_error "This script must run on a Proxmox VE host (pct/qm commands not found)"
    fi
}

# Convert LXC container to template
make_lxc_to_template() {
    check_proxmox_host
    
    read -p "Enter container ID (CTID): " CTID
    
    if [[ -z "$CTID" ]]; then
        log_error "Container ID cannot be empty"
    fi
    
    log_info "Converting LXC container $CTID to template..."
    
    if sudo pct set "$CTID" -template 1; then
        log_info "Container $CTID is now a template"
    else
        log_error "Failed to convert container $CTID to template"
    fi
}

# Convert template LXC container back to normal
make_template_to_lxc() {
    check_proxmox_host
    
    read -p "Enter container ID (CTID): " CTID
    
    if [[ -z "$CTID" ]]; then
        log_error "Container ID cannot be empty"
    fi
    
    log_info "Converting template $CTID back to normal container..."
    
    if sudo pct set "$CTID" -template 0; then
        log_info "Container $CTID is now a normal container"
    else
        log_error "Failed to convert container $CTID back to normal"
    fi
}

# Unlock a locked VM/container
unlock_vm() {
    check_proxmox_host
    
    read -p "Enter container/VM ID (CTID): " CTID
    
    if [[ -z "$CTID" ]]; then
        log_error "Container/VM ID cannot be empty"
    fi
    
    log_info "Unlocking container/VM $CTID..."
    
    if sudo pct unlock "$CTID"; then
        log_info "Container/VM $CTID is now unlocked"
    else
        log_error "Failed to unlock container/VM $CTID"
    fi
}

# Stop all VMs and LXC containers
stop_all_containers() {
    check_proxmox_host
    
    log_info "Stopping all VMs and LXC containers..."
    
    # Stop all QEMU VMs
    log_info "Stopping all QEMU VMs..."
    for vmid in $(sudo qm list | awk 'NR>1 {print $1}'); do
        if [[ -n "$vmid" ]]; then
            log_info "Stopping VM $vmid..."
            sudo qm stop "$vmid" || log_warn "Failed to stop VM $vmid"
        fi
    done
    
    # Stop all LXC containers
    log_info "Stopping all LXC containers..."
    for ctid in $(sudo pct list | awk 'NR>1 {print $1}'); do
        if [[ -n "$ctid" ]]; then
            log_info "Stopping container $ctid..."
            sudo pct stop "$ctid" || log_warn "Failed to stop container $ctid"
        fi
    done
    
    log_info "Stop-all operation completed"
}

# List all LXC containers (running and offline)
list_all_lxc() {
    check_proxmox_host
    
    log_info "Listing all LXC containers..."
    printf "%-8s %-20s %-20s %-10s\n" "VMID" "Hostname" "IP" "Status"
    echo "============================================================"
    for id in $(sudo pct list | awk 'NR>1 {print $1}'); do
        name=$(sudo pct config "$id" | grep hostname | awk '{print $2}')
        ip=$(sudo pct config "$id" | grep -oP 'ip=\K[^,]+' | head -1)
        status=$(sudo pct status "$id" | awk '{print $2}')
        printf "%-8s %-20s %-20s %-10s\n" "$id" "$name" "$ip" "$status"
    done
    echo "============================================================"
}

# List only running LXC containers with live IP
list_running_lxc() {
    check_proxmox_host
    
    log_info "Listing running LXC containers..."
    printf "%-8s %-20s %-20s\n" "VMID" "Hostname" "IP"
    echo "-------------------------------------------"
    for id in $(sudo pct list | grep running | awk '{print $1}'); do
        name=$(sudo pct config "$id" | grep hostname | awk '{print $2}')
        ip=$(sudo pct exec "$id" -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        printf "%-8s %-20s %-20s\n" "$id" "$name" "$ip"
    done
    echo "-------------------------------------------"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_guest_agent
        ;;
    update)
        update_guest_agent
        ;;
    uninstall)
        uninstall_guest_agent
        ;;
    make-lxc-to-template)
        make_lxc_to_template
        ;;
    make-template-to-lxc)
        make_template_to_lxc
        ;;
    unlock-vm)
        unlock_vm
        ;;
    stop-all)
        stop_all_containers
        ;;
    list-lxc)
        list_all_lxc
        ;;
    list-lxc-running)
        list_running_lxc
        ;;
    *)
        log_error "Unknown action: $ACTION"
        ;;
esac
