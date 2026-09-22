#!/bin/bash

# proxmox - Guest agent and container management for Proxmox hosts
# Manages qemu-guest-agent (for guests) and VM/LXC container operations

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
parse_parameters "$1"

# Install qemu-guest-agent
install_guest_agent() {
    log_info "Installing qemu-guest-agent..."
    
    detect_os
    
    case "$PKG_TYPE" in
        deb)
            $PKG_UPDATE || true
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to install qemu-guest-agent"
            ;;
        rpm)
            $PKG_UPDATE || true
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to install qemu-guest-agent"
            ;;
        pacman)
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to install qemu-guest-agent"
            ;;
        zypper)
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to install qemu-guest-agent"
            ;;
        apk)
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to install qemu-guest-agent"
            ;;
        *)
            log_error "Unsupported package manager"
            ;;
    esac
    
    # Start service (suppress SysV sync warnings from systemd)
    if command -v systemctl &>/dev/null; then
        systemctl start qemu-guest-agent 2>/dev/null || true
    fi
    
    log_info "qemu-guest-agent installed successfully!"
}

# Update qemu-guest-agent
update_guest_agent() {
    log_info "Updating qemu-guest-agent..."
    
    detect_os
    
    case "$PKG_TYPE" in
        deb)
            $PKG_UPDATE || true
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to update"
            ;;
        rpm)
            $PKG_UPDATE || true
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to update"
            ;;
        pacman)
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to update"
            ;;
        zypper)
            $PKG_INSTALL qemu-guest-agent || log_error "Failed to update"
            ;;
        apk)
            apk upgrade qemu-guest-agent || log_error "Failed to update"
            ;;
        *)
            log_error "Unsupported package manager"
            ;;
    esac
    
    # Restart service
    if command -v systemctl &>/dev/null; then
        systemctl restart qemu-guest-agent 2>/dev/null || true
    fi
    
    log_info "qemu-guest-agent updated successfully!"
}

# Uninstall qemu-guest-agent
uninstall_guest_agent() {
    log_info "Uninstalling qemu-guest-agent..."
    
    detect_os
    
    # Stop service first
    if command -v systemctl &>/dev/null; then
        systemctl stop qemu-guest-agent 2>/dev/null || true
        systemctl disable qemu-guest-agent 2>/dev/null || true
    fi
    
    case "$PKG_TYPE" in
        deb)
            $PKG_UNINSTALL qemu-guest-agent || log_error "Failed to uninstall"
            ;;
        rpm)
            $PKG_UNINSTALL qemu-guest-agent || log_error "Failed to uninstall"
            ;;
        pacman)
            $PKG_UNINSTALL qemu-guest-agent || log_error "Failed to uninstall"
            ;;
        zypper)
            $PKG_UNINSTALL qemu-guest-agent || log_error "Failed to uninstall"
            ;;
        apk)
            $PKG_UNINSTALL qemu-guest-agent || log_error "Failed to uninstall"
            ;;
        *)
            log_error "Unsupported package manager"
            ;;
    esac
    
    log_info "qemu-guest-agent uninstalled successfully!"
}

# Make LXC container a template
make_lxc_to_template() {
    log_info "Converting LXC container to template..."
    
    if [[ -z "$CTID" ]]; then
        log_error "Container ID (CTID) not provided"
    fi
    
    if ! command -v pct &>/dev/null; then
        log_error "pct command not found - not running on Proxmox"
    fi
    
    # Stop container if running
    if pct status "$CTID" 2>/dev/null | grep -q "running"; then
        log_info "Stopping container $CTID..."
        pct stop "$CTID"
        sleep 2
    fi
    
    # Convert to template
    log_info "Converting container $CTID to template..."
    pct set "$CTID" -template 1 || log_error "Failed to convert container"
    
    log_info "Container $CTID converted to template successfully!"
}

# Make template a normal LXC container
make_template_to_lxc() {
    log_info "Converting template to LXC container..."
    
    if [[ -z "$CTID" ]]; then
        log_error "Container ID (CTID) not provided"
    fi
    
    if ! command -v pct &>/dev/null; then
        log_error "pct command not found - not running on Proxmox"
    fi
    
    # Convert to normal container
    log_info "Converting template $CTID to normal container..."
    pct set "$CTID" -template 0 || log_error "Failed to convert template"
    
    log_info "Template $CTID converted to normal container successfully!"
}

# Unlock a locked VM or container
unlock_vm() {
    log_info "Unlocking VM/container..."
    
    if [[ -z "$CTID" ]]; then
        log_error "VM/Container ID (CTID) not provided"
    fi
    
    if ! command -v qm &>/dev/null && ! command -v pct &>/dev/null; then
        log_error "qm/pct commands not found - not running on Proxmox"
    fi
    
    # Try qm (VM) first, then pct (LXC)
    if qm unlock "$CTID" 2>/dev/null; then
        log_info "VM $CTID unlocked successfully!"
    elif pct unlock "$CTID" 2>/dev/null; then
        log_info "Container $CTID unlocked successfully!"
    else
        log_error "Failed to unlock VM/container $CTID"
    fi
}

