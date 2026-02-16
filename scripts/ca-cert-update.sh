#!/bin/bash

# CA Certificate Update Script
# Downloads and installs CA certificates from a server

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

case "$ACTION" in
    update)
        [[ -z "$SERVER" ]] && log_error "SERVER variable not set"
        
        log_info "Fetching CA certificate from $SERVER..."
        
        # Download certificate
        if ! echo | openssl s_client -connect "$SERVER:443" -showcerts 2>/dev/null | openssl x509 -outform PEM > /home/ca.crt; then
            log_error "Failed to fetch certificate from $SERVER"
        fi
        
        log_info "Certificate downloaded to /home/ca.crt"
        
        log_info "Installing certificate to system CA store..."
        if ! sudo cp /home/ca.crt /usr/local/share/ca-certificates/ca-$SERVER.crt; then
            log_error "Failed to copy certificate to CA store"
        fi
        
        log_info "Updating CA certificate database..."
        if ! sudo update-ca-certificates; then
            log_error "Failed to update CA certificates"
        fi
        
        log_info "CA certificate from $SERVER installed successfully!"
        ;;
    
    *)
        log_error "Unknown action: $ACTION"
        echo "Usage: ca-cert-update.sh update,SERVER=server.name"
        exit 1
        ;;
esac
