#!/bin/bash

# remotely - Remote desktop and support software
# Install and manage Remotely - open-source remote desktop and remote support tool

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Installation directory and config file
INSTALL_DIR="/usr/local/bin/Remotely"
CONFIG_FILE="$INSTALL_DIR/ConnectionInfo.json"
LOG_DIR="/var/log/remotely"
SERVICE_FILE="/etc/systemd/system/remotely.service"


# Install Microsoft GPG key and add repository
setup_microsoft_repo() {
    log_info "Setting up Microsoft package repository..."
    
    if [[ "$PKG_TYPE" == "deb" ]]; then
        # Debian/Ubuntu - use Microsoft's official installation script
        MS_REPO_URL="https://packages.microsoft.com/config/$MS_REPO_DISTRO/$OS_VERSION/packages-microsoft-prod.deb"
        
        log_info "Downloading Microsoft repository package..."
        curl -sSL "$MS_REPO_URL" -o /tmp/packages-microsoft-prod.deb
        
        # Auto-answer 'Y' to config file dialogs
        log_info "Installing Microsoft repository..."
        echo "Y" | DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/packages-microsoft-prod.deb 2>&1 | grep -v "Processing triggers" || true
        
        # Import Microsoft GPG key with retry logic
        log_info "Installing Microsoft GPG key..."
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EB3E94ADBE1229CF 2>/dev/null || \
        curl -sSL "https://packages.microsoft.com/keys/microsoft.asc" | apt-key add - 2>/dev/null || \
        log_warn "Microsoft GPG key import had issues, continuing anyway"
        
        rm -f /tmp/packages-microsoft-prod.deb
        
    else
        # RedHat-based
        MS_REPO_URL="https://packages.microsoft.com/config/$MS_REPO_DISTRO/$OS_VERSION/packages-microsoft-prod.rpm"
        
        log_info "Downloading Microsoft repository package..."
        curl -sSL "$MS_REPO_URL" -o /tmp/packages-microsoft-prod.rpm
        
        # Auto-answer 'Y' to config file dialogs
        log_info "Installing Microsoft repository..."
        echo "Y" | rpm -ivh /tmp/packages-microsoft-prod.rpm 2>&1 | grep -v "warning" || true
        rm -f /tmp/packages-microsoft-prod.rpm
    fi
    
    log_info "Microsoft repository configured"
}

# Generate UUID for device ID
generate_uuid() {
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null || \
        perl -e 'use Digest::MD5 qw(md5_hex); print substr(md5_hex(rand()), 0, 32);' 2>/dev/null || \
        openssl rand -hex 16 2>/dev/null || \
        echo "$(date +%s)-$(shuf -i 100000-999999 -n 1)"
    fi
}

