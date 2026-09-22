#!/bin/bash

# linux - Linux System Configuration Script
# Manage network, DNS, hostname, users, and groups on Linux systems

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

configure_network() {
    log_info "Configuring network..."
    
    [[ -z "$INTERFACE" ]] && log_error "INTERFACE not set"
    [[ -z "$DHCP_MODE" ]] && log_error "DHCP_MODE not set"
    
    if [[ "$DHCP_MODE" == "yes" ]]; then
        log_info "Setting $INTERFACE to DHCP..."
        
        # Debian/Ubuntu
        if [[ -f /etc/netplan/00-installer-config.yaml ]]; then
            log_info "Using netplan (Debian/Ubuntu)..."
            cat > /tmp/netplan.yaml <<EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: true
      dhcp6: true
EOF
            cp /tmp/netplan.yaml /etc/netplan/00-installer-config.yaml
            netplan apply
        # Red Hat/CentOS
        elif [[ -f /etc/sysconfig/network-scripts/ifcfg-$INTERFACE ]]; then
            log_info "Using ifcfg-* (Red Hat/CentOS)..."
            tee /etc/sysconfig/network-scripts/ifcfg-$INTERFACE > /dev/null <<EOF
TYPE=Ethernet
BOOTPROTO=dhcp
NAME=$INTERFACE
DEVICE=$INTERFACE
ONBOOT=yes
EOF
            systemctl restart network
        fi
    else
        [[ -z "$IP_ADDRESS" ]] && log_error "IP_ADDRESS not set for static configuration"
        [[ -z "$GATEWAY" ]] && log_error "GATEWAY not set for static configuration"
        
        log_info "Setting $INTERFACE to static IP: $IP_ADDRESS..."
        
        # Debian/Ubuntu
        if [[ -f /etc/netplan/00-installer-config.yaml ]]; then
            log_info "Using netplan (Debian/Ubuntu)..."
            local ipv6_config=""
            if [[ -n "$IPV6_ADDRESS" ]]; then
                ipv6_config="      addresses: [$IP_ADDRESS, $IPV6_ADDRESS]
      gateway6: ${IPV6_GATEWAY:-}"
            else
                ipv6_config="      addresses: [$IP_ADDRESS]"
            fi
            
            cat > /tmp/netplan.yaml <<EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: false
      dhcp6: false
$ipv6_config
      gateway4: $GATEWAY
      nameservers:
        addresses: [${DNS_SERVER:-8.8.8.8}]
EOF
            cp /tmp/netplan.yaml /etc/netplan/00-installer-config.yaml
            netplan apply
        # Red Hat/CentOS
        elif [[ -f /etc/sysconfig/network-scripts/ifcfg-$INTERFACE ]]; then
            log_info "Using ifcfg-* (Red Hat/CentOS)..."
            local ip="${IP_ADDRESS%/*}"
            local prefix="${IP_ADDRESS#*/}"
            tee /etc/sysconfig/network-scripts/ifcfg-$INTERFACE > /dev/null <<EOF
TYPE=Ethernet
BOOTPROTO=static
NAME=$INTERFACE
DEVICE=$INTERFACE
ONBOOT=yes
IPADDR=$ip
PREFIX=$prefix
GATEWAY=$GATEWAY
DNS1=${DNS_SERVER:-8.8.8.8}
IPV6INIT=yes
EOF
            if [[ -n "$IPV6_ADDRESS" ]]; then
                echo "IPV6ADDR=$IPV6_ADDRESS" | tee -a /etc/sysconfig/network-scripts/ifcfg-$INTERFACE >/dev/null
                if [[ -n "$IPV6_GATEWAY" ]]; then
                    echo "IPV6_DEFAULTGW=$IPV6_GATEWAY" | tee -a /etc/sysconfig/network-scripts/ifcfg-$INTERFACE >/dev/null
                fi
            fi
            systemctl restart network
        else
            log_error "Network configuration method not found. Supported: netplan, ifcfg-*"
        fi
    fi
    
    log_info "Network configuration updated!"
}

configure_dns() {
    log_info "Configuring DNS..."
    
    [[ -z "$DNS_SERVER" ]] && log_error "DNS_SERVER not set"
    
    log_info "Setting DNS to: $DNS_SERVER..."
    
    # Systemd-resolved (modern)
    if command -v systemctl &>/dev/null && systemctl is-active --quiet systemd-resolved; then
        mkdir -p /etc/systemd/resolved.conf.d/
        tee /etc/systemd/resolved.conf.d/custom-dns.conf > /dev/null <<EOF
[Resolve]
DNS=$DNS_SERVER
FallbackDNS=8.8.8.8 8.8.4.4
EOF
        systemctl restart systemd-resolved
    # /etc/resolv.conf (fallback)
    else
        echo "nameserver $DNS_SERVER" | tee /etc/resolv.conf >/dev/null
        echo "nameserver 8.8.8.8" | tee -a /etc/resolv.conf >/dev/null
    fi
    
    log_info "DNS configured successfully!"
}

