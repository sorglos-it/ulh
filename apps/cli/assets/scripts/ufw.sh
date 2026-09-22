#!/bin/bash

# ufw - Uncomplicated Firewall
# Install, update, uninstall, and configure UFW on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"


# Install UFW
install_ufw() {
    log_info "Installing ufw..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL ufw || log_error "Failed"
    
    log_info "ufw installed!"
}

# Update UFW
update_ufw() {
    log_info "Updating ufw..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL ufw || log_error "Failed"
    
    log_info "ufw updated!"
}

# Uninstall UFW
uninstall_ufw() {
    log_info "Uninstalling ufw..."
    detect_os
    
    ufw disable || true
    $PKG_UNINSTALL ufw || log_error "Failed"
    
    log_info "ufw uninstalled!"
}

# Configure UFW with interactive rule management
configure_ufw() {
    log_info "UFW Configuration Menu"
    
    # If PORT is set via parameters, use simple mode (backward compatibility)
    if [[ -n "$PORT" ]]; then
        log_info "Adding rule for port $PORT..."
        ufw allow "$PORT" || log_error "Failed to add rule"
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
                    ufw "$action" "$port/$protocol" || log_error "Failed to add rule"
                    log_info "Rule added: $action $port/$protocol"
                else
                    ufw "$action" from "$from_ip" to any port "$port" proto "$protocol" || log_error "Failed to add rule"
                    log_info "Rule added: $action from $from_ip port $port/$protocol"
                fi
                ;;
            2)
                # Delete Rule
                log_info "Current rules:"
                ufw status numbered || true
                echo ""
                read -p "Enter rule number to delete: " rule_num
                
                if [[ -n "$rule_num" && "$rule_num" =~ ^[0-9]+$ ]]; then
                    # Use 'yes' to auto-confirm deletion
                    bash -c "echo 'y' | ufw delete $rule_num" || log_error "Failed to delete rule"
                    log_info "Rule deleted!"
                else
                    log_error "Invalid rule number"
                fi
                ;;
            3)
                # Show Rules
                log_info "Current UFW status and rules:"
                ufw status verbose || true
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
    ufw status verbose || log_error "Failed to get status"
}

# Reset UFW firewall to defaults
reset_ufw() {
    log_info "Resetting UFW to default settings..."
    
    # Confirm from CONFIRM parameter
    CONFIRM="${CONFIRM:-no}"
    if [[ "$CONFIRM" == "yes" ]]; then
        bash -c "echo 'y' | ufw reset" || log_error "Failed to reset UFW"
        log_info "UFW reset to default settings!"
    else
        log_info "Reset cancelled."
    fi
}

# Enable UFW firewall
enable_ufw() {
    log_info "Enabling ufw..."
    
    ufw enable || log_error "Failed"
    
    log_info "ufw enabled!"
}

# Disable UFW firewall
disable_ufw() {
    log_info "Disabling ufw..."
    
    ufw disable || log_error "Failed"
    
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
        print_usage ufw && exit 1
        ;;
esac
