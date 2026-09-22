#!/bin/bash

# openssh - Secure Shell remote access
# Install, update, uninstall, and configure OpenSSH on all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Install OpenSSH server
install_openssh() {
    log_info "Installing openssh-server..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL openssh-server || log_error "Failed"
    
    # Enable SSH service (handle both 'ssh' and 'sshd' service names)
    systemctl enable ssh || systemctl enable sshd
    
    log_info "openssh-server installed and enabled!"
}

# Update OpenSSH server
update_openssh() {
    log_info "Updating openssh-server..."
    detect_os
    
    $PKG_UPDATE || true
    $PKG_INSTALL openssh-server || log_error "Failed"
    
    log_info "openssh-server updated!"
}

# Uninstall OpenSSH server
uninstall_openssh() {
    log_info "Uninstalling openssh-server..."
    detect_os
    
    # Disable SSH service (handle both 'ssh' and 'sshd' service names)
    systemctl disable sshd || systemctl disable ssh
    $PKG_UNINSTALL openssh-server || log_error "Failed"
    
    log_info "openssh-server uninstalled!"
}

# Configure OpenSSH server interactively with comprehensive options
configure_openssh() {
    log_info "Configuring OpenSSH server (comprehensive configuration)..."
    
    # Ensure sshd_config.d directory exists
    mkdir -p /etc/ssh/sshd_config.d || log_error "Failed to create /etc/ssh/sshd_config.d"
    
    # Create backup of current config
    BACKUP_FILE="/etc/ssh/sshd_config.d/ulh.conf.backup.$(date +%s)"
    if [[ -f /etc/ssh/sshd_config.d/ulh.conf ]]; then
        cp /etc/ssh/sshd_config.d/ulh.conf "$BACKUP_FILE" || log_warn "Failed to backup existing config"
        log_info "Backed up previous config to $BACKUP_FILE"
    fi
    
    echo "========================================"
    echo "NETWORK & CONNECTIVITY OPTIONS"
    echo "========================================"
    SSH_PORT="${SSH_PORT:-22}"
    SSH_PORT="${SSH_PORT:-22}"
    
    LISTEN_IPv4="${LISTEN_IPv4:-0.0.0.0}"
    LISTEN_IPv4="${LISTEN_IPv4:-0.0.0.0}"
    
    LISTEN_IPv6="${LISTEN_IPv6:-::}"
    LISTEN_IPv6="${LISTEN_IPv6:-::}"
    
    SSH_PROTOCOL="${SSH_PROTOCOL:-2}"
    SSH_PROTOCOL="${SSH_PROTOCOL:-2}"
    
    TCP_KEEPALIVE="${TCP_KEEPALIVE:-yes}"
    TCP_KEEPALIVE="${TCP_KEEPALIVE:-yes}"
    
    ADDRESS_FAMILY="${ADDRESS_FAMILY:-any}"
    ADDRESS_FAMILY="${ADDRESS_FAMILY:-any}"
    
    echo ""
    echo "========================================"
    echo "AUTHENTICATION OPTIONS"
    echo "========================================"
    PASS_AUTH="${PASS_AUTH:-yes}"
    PASS_AUTH="${PASS_AUTH:-yes}"
    
    PUBKEY_AUTH="${PUBKEY_AUTH:-yes}"
    PUBKEY_AUTH="${PUBKEY_AUTH:-yes}"
    
    KERBEROS_AUTH="${KERBEROS_AUTH:-no}"
    KERBEROS_AUTH="${KERBEROS_AUTH:-no}"
    
    GSSAPI_AUTH="${GSSAPI_AUTH:-no}"
    GSSAPI_AUTH="${GSSAPI_AUTH:-no}"
    
    USE_PAM="${USE_PAM:-yes}"
    USE_PAM="${USE_PAM:-yes}"
    
    AUTH_METHODS="${AUTH_METHODS:-}"
    
    MAX_AUTH_TRIES="${MAX_AUTH_TRIES:-6}"
    MAX_AUTH_TRIES="${MAX_AUTH_TRIES:-6}"
    
    echo ""
    echo "========================================"
    echo "ROOT LOGIN & USER RESTRICTIONS"
    echo "========================================"
    PERMIT_ROOT="${PERMIT_ROOT:-prohibit-password}"
    PERMIT_ROOT="${PERMIT_ROOT:-prohibit-password}"
    
    ALLOW_USERS="${ALLOW_USERS:-}"
    
    ALLOW_GROUPS="${ALLOW_GROUPS:-}"
    
    DENY_USERS="${DENY_USERS:-}"
    
    DENY_GROUPS="${DENY_GROUPS:-}"
    
    echo ""
    echo "========================================"
    echo "SECURITY OPTIONS"
    echo "========================================"
    STRICT_MODES="${STRICT_MODES:-yes}"
    STRICT_MODES="${STRICT_MODES:-yes}"
    
    PERMIT_USER_ENV="${PERMIT_USER_ENV:-no}"
    PERMIT_USER_ENV="${PERMIT_USER_ENV:-no}"
    
    PERMIT_EMPTY_PASS="${PERMIT_EMPTY_PASS:-no}"
    PERMIT_EMPTY_PASS="${PERMIT_EMPTY_PASS:-no}"
    
    PERMIT_TUNNEL="${PERMIT_TUNNEL:-no}"
    PERMIT_TUNNEL="${PERMIT_TUNNEL:-no}"
    
    COMPRESSION="${COMPRESSION:-delayed}"
    COMPRESSION="${COMPRESSION:-delayed}"
    
    CLIENT_ALIVE_INTERVAL="${CLIENT_ALIVE_INTERVAL:-300}"
    CLIENT_ALIVE_INTERVAL="${CLIENT_ALIVE_INTERVAL:-300}"
    
    CLIENT_ALIVE_COUNTMAX="${CLIENT_ALIVE_COUNTMAX:-3}"
    CLIENT_ALIVE_COUNTMAX="${CLIENT_ALIVE_COUNTMAX:-3}"
    
    LOGIN_GRACE_TIME="${LOGIN_GRACE_TIME:-120}"
    LOGIN_GRACE_TIME="${LOGIN_GRACE_TIME:-120}"
    
    echo ""
    echo "========================================"
    echo "X11 & FORWARDING OPTIONS"
    echo "========================================"
    X11_FORWARDING="${X11_FORWARDING:-no}"
    X11_FORWARDING="${X11_FORWARDING:-no}"
    
    X11_USE_LOCALHOST="${X11_USE_LOCALHOST:-yes}"
    X11_USE_LOCALHOST="${X11_USE_LOCALHOST:-yes}"
    
    ALLOW_AGENT_FORWARD="${ALLOW_AGENT_FORWARD:-yes}"
    ALLOW_AGENT_FORWARD="${ALLOW_AGENT_FORWARD:-yes}"
    
    ALLOW_TCP_FORWARD="${ALLOW_TCP_FORWARD:-yes}"
    ALLOW_TCP_FORWARD="${ALLOW_TCP_FORWARD:-yes}"
    
    GATEWAY_PORTS="${GATEWAY_PORTS:-no}"
    GATEWAY_PORTS="${GATEWAY_PORTS:-no}"
    
    echo ""
    echo "========================================"
    echo "LOGGING & DISPLAY OPTIONS"
    echo "========================================"
    PRINT_MOTD="${PRINT_MOTD:-yes}"
    PRINT_MOTD="${PRINT_MOTD:-yes}"
    
    PRINT_LASTLOG="${PRINT_LASTLOG:-yes}"
    PRINT_LASTLOG="${PRINT_LASTLOG:-yes}"
    
    LOG_LEVEL="${LOG_LEVEL:-INFO}"
    LOG_LEVEL="${LOG_LEVEL:-INFO}"
    
    BANNER="${BANNER:-}"
    
    SYSLOG_FACILITY="${SYSLOG_FACILITY:-AUTH}"
    SYSLOG_FACILITY="${SYSLOG_FACILITY:-AUTH}"
    
    echo ""
    echo "========================================"
    echo "KEYS & CRYPTOGRAPHY OPTIONS"
    echo "========================================"
    HOST_KEY_ALGORITHMS="${HOST_KEY_ALGORITHMS:-}"
    
    CIPHERS="${CIPHERS:-}"
    
    MACS="${MACS:-}"
    
    KEY_EXCHANGE_ALGOS="${KEY_EXCHANGE_ALGOS:-}"
    
    REKEY_LIMIT="${REKEY_LIMIT:-}"
    
    AUTHORIZED_KEYS_FILE="${AUTHORIZED_KEYS_FILE:-.ssh/authorized_keys}"
    AUTHORIZED_KEYS_FILE="${AUTHORIZED_KEYS_FILE:-.ssh/authorized_keys}"
    
    echo ""
    echo "========================================"
    echo "SUBSYSTEM OPTIONS"
    echo "========================================"
    SFTP_SUBSYSTEM="${SFTP_SUBSYSTEM:-/usr/lib/openssh/sftp-server}"
    SFTP_SUBSYSTEM="${SFTP_SUBSYSTEM:-/usr/lib/openssh/sftp-server}"
    
    # Generate configuration content with all options
    CONFIG_CONTENT="# OpenSSH SSH daemon configuration
# Generated by ulh - Do not edit manually
# Use: ulh openssh config
# Backup: $BACKUP_FILE
# Date: $(date)

# ========== NETWORK & CONNECTIVITY ==========
Port $SSH_PORT
ListenAddress $LISTEN_IPv4"
    
    if [[ -n "$LISTEN_IPv6" ]]; then
        CONFIG_CONTENT+="
ListenAddress $LISTEN_IPv6"
    fi
    
    CONFIG_CONTENT+="
Protocol $SSH_PROTOCOL
AddressFamily $ADDRESS_FAMILY
TCPKeepAlive $TCP_KEEPALIVE

# ========== AUTHENTICATION ==========
PasswordAuthentication $PASS_AUTH
PubkeyAuthentication $PUBKEY_AUTH
KerberosAuthentication $KERBEROS_AUTH
GSSAPIAuthentication $GSSAPI_AUTH
UsePAM $USE_PAM
MaxAuthTries $MAX_AUTH_TRIES"
    
    if [[ -n "$AUTH_METHODS" ]]; then
        CONFIG_CONTENT+="
AuthenticationMethods $AUTH_METHODS"
    fi
    
    CONFIG_CONTENT+="

# ========== ROOT LOGIN & USER RESTRICTIONS ==========
PermitRootLogin $PERMIT_ROOT"
    
    if [[ -n "$ALLOW_USERS" ]]; then
        CONFIG_CONTENT+="
AllowUsers $ALLOW_USERS"
    fi
    
    if [[ -n "$ALLOW_GROUPS" ]]; then
        CONFIG_CONTENT+="
AllowGroups $ALLOW_GROUPS"
    fi
    
    if [[ -n "$DENY_USERS" ]]; then
        CONFIG_CONTENT+="
DenyUsers $DENY_USERS"
    fi
    
    if [[ -n "$DENY_GROUPS" ]]; then
        CONFIG_CONTENT+="
DenyGroups $DENY_GROUPS"
    fi
    
    CONFIG_CONTENT+="

# ========== SECURITY ==========
StrictModes $STRICT_MODES
PermitUserEnvironment $PERMIT_USER_ENV
PermitEmptyPasswords $PERMIT_EMPTY_PASS
PermitTunnel $PERMIT_TUNNEL
Compression $COMPRESSION
ClientAliveInterval $CLIENT_ALIVE_INTERVAL
ClientAliveCountMax $CLIENT_ALIVE_COUNTMAX
LoginGraceTime $LOGIN_GRACE_TIME

# ========== X11 & FORWARDING ==========
X11Forwarding $X11_FORWARDING
X11UseLocalhost $X11_USE_LOCALHOST
AllowAgentForwarding $ALLOW_AGENT_FORWARD
AllowTcpForwarding $ALLOW_TCP_FORWARD
GatewayPorts $GATEWAY_PORTS

# ========== LOGGING & DISPLAY ==========
PrintMotd $PRINT_MOTD
PrintLastLog $PRINT_LASTLOG
LogLevel $LOG_LEVEL
SyslogFacility $SYSLOG_FACILITY"
    
    if [[ -n "$BANNER" ]]; then
        CONFIG_CONTENT+="
Banner $BANNER"
    fi
    
    CONFIG_CONTENT+="

# ========== KEYS & CRYPTOGRAPHY ==========
AuthorizedKeysFile $AUTHORIZED_KEYS_FILE"
    
    if [[ -n "$HOST_KEY_ALGORITHMS" ]]; then
        CONFIG_CONTENT+="
HostKeyAlgorithms $HOST_KEY_ALGORITHMS"
    fi
    
    if [[ -n "$CIPHERS" ]]; then
        CONFIG_CONTENT+="
Ciphers $CIPHERS"
    fi
    
    if [[ -n "$MACS" ]]; then
        CONFIG_CONTENT+="
MACs $MACS"
    fi
    
    if [[ -n "$KEY_EXCHANGE_ALGOS" ]]; then
        CONFIG_CONTENT+="
KeyExchangeAlgorithms $KEY_EXCHANGE_ALGOS"
    fi
    
    if [[ -n "$REKEY_LIMIT" ]]; then
        CONFIG_CONTENT+="
RekeyLimit $REKEY_LIMIT"
    fi
    
    CONFIG_CONTENT+="

# ========== SUBSYSTEM ==========
Subsystem sftp $SFTP_SUBSYSTEM
"
    
    # Write configuration to temporary file first
    TEMP_CONFIG="/tmp/ulh-sshd-config.$$.conf"
    echo "$CONFIG_CONTENT" > "$TEMP_CONFIG"
    
    # Copy to final location
    cp "$TEMP_CONFIG" /etc/ssh/sshd_config.d/ulh.conf || log_error "Failed to write config to /etc/ssh/sshd_config.d/ulh.conf"
    
    # Cleanup temp file
    rm -f "$TEMP_CONFIG"
    
    log_info "Configuration written to /etc/ssh/sshd_config.d/ulh.conf"
    
    # Validate SSH configuration
    if ! sshd -t 2>&1 | tee /tmp/sshd-validation.log; then
        log_error "SSH configuration validation failed. See /tmp/sshd-validation.log for details"
    fi
    
    log_info "SSH configuration validation passed"
    
    # Restart SSH service
    log_info "Restarting SSH service..."
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        log_info "SSH service restarted successfully"
    else
        log_error "Failed to restart SSH service"
    fi
    
    log_info "OpenSSH server configured successfully!"
}

# Fix Xauthority file permissions and generate trust (for X11 forwarding)
fix_xauthority() {
    log_info "Fixing X11 Xauthority configuration..."
    
    # Create .Xauthority file if it doesn't exist
    touch /root/.Xauthority
    
    # Set proper ownership
    chown root:root /root/.Xauthority
    
    # Set restrictive permissions (600 = rw-------)
    chmod 600 /root/.Xauthority
    
    # Generate trusted X11 authority for display :0
    xauth generate :0 . trusted || log_warn "xauth generate completed with warnings"
    
    log_info "X11 Xauthority fixed successfully!"
}

# Route to appropriate action
case "$ACTION" in
    install)
        install_openssh
        ;;
    update)
        update_openssh
        ;;
    uninstall)
        uninstall_openssh
        ;;
    config)
        configure_openssh
        ;;
    fix-xauthority)
        fix_xauthority
        ;;
    *)
        print_usage openssh && exit 1
esac
