#!/bin/bash

# adguard-home - DNS ad-blocking with advanced filtering
# Install, update, uninstall, and configure AdGuard Home for all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

install_adguard() {
    log_info "Installing AdGuard Home..."
    detect_os
    
    # Install dependencies
    $PKG_UPDATE || true
    $PKG_INSTALL curl wget || true
    
    # Download and run official installer
    log_info "Downloading official AdGuard Home installer..."
    if command -v curl &> /dev/null; then
        curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v || log_error "Installation failed"
    elif command -v wget &> /dev/null; then
        wget --no-verbose -O - https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v || log_error "Installation failed"
    else
        log_error "curl or wget required for installation"
    fi
    
    log_info "AdGuard Home installed successfully!"
    log_info "Access web interface: http://localhost:3000/"
    log_info "Default username: admin"
}

update_adguard() {
    log_info "Updating AdGuard Home..."
    detect_os
    
    # Run installer script for update
    log_info "Checking for updates..."
    if command -v curl &> /dev/null; then
        curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v || log_error "Update failed"
    elif command -v wget &> /dev/null; then
        wget --no-verbose -O - https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v || log_error "Update failed"
    else
        log_error "curl or wget required for update"
    fi
    
    # Restart service
    if systemctl is-active --quiet AdGuardHome; then
        systemctl restart AdGuardHome || log_error "Failed to restart AdGuard Home"
    fi
    
    log_info "AdGuard Home updated successfully!"
}

uninstall_adguard() {
    log_warn "Uninstalling AdGuard Home..."
    
    # Confirmation prompt (from CONFIRM parameter or default "no")
    CONFIRM="${CONFIRM:-no}"
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Uninstall cancelled"
        return 0
    fi
    
    # Stop service
    if systemctl is-active --quiet AdGuardHome; then
        systemctl stop AdGuardHome || log_warn "Could not stop service"
    fi
    
    # Keep config (from KEEP_CONFIG parameter or default "yes")
    KEEP_CONFIG="${KEEP_CONFIG:-yes}"
    if [[ "$KEEP_CONFIG" != "no" ]]; then
        log_info "Configuration will be preserved"
    fi
    
    # Run official uninstall if available
    if [[ -f "/opt/AdGuardHome/AdGuardHome" ]]; then
        /opt/AdGuardHome/AdGuardHome -s uninstall || log_warn "Uninstall script had issues"
    fi
    
    log_info "AdGuard Home uninstalled successfully!"
}

configure_adguard() {
    log_info "AdGuard Home configuration"
    log_info ""
    log_info "Web Interface: http://localhost:3000/"
    log_info "API: http://localhost:3000/api/"
    log_info "Default username: admin"
    log_info ""
    
    if systemctl is-active --quiet AdGuardHome; then
        log_info "Service status: RUNNING"
    else
        log_info "Service status: STOPPED"
    fi
    
    log_info ""
    log_info "To access AdGuard Home:"
    log_info "  1. Open http://localhost:3000/ in your browser"
    log_info "  2. Complete initial setup wizard"
    log_info "  3. Set as DNS server (usually on router or client)"
    log_info ""
}

