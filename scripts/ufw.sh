#!/bin/bash

# ufw - Uncomplicated Firewall
# Install, update, uninstall, and configure UFW on all Linux distributions

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
NC='\033[0m'

# Log informational messages with green checkmark
log_info() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

# Log error messages with red X and exit
log_error() {
    printf "${RED}✗${NC} %s\n" "$1"
    exit 1
}

# Detect operating system and set appropriate package manager commands
detect_os() {
    source /etc/os-release || log_error "Cannot detect OS"
    
    case "${ID,,}" in
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
            log_error "Unsupported distribution"
            ;;
    esac
}

# Install UFW
install_ufw() {
    log_info "Installing ufw..."
    detect_os
    
    sudo $PKG_UPDATE || true
    sudo $PKG_INSTALL ufw || log_error "Failed"
    
    log_info "ufw installed!"
}

# Update UFW
update_ufw() {
    log_info "Updating ufw..."
    detect_os
    
    sudo $PKG_UPDATE || true
    sudo $PKG_INSTALL ufw || log_error "Failed"
    
    log_info "ufw updated!"
}

# Uninstall UFW
uninstall_ufw() {
    log_info "Uninstalling ufw..."
    detect_os
    
    sudo ufw disable || true
    sudo $PKG_UNINSTALL ufw || log_error "Failed"
    
    log_info "ufw uninstalled!"
}

# Configure UFW with interactive rule management
configure_ufw() {
    log_info "UFW Configuration Menu"
    
    # If PORT is set via parameters, use simple mode (backward compatibility)
    if [[ -n "$PORT" ]]; then
        log_info "Adding rule for port $PORT..."
        sudo ufw allow "$PORT" || log_error "Failed to add rule"
        log_info "Port $PORT allowed!"
        return
    fi
    
    # Interactive menu
    while true; do
        echo ""
        log_info "Choose action:"
        echo "  1) Add Rule"
        echo "  2) Delete Rule"
        echo "  3) Show Rules"
        echo "  4) Back to main menu"
        echo ""
        read -p "Enter choice (1-4): " choice
        
        case "$choice" in
            1)
                # Add Rule
                read -p "Port number: " port
                read -p "Protocol (tcp/udp, default: tcp): " protocol
                protocol="${protocol:-tcp}"
                read -p "Action (allow/deny/reject, default: allow): " action
                action="${action:-allow}"
                read -p "From IP (optional, press Enter for any): " from_ip
                
                if [[ -z "$from_ip" ]]; then
                    sudo ufw "$action" "$port/$protocol" || log_error "Failed to add rule"
                    log_info "Rule added: $action $port/$protocol"
                else
                    sudo ufw "$action" from "$from_ip" to any port "$port" proto "$protocol" || log_error "Failed to add rule"
                    log_info "Rule added: $action from $from_ip port $port/$protocol"
                fi
                ;;
            2)
                # Delete Rule
                log_info "Current rules:"
                sudo ufw status numbered || true
                echo ""
                read -p "Enter rule number to delete: " rule_num
                
                if [[ -n "$rule_num" && "$rule_num" =~ ^[0-9]+$ ]]; then
                    # Use 'yes' to auto-confirm deletion
                    sudo bash -c "echo 'y' | ufw delete $rule_num" || log_error "Failed to delete rule"
                    log_info "Rule deleted!"
                else
                    log_error "Invalid rule number"
                fi
                ;;
            3)
                # Show Rules
                log_info "Current UFW status and rules:"
                sudo ufw status verbose || true
                ;;
            4)
                # Back to main menu
                log_info "Returning to main menu..."
                break
                ;;
            *)
                log_error "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
}

# Show UFW firewall status
status_ufw() {
    log_info "UFW Firewall Status:"
    sudo ufw status verbose || log_error "Failed to get status"
}

# Reset UFW firewall to defaults
reset_ufw() {
    log_info "Resetting UFW to default settings..."
    
    read -p "Are you sure? This will reset all UFW rules (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        sudo bash -c "echo 'y' | ufw reset" || log_error "Failed to reset UFW"
        log_info "UFW reset to default settings!"
    else
        log_info "Reset cancelled."
    fi
}

# Enable UFW firewall
enable_ufw() {
    log_info "Enabling ufw..."
    
    sudo ufw enable || log_error "Failed"
    
    log_info "ufw enabled!"
}

# Disable UFW firewall
disable_ufw() {
    log_info "Disabling ufw..."
    
    sudo ufw disable || log_error "Failed"
    
    log_info "ufw disabled!"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_ufw
        ;;
    update)
        update_ufw
        ;;
    uninstall)
        uninstall_ufw
        ;;
    config)
        configure_ufw
        ;;
    enable)
        enable_ufw
        ;;
    disable)
        disable_ufw
        ;;
    status)
        status_ufw
        ;;
    reset)
        reset_ufw
        ;;
    *)
        log_error "Unknown action: $ACTION"
        ;;
esac
