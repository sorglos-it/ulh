#!/bin/bash

# docker-compose - Multi-container orchestration with Docker Compose
# Install, update, uninstall, and configure Docker Compose for all Linux distributions

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

# Check if Docker is installed (required dependency)
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first before installing Docker Compose."
    fi
    log_info "Docker found: $(docker --version)"
}

# Get the latest docker-compose version from GitHub
get_latest_version() {
    # Try to get the latest release tag from GitHub API
    local latest=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
    
    if [[ -z "$latest" ]]; then
        # Fallback to a recent stable version if API fails
        latest="2.24.0"
    fi
    
    echo "$latest"
}

# Get system architecture
get_arch() {
    case "$(uname -m)" in
        x86_64)
            echo "x86_64"
            ;;
        aarch64)
            echo "aarch64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            echo "x86_64"  # Default fallback
            ;;
    esac
}

install_docker_compose() {
    log_info "Installing Docker Compose..."
    detect_os
    check_docker
    
    local version=$(get_latest_version)
    local arch=$(get_arch)
    local download_url="https://github.com/docker/compose/releases/download/v${version}/docker-compose-$(uname -s)-${arch}"
    
    log_info "Downloading Docker Compose v${version}..."
    
    # Try binary download first
    if curl -fsSL "$download_url" -o /tmp/docker-compose; then
        log_info "Binary download successful"
        mv /tmp/docker-compose /usr/local/bin/docker-compose || log_error "Failed to move docker-compose to /usr/local/bin"
        chmod +x /usr/local/bin/docker-compose || log_error "Failed to make docker-compose executable"
        
        log_info "Docker Compose installed successfully!"
        /usr/local/bin/docker-compose --version
    else
        # Fallback to distro package manager
        log_info "Binary download failed, trying distro package manager..."
        $PKG_UPDATE || true
        $PKG_INSTALL "$DISTRO_PKG_NAME" || log_error "Failed to install Docker Compose via package manager"
        
        log_info "Docker Compose installed successfully!"
        docker-compose --version
    fi
}

update_docker_compose() {
    log_info "Updating Docker Compose..."
    detect_os
    
    if [[ -f /usr/local/bin/docker-compose ]]; then
        # Update binary installation
        local version=$(get_latest_version)
        local arch=$(get_arch)
        local download_url="https://github.com/docker/compose/releases/download/v${version}/docker-compose-$(uname -s)-${arch}"
        
        log_info "Downloading Docker Compose v${version}..."
        
        if curl -fsSL "$download_url" -o /tmp/docker-compose; then
            mv /tmp/docker-compose /usr/local/bin/docker-compose || log_error "Failed to update docker-compose binary"
            chmod +x /usr/local/bin/docker-compose || log_error "Failed to make docker-compose executable"
            
            log_info "Docker Compose updated successfully!"
            /usr/local/bin/docker-compose --version
        else
            log_error "Failed to download Docker Compose binary"
        fi
    else
        # Update package manager installation
        log_info "Docker Compose installed via package manager, updating..."
        $PKG_UPDATE || true
        $PKG_INSTALL "$DISTRO_PKG_NAME" || log_error "Failed to update Docker Compose"
        
        log_info "Docker Compose updated successfully!"
        docker-compose --version
    fi
}

uninstall_docker_compose() {
    log_info "Uninstalling Docker Compose..."
    
    # Confirm before uninstalling (from CONFIRM parameter or default "no")
    CONFIRM="${CONFIRM:-no}"
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Uninstall cancelled"
        exit 0
    fi
    
    if [[ -f /usr/local/bin/docker-compose ]]; then
        rm -f /usr/local/bin/docker-compose || log_error "Failed to remove docker-compose binary"
        log_info "Docker Compose binary removed"
    fi
    
    # Also try to remove package manager installation
    detect_os
    $PKG_UNINSTALL "$DISTRO_PKG_NAME" 2>/dev/null || true
    
    log_info "Docker Compose uninstalled successfully!"
    
    # Verify removal
    if ! command -v docker-compose &> /dev/null; then
        log_info "Verification: Docker Compose not found (as expected)"
    fi
}

configure_docker_compose() {
    log_info "Docker Compose configuration and information"
    
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose version:"
        docker-compose --version
        
        log_info "Installation path:"
        which docker-compose
        
        log_info "Basic usage examples:"
        echo "  docker-compose up -d              # Start containers in detached mode"
        echo "  docker-compose ps                 # List running containers"
        echo "  docker-compose logs -f            # View container logs"
        echo "  docker-compose down               # Stop and remove containers"
        echo "  docker-compose exec <service> sh  # Execute command in service"
        echo "  docker-compose build              # Build custom images"
        
        log_info "For more information, run: docker-compose --help"
    else
        log_error "Docker Compose is not installed"
    fi
}

case "$ACTION" in
    install)
        install_docker_compose
        ;;
    update)
        update_docker_compose
        ;;
    uninstall)
        uninstall_docker_compose
        ;;
    config)
        configure_docker_compose
        ;;
    *)
        print_usage docker-compose && exit 1
        ;;
esac