dns_check_adguard() {
    # Traces a hostname through all AdGuard Home DNS sources to find
    # where a wrong/stale answer is coming from (classic "AGH returns
    # wrong IP even after cache flush").
    #
    # Checked sources:
    #   1. /etc/hosts                              (if hostsfile_enabled)
    #   2. AdGuardHome.yaml -> rewrites:
    #   3. AdGuardHome.yaml -> user_rules: ($dnsrewrite)
    #   4. AdGuardHome.yaml -> hostsfile_enabled flag
    #   5. Live resolution via 127.0.0.1

    local hostname="${HOSTNAME:-}"
    local agh_yaml="/opt/AdGuardHome/AdGuardHome.yaml"
    local hosts_file="/etc/hosts"
    local found=0

    if [[ -z "$hostname" ]]; then
        log_error "No hostname provided (HOSTNAME variable empty)"
    fi

    log_info "DNS-Check for: $hostname"
    log_info "=========================================="

    # 1) /etc/hosts
    log_info "[1/5] /etc/hosts"
    if [[ -r "$hosts_file" ]]; then
        local hits
        hits=$(grep -E "[[:space:]]${hostname}([[:space:]]|$)" "$hosts_file" 2>/dev/null || true)
        if [[ -n "$hits" ]]; then
            log_warn "  Match in /etc/hosts:"
            while IFS= read -r line; do log_warn "    $line"; done <<< "$hits"
            found=1
        else
            log_info "  (no match)"
        fi
    else
        log_warn "  $hosts_file not readable"
    fi

    # 2) AdGuardHome.yaml -> rewrites:
    log_info "[2/5] AdGuardHome.yaml -> rewrites"
    if [[ -r "$agh_yaml" ]]; then
        local rewrite_hits
        rewrite_hits=$(awk -v h="$hostname" '
            /^rewrites:/        {in_block=1; next}
            /^[a-z_]+:/ && !/^  / && !/^- / {in_block=0}
            in_block && index($0, h) {print}
        ' "$agh_yaml" 2>/dev/null || true)
        if [[ -n "$rewrite_hits" ]]; then
            log_warn "  Match in rewrites:"
            while IFS= read -r line; do log_warn "    $line"; done <<< "$rewrite_hits"
            found=1
        else
            log_info "  (no match)"
        fi

        # 3) user_rules: ($dnsrewrite)
        log_info "[3/5] AdGuardHome.yaml -> user_rules (\$dnsrewrite)"
        local userrule_hits
        userrule_hits=$(awk -v h="$hostname" '
            /^user_rules:/      {in_block=1; next}
            /^[a-z_]+:/ && !/^  / && !/^- / {in_block=0}
            in_block && index($0, h) {print}
        ' "$agh_yaml" 2>/dev/null || true)
        if [[ -n "$userrule_hits" ]]; then
            log_warn "  Match in user_rules:"
            while IFS= read -r line; do log_warn "    $line"; done <<< "$userrule_hits"
            found=1
        else
            log_info "  (no match)"
        fi

        # 4) hostsfile_enabled flag
        log_info "[4/5] hostsfile_enabled flag"
        local hosts_flag
        hosts_flag=$(grep -E "^[[:space:]]*hostsfile_enabled:" "$agh_yaml" 2>/dev/null | head -1 || true)
        if [[ -n "$hosts_flag" ]]; then
            log_info "  $hosts_flag"
            if echo "$hosts_flag" | grep -qE "true"; then
                log_info "  -> /etc/hosts IS used by AGH"
            else
                log_info "  -> /etc/hosts is NOT used by AGH"
            fi
        else
            log_info "  (flag not set -> default: true = /etc/hosts IS used)"
        fi
    else
        log_warn "  $agh_yaml not readable (AGH not installed or no permission)"
    fi

    # 5) Live resolution via local AGH
    log_info "[5/5] Live resolution via 127.0.0.1"
    if command -v dig &> /dev/null; then
        local answer
        answer=$(dig @127.0.0.1 "$hostname" +short +time=2 +tries=1 2>/dev/null || true)
        if [[ -n "$answer" ]]; then
            log_info "  Answer: $answer"
        else
            log_warn "  (no answer / timeout)"
        fi
    elif command -v nslookup &> /dev/null; then
        nslookup "$hostname" 127.0.0.1 2>/dev/null | grep -E "Address|Name" || log_warn "  (no answer)"
    else
        log_warn "  dig/nslookup not available - install bind-utils or dnsutils"
    fi

    log_info "=========================================="
    if [[ "$found" -eq 1 ]]; then
        log_warn "Static entries found. If live answer is wrong,"
        log_warn "remove the matching entry above and restart AdGuardHome."
    else
        log_info "No static overrides found. Wrong answer (if any)"
        log_info "comes from upstream DNS or AGH runtime cache."
    fi
}

case "$ACTION" in
    install)
        install_adguard
        ;;
    update)
        update_adguard
        ;;
    uninstall)
        uninstall_adguard
        ;;
    config)
        configure_adguard
        ;;
    dns-check)
        dns_check_adguard
        ;;
    *)
        print_usage adguard-home && exit 1
esac
