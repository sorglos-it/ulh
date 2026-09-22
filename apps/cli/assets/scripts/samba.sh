#!/bin/bash

# samba - Network file sharing with Samba/SMB
# Install, update, uninstall, and configure Samba for all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"
# Samba configuration paths
SMB_CONF="/etc/samba/smb.conf"
SMB_CONF_BACKUP="/etc/samba/smb.conf.backup.$(date +%Y%m%d_%H%M%S)"


# Prompt for user input with default value
prompt_input() {
    local prompt_text="$1"
    local default_val="$2"
    local input_var
    
    if [[ -n "$default_val" ]]; then
        read -p "$prompt_text [$default_val]: " input_var
        echo "${input_var:-$default_val}"
    else
        read -p "$prompt_text: " input_var
        echo "$input_var"
    fi
}

# Yes/No prompt
prompt_yes_no() {
    local prompt_text="$1"
    local default_val="${2:-no}"
    local response
    
    if [[ "$default_val" == "yes" ]]; then
        read -p "$prompt_text (yes/no) [yes]: " response
        response="${response:-yes}"
    else
        read -p "$prompt_text (yes/no) [no]: " response
        response="${response:-no}"
    fi
    
    [[ "$response" == "yes" ]] && echo "yes" || echo "no"
}

# Confirm action
confirm() {
    local prompt_text="$1"
    local response
    
    read -p "$prompt_text (yes/no): " response
    [[ "$response" == "yes" ]]
}

install_samba() {
    log_section "Installing Samba..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL samba samba-client || log_error "Failed to install Samba"
    
    # Backup original smb.conf
    if [[ -f "$SMB_CONF" ]]; then
        log_info "Backing up original smb.conf to $SMB_CONF_BACKUP"
        cp "$SMB_CONF" "$SMB_CONF_BACKUP"
    fi
    
    # Create initial basic configuration
    log_info "Creating initial Samba configuration..."
    create_initial_config
    
    # Enable and start services
    log_info "Enabling and starting Samba services..."
    systemctl enable smbd nmbd 2>/dev/null || true
    systemctl start smbd nmbd || log_error "Failed to start Samba services"
    
    log_info "Samba installed and configured successfully!"
    log_info "Configuration file: $SMB_CONF"
    log_info "Services: smbd, nmbd"
    
    # Show version
    smbd --version | head -1
}

create_initial_config() {
    # Create a basic smb.conf if it doesn't exist
    cat << 'EOF' | tee "$SMB_CONF" > /dev/null
[global]
    workgroup = WORKGROUP
    server string = Samba Server
    security = user
    map to guest = Never
    guest account = nobody
    wins support = no
    dns proxy = yes
    log file = /var/log/samba/%m.log
    log level = 1
    max log size = 50
    load printers = no
    printing = cups
    printcap name = cups

[homes]
    comment = Home Directories
    browseable = no
    writable = yes
    create mask = 0700
    directory mask = 0700
EOF
}

update_samba() {
    log_section "Updating Samba..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL samba samba-client || log_error "Failed to update Samba"
    
    # Validate configuration
    if command -v testparm &> /dev/null; then
        log_info "Validating smb.conf..."
        testparm -s "$SMB_CONF" > /dev/null 2>&1 || log_error "Configuration validation failed"
    fi
    
    # Restart services
    log_info "Restarting Samba services..."
    systemctl restart smbd nmbd || log_error "Failed to restart services"
    
    log_info "Samba updated successfully!"
    smbd --version | head -1
}

uninstall_samba() {
    log_section "Uninstalling Samba..."
    
    if ! confirm "Are you sure you want to uninstall Samba?"; then
        log_warn "Uninstall cancelled"
        return
    fi
    
    local keep_config
    keep_config=$(prompt_yes_no "Keep backup configuration file?" "yes")
    
    # Stop services
    log_info "Stopping Samba services..."
    systemctl stop smbd nmbd 2>/dev/null || true
    systemctl disable smbd nmbd 2>/dev/null || true
    
    # Remove packages
    detect_os
    log_info "Removing Samba packages..."
    $PKG_UNINSTALL samba samba-client || log_error "Failed to uninstall Samba"
    
    if [[ "$keep_config" == "no" ]] && [[ -f "$SMB_CONF" ]]; then
        log_info "Removing configuration files..."
        rm -f "$SMB_CONF"
    fi
    
    log_info "Samba uninstalled successfully!"
}