# Install Remotely
install_remotely() {
    log_info "Checking Remotely installation status..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo"
    fi
    
    detect_os
    
    # Check if Remotely is already installed
    if systemctl list-unit-files remotely.service &>/dev/null; then
        log_info "Remotely service found"
        
        # Check if service is enabled
        if systemctl is-enabled remotely &>/dev/null; then
            # Service is enabled and exists
            if systemctl is-active --quiet remotely; then
                log_info_blue "Remotely is already installed and configured"
                return 0
            else
                log_warn "Remotely service is enabled but not running, starting it..."
                systemctl start remotely
                sleep 2
                if systemctl is-active --quiet remotely; then
                    log_info_blue "Remotely is already installed and configured"
                    return 0
                fi
            fi
        else
            # Service exists but is disabled, enable and update configuration
            log_info "Remotely is installed but disabled, enabling and updating configuration..."
            
            if [[ -z "$REMOTELY_SERVER" ]]; then
                log_error "Remotely Server URL cannot be empty"
            fi
            
            if [[ -z "$ORGANIZATION_ID" ]]; then
                log_error "OrganizationID cannot be empty"
            fi
            
            # Update configuration with new server/org
            log_info "Updating configuration..."
            local device_id=$(jq -r '.DeviceID' "$CONFIG_FILE" 2>/dev/null || echo "")
            local server_token=$(jq -r '.ServerVerificationToken' "$CONFIG_FILE" 2>/dev/null || echo "")
            
            if [[ -z "$device_id" ]]; then
                device_id=$(generate_uuid)
            fi
            
            local new_config="{
  \"DeviceID\": \"$device_id\",
  \"Host\": \"$REMOTELY_SERVER\",
  \"OrganizationID\": \"$ORGANIZATION_ID\",
  \"ServerVerificationToken\": \"$server_token\"
}"
            
            echo "$new_config" | tee "$CONFIG_FILE" > /dev/null
            chmod 600 "$CONFIG_FILE"
            
            # Enable and start service
            systemctl enable remotely
            systemctl start remotely
            sleep 2
            
            if systemctl is-active --quiet remotely; then
                log_info_blue "Remotely enabled and started successfully"
                return 0
            else
                log_warn "Remotely service did not start. Check logs with: journalctl -u remotely -n 50"
            fi
            return 0
        fi
    fi
    
    # New installation
    log_info "Installing Remotely..."
    
    # Use parameters from REMOTELY_SERVER and ORGANIZATION_ID
    if [[ -z "$REMOTELY_SERVER" ]]; then
        log_error "Remotely Server URL cannot be empty"
    fi
    
    if [[ -z "$ORGANIZATION_ID" ]]; then
        log_error "OrganizationID cannot be empty"
    fi
    
    log_info "Configuring with Server: $REMOTELY_SERVER, OrgID: $ORGANIZATION_ID"
    
    # Update package manager and install repository
    DEBIAN_FRONTEND=noninteractive $PKG_UPDATE || true
    setup_microsoft_repo
    DEBIAN_FRONTEND=noninteractive $PKG_UPDATE || true
    
    # Install required dependencies
    log_info "Installing dependencies..."
    
    # Install unzip first (critical for extraction)
    DEBIAN_FRONTEND=noninteractive $PKG_INSTALL unzip || log_error "Failed to install unzip (required)"
    
    if [[ "$PKG_TYPE" == "deb" ]]; then
        DEBIAN_FRONTEND=noninteractive $PKG_INSTALL apt-transport-https || true
        DEBIAN_FRONTEND=noninteractive $PKG_INSTALL dotnet-runtime-8.0 || log_error "Failed to install .NET runtime"
        DEBIAN_FRONTEND=noninteractive $PKG_INSTALL libx11-dev libxrandr-dev libxtst-dev libxcb-shape0 xclip jq curl || log_error "Failed to install dependencies"
    else
        $PKG_INSTALL dotnet-runtime-8.0 || log_error "Failed to install .NET runtime"
        $PKG_INSTALL libX11-devel libXrandr-devel libXtst-devel libxcb-devel xclip jq curl || log_error "Failed to install dependencies"
    fi
    
    # Generate device ID or use existing one
    DEVICE_ID=""
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Existing configuration found, preserving device ID..."
        DEVICE_ID=$(jq -r '.DeviceID' "$CONFIG_FILE" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$DEVICE_ID" ]]; then
        DEVICE_ID=$(generate_uuid)
    fi
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"
    
    # Download and extract Remotely
    log_info "Downloading Remotely agent..."
    
    TEMP_ZIP="/tmp/Remotely-Linux.zip"
    if ! curl -sSL "$REMOTELY_SERVER/Content/Remotely-Linux.zip" -o "$TEMP_ZIP"; then
        log_error "Failed to download Remotely agent from $REMOTELY_SERVER"
    fi
    
    if [[ ! -f "$TEMP_ZIP" ]]; then
        log_error "Download failed: $TEMP_ZIP not found"
    fi
    
    log_info "Extracting Remotely agent (this may take a moment)..."
    
    # Extract with progress indicator (use -a to auto-convert backslashes to forward slashes)
    unzip -q -a -o "$TEMP_ZIP" -d "$INSTALL_DIR" 2>&1 || true
    
    log_info "✓ Extraction complete"
    
    # Debug: List extracted files
    log_info "Files extracted:"
    find "$INSTALL_DIR" -maxdepth 2 -type f 2>/dev/null | head -10 | while read f; do
        log_info "  - $(basename "$f")"
    done
    
    # Verify extraction by checking for main executable (try different paths)
    local agent_found=0
    if [[ -f "$INSTALL_DIR/Remotely_Agent" ]]; then
        agent_found=1
    elif [[ -f "$INSTALL_DIR/Remotely/Remotely_Agent" ]]; then
        # ZIP may have created a Remotely subdirectory
        log_info "Found agent in subdirectory, moving files..."
        mv "$INSTALL_DIR/Remotely"/* "$INSTALL_DIR/" || true
        agent_found=1
    elif [[ -f $(find "$INSTALL_DIR" -name "Remotely_Agent" -type f 2>/dev/null | head -1) ]]; then
        log_info "Found agent in nested directory, moving..."
        find "$INSTALL_DIR" -name "Remotely_Agent" -type f -exec dirname {} \; | head -1 | xargs -I {} mv {}/* "$INSTALL_DIR/" || true
        agent_found=1
    fi
    
    if [[ $agent_found -eq 0 ]]; then
        log_error "Failed to extract Remotely agent - Remotely_Agent not found after extraction"
    fi
    
    log_info "Extracted files: $(find "$INSTALL_DIR" -type f | wc -l) files"
    
    rm -f "$TEMP_ZIP"
    
    # Make executables
    chmod +x "$INSTALL_DIR/Remotely_Agent" || true
    chmod +x "$INSTALL_DIR/Desktop/Remotely_Desktop" || true
    
    # Create connection info JSON
    log_info "Creating connection configuration..."
    
    CONNECTION_JSON="{
  \"DeviceID\": \"$DEVICE_ID\",
  \"Host\": \"$REMOTELY_SERVER\",
  \"OrganizationID\": \"$ORGANIZATION_ID\",
  \"ServerVerificationToken\": \"\"
}"
    
    echo "$CONNECTION_JSON" | tee "$CONFIG_FILE" > /dev/null
    chmod 600 "$CONFIG_FILE"
    
    # Create systemd service file
    log_info "Creating systemd service..."
    
    SERVICE_CONTENT="[Unit]
Description=Remotely agent for remote access and support
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/Remotely_Agent
Restart=always
RestartSec=10
StartLimitIntervalSec=0
StandardOutput=journal
StandardError=journal
SyslogIdentifier=remotely-agent

[Install]
WantedBy=multi-user.target"
    
    echo "$SERVICE_CONTENT" | tee "$SERVICE_FILE" > /dev/null
    systemctl daemon-reload
    
    # Enable and start service
    log_info "Enabling and starting Remotely service..."
    systemctl enable remotely
    systemctl start remotely
    
    # Verify installation
    sleep 2
    if systemctl is-active --quiet remotely; then
        log_info "Remotely service started successfully!"
    else
        log_warn "Remotely service did not start. Check logs with: journalctl -u remotely -n 50"
    fi
    
    # Display connection info
    log_info_blue "Remotely installation complete!"
    echo ""
    echo "  Connection Details:"
    echo "  ├─ DeviceID: $DEVICE_ID"
    echo "  ├─ Remotely Server: $REMOTELY_SERVER"
    echo "  ├─ OrganizationID: $ORGANIZATION_ID"
    echo "  └─ Config: $CONFIG_FILE"
    echo ""
    echo "  Status: systemctl status remotely"
    echo "  Logs:   journalctl -u remotely -f"
}

# Update Remotely
update_remotely() {
    log_info "Updating Remotely..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo"
    fi
    
    detect_os
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_error "Remotely is not installed at $INSTALL_DIR"
    fi
    
    # Read existing configuration
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
    fi
    
    REMOTELY_SERVER=$(jq -r '.Host' "$CONFIG_FILE")
    
    if [[ -z "$REMOTELY_SERVER" ]] || [[ "$REMOTELY_SERVER" == "null" ]]; then
        log_error "Cannot determine Remotely server address from configuration"
    fi
    
    # Update package manager
    DEBIAN_FRONTEND=noninteractive $PKG_UPDATE || true
    setup_microsoft_repo
    DEBIAN_FRONTEND=noninteractive $PKG_UPDATE || true
    
    # Download latest agent
    log_info "Downloading latest Remotely agent..."
    
    TEMP_ZIP="/tmp/Remotely-Linux-update.zip"
    if ! curl -sSL "$REMOTELY_SERVER/Content/Remotely-Linux.zip" -o "$TEMP_ZIP"; then
        log_error "Failed to download Remotely agent"
    fi
    
    # Backup current installation
    log_info "Backing up current installation..."
    cp -r "$INSTALL_DIR" "${INSTALL_DIR}.backup"
    
    # Extract and update (use -a to auto-convert backslashes to forward slashes)
    log_info "Extracting updated agent (this may take a moment)..."
    unzip -q -a -o "$TEMP_ZIP" -d "$INSTALL_DIR" || {
        log_warn "Extraction failed, restoring backup..."
        rm -rf "$INSTALL_DIR"
        mv "${INSTALL_DIR}.backup" "$INSTALL_DIR"
        log_error "Update failed"
    }
    log_info "✓ Extraction complete"
    
    rm -f "$TEMP_ZIP"
    
    # Make executables
    chmod +x "$INSTALL_DIR/Remotely_Agent" || true
    chmod +x "$INSTALL_DIR/Desktop/Remotely_Desktop" || true
    
    # Remove backup
    rm -rf "${INSTALL_DIR}.backup"
    
    # Restart service
    log_info "Restarting Remotely service..."
    systemctl restart remotely
    
    sleep 2
    if systemctl is-active --quiet remotely; then
        log_info "Remotely updated successfully!"
    else
        log_warn "Remotely service did not start. Check logs with: journalctl -u remotely -n 50"
    fi
}

# Uninstall Remotely
uninstall_remotely() {
    log_info "Uninstalling Remotely..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo"
    fi
    
    # Confirmation (from CONFIRM parameter)
    CONFIRM="${CONFIRM:-no}"
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Uninstall cancelled"
        return
    fi
    
    # Keep config (from KEEP_CONFIG parameter, default "yes")
    KEEP_CONFIG="${KEEP_CONFIG:-yes}"
    
    # Stop and disable service
    log_info "Stopping Remotely service..."
    systemctl stop remotely || true
    systemctl disable remotely || true
    
    # Remove service file
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    
    # Remove installation
    if [[ "$KEEP_CONFIG" == "yes" ]]; then
        log_info "Keeping configuration files at: $CONFIG_FILE"
        rm -rf "$INSTALL_DIR"/*
        # Restore just the config
        cp "$CONFIG_FILE" /tmp/ConnectionInfo.json.bak || true
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
        mv /tmp/ConnectionInfo.json.bak "$CONFIG_FILE" || true
    else
        log_info "Removing installation and configuration..."
        rm -rf "$INSTALL_DIR"
    fi
    
    # Ask about removing Microsoft repository
    # Remove repo (from REMOVE_REPO parameter, default "no")
    REMOVE_REPO="${REMOVE_REPO:-no}"
    if [[ "$REMOVE_REPO" == "yes" ]]; then
        log_info "Removing Microsoft repository..."
        
        detect_os
        
        if [[ "$PKG_TYPE" == "deb" ]]; then
            apt-key del "BC528686B50D79E339D3721CEB3E94ADBE1229CF" || true
            rm -f /usr/share/keyrings/microsoft-archive-keyring.gpg
            rm -f /etc/apt/sources.list.d/microsoft-prod.list
        else
            rpm --erase packages-microsoft-prod || true
        fi
    fi
    
    log_info "Remotely uninstalled successfully!"
}

# Reconfigure Remotely connection settings
config_remotely() {
    log_info "Reconfiguring Remotely..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo"
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
    fi
    
    # Read current configuration
    log_info_blue "Current configuration:"
    
    DEVICE_ID=$(jq -r '.DeviceID' "$CONFIG_FILE")
    SERVER_TOKEN=$(jq -r '.ServerVerificationToken' "$CONFIG_FILE")
    CURRENT_REMOTELY_SERVER=$(jq -r '.Host' "$CONFIG_FILE")
    CURRENT_ORG=$(jq -r '.OrganizationID' "$CONFIG_FILE")
    
    echo "  DeviceID: $DEVICE_ID"
    echo "  Remotely Server: $CURRENT_REMOTELY_SERVER"
    echo "  OrganizationID: $CURRENT_ORG"
    echo ""
    
    # Use parameters for new values, with fallback to current
    NEW_REMOTELY_SERVER="${NEW_REMOTELY_SERVER:-$CURRENT_REMOTELY_SERVER}"
    NEW_ORG="${NEW_ORG:-$CURRENT_ORG}"
    
    # Backup configuration
    log_info "Backing up configuration..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    
    # Update JSON with new values while preserving DeviceID and ServerVerificationToken
    log_info "Updating configuration..."
    
    NEW_CONFIG=$(jq \
        --arg deviceid "$DEVICE_ID" \
        --arg host "$NEW_REMOTELY_SERVER" \
        --arg orgid "$NEW_ORG" \
        --arg token "$SERVER_TOKEN" \
        '{DeviceID: $deviceid, Host: $host, OrganizationID: $orgid, ServerVerificationToken: $token}' \
        <<< '{}')
    
    echo "$NEW_CONFIG" | tee "$CONFIG_FILE" > /dev/null
    chmod 600 "$CONFIG_FILE"
    
    # Restart service
    log_info "Restarting Remotely service..."
    systemctl restart remotely
    
    sleep 2
    if systemctl is-active --quiet remotely; then
        log_info "Configuration updated successfully!"
    else
        log_warn "Service did not start. Check logs with: journalctl -u remotely -n 50"
    fi
    
    log_info_blue "New configuration:"
    echo "  DeviceID: $DEVICE_ID"
    echo "  Remotely Server: $NEW_REMOTELY_SERVER"
    echo "  OrganizationID: $NEW_ORG"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_remotely
        ;;
    update)
        update_remotely
        ;;
    uninstall)
        uninstall_remotely
        ;;
    config)
        config_remotely
        ;;
    *)
        print_usage remotely && exit 1
esac