# Stop all VMs and LXC containers
stop_all() {
    log_info "Stopping all VMs and LXC containers..."
    
    if ! command -v qm &>/dev/null || ! command -v pct &>/dev/null; then
        log_error "qm/pct commands not found - not running on Proxmox"
    fi
    
    # Stop all VMs
    log_info "Stopping all VMs..."
    local vms=$(qm list 2>/dev/null | tail -n +2 | awk '{print $1}')
    for vmid in $vms; do
        if qm status "$vmid" 2>/dev/null | grep -q "running"; then
            log_info "  Stopping VM $vmid..."
            qm stop "$vmid" &
        fi
    done
    wait
    
    # Stop all LXC containers
    log_info "Stopping all LXC containers..."
    local ctids=$(pct list 2>/dev/null | tail -n +2 | awk '{print $1}')
    for ctid in $ctids; do
        if pct status "$ctid" 2>/dev/null | grep -q "running"; then
            log_info "  Stopping container $ctid..."
            pct stop "$ctid" &
        fi
    done
    wait
    
    log_info "All VMs and containers stopped successfully!"
}

# List all LXC containers
list_lxc() {
    log_info "Listing all LXC containers..."
    
    if ! command -v pct &>/dev/null; then
        log_error "pct command not found - not running on Proxmox"
    fi
    
    echo ""
    pct list || log_error "Failed to list containers"
}

# List running LXC containers with live IPs
list_lxc_running() {
    log_info "Listing running LXC containers with IPs..."
    
    if ! command -v pct &>/dev/null; then
        log_error "pct command not found - not running on Proxmox"
    fi
    
    echo ""
    printf "VMID  %-20s %-20s %s\n" "HOSTNAME" "IP" "STATUS"
    printf "%-6s%-20s %-20s %s\n" "----" "--------" "--" "------"
    
    local ctids=$(pct list 2>/dev/null | tail -n +2 | awk '{print $1}')
    for ctid in $ctids; do
        local status=$(pct status "$ctid" 2>/dev/null)
        if echo "$status" | grep -q "running"; then
            local hostname=$(pct exec "$ctid" hostname 2>/dev/null || echo "N/A")
            local ip=$(pct exec "$ctid" hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
            printf "%-6s%-20s %-20s %s\n" "$ctid" "$hostname" "$ip" "running"
        fi
    done
}

# Start a specific VM
start_vm() {
    log_info "Starting VM..."
    
    if [[ -z "$VMID" ]]; then
        log_error "VM ID (VMID) not provided"
    fi
    
    if ! command -v qm &>/dev/null; then
        log_error "qm command not found - not running on Proxmox"
    fi
    
    log_info "Starting VM $VMID..."
    qm start "$VMID" || log_error "Failed to start VM $VMID"
    
    sleep 2
    log_info "VM $VMID started successfully!"
}

# Stop a specific VM
stop_vm() {
    log_info "Stopping VM..."
    
    if [[ -z "$VMID" ]]; then
        log_error "VM ID (VMID) not provided"
    fi
    
    if ! command -v qm &>/dev/null; then
        log_error "qm command not found - not running on Proxmox"
    fi
    
    log_info "Stopping VM $VMID..."
    qm stop "$VMID" || log_error "Failed to stop VM $VMID"
    
    log_info "VM $VMID stopped successfully!"
}

# Start a specific LXC container
start_lxc() {
    log_info "Starting LXC container..."
    
    if [[ -z "$CTID" ]]; then
        log_error "Container ID (CTID) not provided"
    fi
    
    if ! command -v pct &>/dev/null; then
        log_error "pct command not found - not running on Proxmox"
    fi
    
    log_info "Starting container $CTID..."
    pct start "$CTID" || log_error "Failed to start container $CTID"
    
    sleep 2
    log_info "Container $CTID started successfully!"
}

# Stop a specific LXC container
stop_lxc() {
    log_info "Stopping LXC container..."
    
    if [[ -z "$CTID" ]]; then
        log_error "Container ID (CTID) not provided"
    fi
    
    if ! command -v pct &>/dev/null; then
        log_error "pct command not found - not running on Proxmox"
    fi
    
    log_info "Stopping container $CTID..."
    pct stop "$CTID" || log_error "Failed to stop container $CTID"
    
    log_info "Container $CTID stopped successfully!"
}

# Route to appropriate action
case "$ACTION" in
    install)                install_guest_agent ;;
    update)                 update_guest_agent ;;
    uninstall)              uninstall_guest_agent ;;
    make-lxc-to-template)   make_lxc_to_template ;;
    make-template-to-lxc)   make_template_to_lxc ;;
    unlock-vm)              unlock_vm ;;
    stop-all)               stop_all ;;
    list-lxc)               list_lxc ;;
    list-lxc-running)       list_lxc_running ;;
    start-vm)               start_vm ;;
    stop-vm)                stop_vm ;;
    start-lxc)              start_lxc ;;
    stop-lxc)               stop_lxc ;;
    *)                      print_usage proxmox && exit 1 ;;
esac