configure_samba() {
    log_section "Configuring Samba globally (smb.conf)..."
    
    # Backup current config
    if [[ -f "$SMB_CONF" ]]; then
        log_info "Backing up current smb.conf"
        cp "$SMB_CONF" "${SMB_CONF}.bak"
    fi
    
    # Use parameters from the catalog (catalog.yaml) or defaults
    log_section "Global Configuration"
    
    local workgroup="${WORKGROUP:-WORKGROUP}"
    local server_desc="${SERVER_DESC:-Samba Server}"
    local security="${SECURITY:-user}"
    local map_guest="${MAP_GUEST:-Never}"
    local guest_acct="${GUEST_ACCT:-nobody}"
    local wins="${WINS:-no}"
    local hosts="${HOSTS:-yes}"
    local log_level="${LOG_LEVEL:-1}"
    
    log_info "Using configuration: workgroup=$workgroup, security=$security, logging=$log_level"
    
    # Create updated configuration
    cat << EOF | tee "$SMB_CONF" > /dev/null
[global]
    workgroup = $workgroup
    server string = $server_desc
    security = $security
    map to guest = $map_guest
    guest account = $guest_acct
    wins support = $wins
    dns proxy = $hosts
    log file = /var/log/samba/%m.log
    log level = $log_level
    max log size = 50
    load printers = no
    printing = cups
    printcap name = cups

[homes]
    comment = Home Directories
    browseable = no
    writable = yes
    create mask = 0700
    directory mask = 0700
EOF
    
    # Validate configuration
    if command -v testparm &> /dev/null; then
        log_info "Validating configuration..."
        if testparm -s "$SMB_CONF" > /dev/null 2>&1; then
            log_info "Configuration is valid"
        else
            log_error "Configuration validation failed - configuration not applied"
        fi
    fi
    
    # Restart services
    log_info "Restarting Samba services..."
    systemctl restart smbd nmbd || log_error "Failed to restart services"
    
    log_info "Samba configuration updated successfully!"
}

add_share() {
    log_section "Adding new Samba share..."
    
    # Prompt for all 9 share configuration parameters
    log_info "Enter share details (9 questions):"
    
    local share_name=$(prompt_input "1. Share name (e.g., data, documents)" "")
    [[ -z "$share_name" ]] && log_error "Share name cannot be empty"
    
    local share_comment=$(prompt_input "2. Share comment/description" "Shared Folder")
    
    local share_path=$(prompt_input "3. Share path (directory to share)" "")
    [[ -z "$share_path" ]] && log_error "Share path cannot be empty"
    
    local writeable=$(prompt_yes_no "4. Writable (Yes/No)?" "yes")
    local only_guest=$(prompt_yes_no "5. Only guest (Yes/No)?" "no")
    local create_mask=$(prompt_input "6. Create mask (e.g., 0777)" "0777")
    local directory_mask=$(prompt_input "7. Directory mask (e.g., 0777)" "0777")
    local browseable=$(prompt_yes_no "8. Browseable (Yes/No)?" "yes")
    local public=$(prompt_yes_no "9. Public (yes/no)?" "yes")
    
    # Create directory if needed
    if [[ ! -d "$share_path" ]]; then
        log_info "Creating directory: $share_path"
        mkdir -p "$share_path" || log_error "Failed to create directory"
    fi
    
    # Set ownership and permissions
    local owner=$(prompt_input "Directory owner" "root")
    local group=$(prompt_input "Directory group" "root")
    
    log_info "Setting ownership and permissions..."
    chown "$owner:$group" "$share_path" || log_error "Failed to set owner"
    chmod "$create_mask" "$share_path" || log_error "Failed to set permissions"
    
    # Convert yes/no to Yes/No for smb.conf
    [[ "$writeable" == "yes" ]] && writeable="Yes" || writeable="No"
    [[ "$only_guest" == "yes" ]] && only_guest="Yes" || only_guest="No"
    [[ "$browseable" == "yes" ]] && browseable="Yes" || browseable="No"
    
    # Create share configuration entry with all 9 parameters
    cat << EOF | tee -a "$SMB_CONF" > /dev/null

[$share_name]
    comment = $share_comment
    path = $share_path
    writeable = $writeable
    only guest = $only_guest
    create mask = $create_mask
    directory mask = $directory_mask
    browseable = $browseable
    public = $public
EOF
    
    # Validate configuration
    if command -v testparm &> /dev/null; then
        log_info "Validating configuration..."
        if ! testparm -s "$SMB_CONF" > /dev/null 2>&1; then
            log_error "Configuration validation failed - reverting"
        fi
    fi
    
    # Restart services
    log_info "Restarting Samba services..."
    systemctl restart smbd nmbd || log_error "Failed to restart services"
    
    log_info "Share '$share_name' added successfully!"
    log_info "Path: $share_path"
    log_info "Writeable: $writeable, Guest only: $only_guest, Browseable: $browseable, Public: $public"
}