change_hostname() {
    log_info "Changing hostname..."
    
    [[ -z "$HOSTNAME" ]] && log_error "HOSTNAME not set"
    
    log_info "Setting hostname to: $HOSTNAME..."
    hostnamectl set-hostname "$HOSTNAME" || hostname "$HOSTNAME"
    
    # Update /etc/hosts
    sed -i "s/127.0.1.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts || echo "127.0.1.1 $HOSTNAME" | tee -a /etc/hosts >/dev/null
    
    log_info "Hostname changed to: $HOSTNAME"
}

add_user() {
    log_info "Adding user..."
    
    [[ -z "$USERNAME" ]] && log_error "USERNAME not set"
    
    local shell="${SHELL:-/bin/bash}"
    
    log_info "Creating user: $USERNAME (shell: $shell)..."
    
    if useradd -m -s "$shell" "$USERNAME" 2>/dev/null; then
        log_info "User $USERNAME created successfully!"
    else
        log_warn "User $USERNAME might already exist"
    fi
}

delete_user() {
    log_info "Deleting user..."
    
    [[ -z "$USERNAME" ]] && log_error "USERNAME not set"
    
    log_info "Removing user: $USERNAME..."
    
    if userdel -r "$USERNAME" 2>/dev/null; then
        log_info "User $USERNAME deleted successfully!"
    else
        log_warn "Failed to delete user $USERNAME"
    fi
}

change_password() {
    log_info "Changing password..."
    
    [[ -z "$USERNAME" ]] && log_error "USERNAME not set"
    [[ -z "$PASSWORD" ]] && log_error "PASSWORD not set"
    
    log_info "Setting password for user: $USERNAME..."
    
    echo "$USERNAME:$PASSWORD" | chpasswd || log_error "Failed to change password"
    
    log_info "Password changed for user: $USERNAME"
}

create_group() {
    log_info "Creating group..."
    
    [[ -z "$GROUPNAME" ]] && log_error "GROUPNAME not set"
    
    log_info "Creating group: $GROUPNAME..."
    
    if groupadd "$GROUPNAME" 2>/dev/null; then
        log_info "Group $GROUPNAME created successfully!"
    else
        log_warn "Group $GROUPNAME might already exist"
    fi
}

add_user_to_group() {
    log_info "Adding user to group..."
    
    [[ -z "$USERNAME" ]] && log_error "USERNAME not set"
    [[ -z "$GROUPNAME" ]] && log_error "GROUPNAME not set"
    
    log_info "Adding user $USERNAME to group $GROUPNAME..."
    
    if usermod -aG "$GROUPNAME" "$USERNAME"; then
        log_info "User $USERNAME added to group $GROUPNAME!"
    else
        log_error "Failed to add user to group"
    fi
}

update_ca_cert() {
    log_info "Updating CA certificate..."
    
    [[ -z "$SERVER" ]] && log_error "SERVER variable not set"
    detect_os
    
    log_info "Fetching CA certificate from $SERVER..."
    
    if ! echo | openssl s_client -connect "$SERVER:443" -showcerts 2>/dev/null | openssl x509 -outform PEM | tee $CA_PATH/ca-$SERVER.crt > /dev/null; then
        log_error "Failed to fetch and install certificate from $SERVER"
    fi
    
    log_info "Certificate installed to system CA store"
    
    log_info "Updating CA certificate database..."
    if ! $CA_UPDATE; then
        log_error "Failed to update CA certificates"
    fi
    
    log_info "CA certificate from $SERVER installed successfully!"
}

install_compression() {
    log_info "Installing zip and unzip..."
    detect_os
    $PKG_UPDATE || true
    $PKG_INSTALL zip unzip || log_error "Failed to install packages"
    log_info "zip and unzip installed successfully!"
}

uninstall_compression() {
    log_info "Uninstalling zip and unzip..."
    detect_os
    $PKG_UNINSTALL zip unzip || log_error "Failed to uninstall packages"
    log_info "zip and unzip uninstalled successfully!"
}

case "$ACTION" in
    network)
        configure_network
        ;;
    
    dns)
        configure_dns
        ;;
    
    hostname)
        change_hostname
        ;;
    
    user-add)
        add_user
        ;;
    
    user-delete)
        delete_user
        ;;
    
    user-password)
        change_password
        ;;
    
    group-create)
        create_group
        ;;
    
    user-to-group)
        add_user_to_group
        ;;
    
    ca-cert)
        update_ca_cert
        ;;
    
    install-zip)
        install_compression
        ;;
    
    uninstall-zip)
        uninstall_compression
        ;;
    
    *)
        print_usage linux && exit 1
esac