smbuser_menu() {
    while true; do
        log_section "Samba User Management"
        echo "1) Add user"
        echo "2) Delete user"
        echo "3) Change password"
        echo "4) List users"
        echo "5) Back"
        
        local choice=$(prompt_input "Choose action" "5")
        
        case "$choice" in
            1) smbuser_add ;;
            2) smbuser_delete ;;
            3) smbuser_change_password ;;
            4) smbuser_list ;;
            5) return ;;
            *)
                log_warn "Invalid option" ;;
        esac
    done
}

smbuser_add() {
    log_section "Add Samba User"
    
    local username=$(prompt_input "Username" "")
    [[ -z "$username" ]] && log_error "Username cannot be empty"
    
    local password
    local password_confirm
    
    while true; do
        password=$(prompt_input "Password" "")
        [[ -z "$password" ]] && log_error "Password cannot be empty"
        
        password_confirm=$(prompt_input "Confirm password" "")
        
        if [[ "$password" == "$password_confirm" ]]; then
            break
        else
            log_warn "Passwords do not match, try again"
        fi
    done
    
    # Check if system user exists, create if not
    if ! id "$username" &>/dev/null; then
        log_info "Creating system user: $username"
        useradd -m -s /nologin "$username" || log_error "Failed to create user"
    fi
    
    # Add to Samba with password
    log_info "Adding user to Samba..."
    echo -e "$password\n$password" | smbpasswd -a -s "$username" || log_error "Failed to add Samba user"
    
    log_info "User '$username' added to Samba successfully!"
}

smbuser_delete() {
    log_section "Delete Samba User"
    
    local username=$(prompt_input "Username to delete" "")
    [[ -z "$username" ]] && log_error "Username cannot be empty"
    
    if ! confirm "Are you sure you want to delete Samba user '$username'?"; then
        log_warn "Deletion cancelled"
        return
    fi
    
    # Remove from Samba
    log_info "Removing user from Samba..."
    smbpasswd -x "$username" || log_error "Failed to delete Samba user"
    
    log_info "User '$username' removed from Samba successfully!"
}

smbuser_change_password() {
    log_section "Change Samba User Password"
    
    local username=$(prompt_input "Username" "")
    [[ -z "$username" ]] && log_error "Username cannot be empty"
    
    local password
    local password_confirm
    
    while true; do
        password=$(prompt_input "New password" "")
        [[ -z "$password" ]] && log_error "Password cannot be empty"
        
        password_confirm=$(prompt_input "Confirm password" "")
        
        if [[ "$password" == "$password_confirm" ]]; then
            break
        else
            log_warn "Passwords do not match, try again"
        fi
    done
    
    # Update password
    log_info "Updating Samba password for '$username'..."
    echo -e "$password\n$password" | smbpasswd -a -s "$username" || log_error "Failed to update password"
    
    log_info "Password updated successfully!"
}

smbuser_list() {
    log_section "Samba Users"
    
    if command -v pdbedit &> /dev/null; then
        log_info "Current Samba users:"
        pdbedit -L -v 2>/dev/null || log_warn "No Samba users found or pdbedit error"
    else
        log_warn "pdbedit not available - cannot list users"
    fi
}

smbuser() {
    log_section "Samba User Management"
    smbuser_menu
}

# Main action dispatcher
case "$ACTION" in
    install)
        install_samba
        ;;
    update)
        update_samba
        ;;
    uninstall)
        uninstall_samba
        ;;
    config)
        configure_samba
        ;;
    add-share)
        add_share
        ;;
    smbuser)
        smbuser
        ;;
    *)
        print_usage samba && exit 1
esac
