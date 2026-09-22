#!/bin/bash

# portainer - Portainer Docker Management UI
# Install, update, and manage Portainer Docker management platform

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed! Please install Docker first."
    fi
    
    if ! systemctl is-active --quiet docker; then
        log_error "Docker service is not running! Start Docker first: systemctl start docker"
    fi
}

install_portainer() {
    log_info "Installing Portainer (Main)..."
    
    check_docker
    
    # Use provided ports or defaults
    local edge_port="${EDGE_PORT:-8000}"
    local web_port="${WEB_PORT:-9000}"
    
    log_info "Using Edge Agent port: $edge_port, Web UI port: $web_port"
    
    log_info "Checking if Portainer is already running..."
    if docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
        log_warn "Portainer container already exists. Removing old container..."
        docker stop portainer 2>/dev/null || true
        docker rm portainer 2>/dev/null || true
    fi
    
    log_info "Creating Docker volume for Portainer data..."
    docker volume create portainer_data 2>/dev/null || log_warn "Volume already exists"
    
    log_info "Pulling Portainer image..."
    docker pull portainer/portainer-ce:latest || log_error "Failed to pull Portainer image"
    
    log_info "Starting Portainer container..."
    docker run -d \
        -p ${edge_port}:8000 \
        -p ${web_port}:9000 \
        --name=portainer \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest || log_error "Failed to start Portainer"
    
    log_info "Waiting for Portainer to be ready..."
    sleep 5
    
    if docker ps --format '{{.Names}}' | grep -q "^portainer$"; then
        log_info "Portainer installed and running successfully!"
        log_info "Access Portainer Web UI at: http://localhost:${web_port}"
        log_info "Edge Agent listening on port: $edge_port"
        log_info "Initial setup will ask you to create an admin account"
    else
        log_error "Portainer container failed to start"
    fi
}

update_portainer() {
    log_info "Updating Portainer..."
    
    check_docker
    
    if ! docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
        log_error "Portainer container not found. Run install first."
    fi
    
    # Use provided ports or defaults
    local edge_port="${EDGE_PORT:-8000}"
    local web_port="${WEB_PORT:-9000}"
    
    log_info "Using Edge Agent port: $edge_port, Web UI port: $web_port"
    
    log_info "Stopping Portainer..."
    docker stop portainer || log_error "Failed to stop Portainer"
    
    log_info "Removing old Portainer container..."
    docker rm portainer || log_error "Failed to remove Portainer"
    
    log_info "Pulling latest Portainer image..."
    docker pull portainer/portainer-ce:latest || log_error "Failed to pull latest image"
    
    log_info "Starting Portainer with updated image..."
    docker run -d \
        -p ${edge_port}:8000 \
        -p ${web_port}:9000 \
        --name=portainer \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest || log_error "Failed to start Portainer"
    
    log_info "Waiting for Portainer to be ready..."
    sleep 5
    
    log_info "Portainer updated successfully!"
}

uninstall_portainer() {
    log_warn "Uninstalling Portainer..."
    log_warn "DELETE_DATA: $DELETE_DATA"
    
    check_docker
    
    if ! docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
        log_warn "Portainer container not found"
    else
        log_info "Stopping Portainer..."
        docker stop portainer || log_warn "Failed to stop Portainer"
        
        log_info "Removing Portainer container..."
        docker rm portainer || log_warn "Failed to remove Portainer"
    fi
    
    if [[ "$DELETE_DATA" == "yes" ]]; then
        log_info "Removing Portainer data volume..."
        docker volume rm portainer_data 2>/dev/null || log_warn "Could not remove volume"
        log_info "Portainer completely uninstalled (data deleted)!"
    else
        log_info "Portainer uninstalled (data preserved in portainer_data volume)!"
    fi
}


check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed! Please install Docker first."
    fi
    
    if ! systemctl is-active --quiet docker; then
        log_error "Docker service is not running! Start Docker first: systemctl start docker"
    fi
}

install_portainer_agent() {
    log_info "Installing Portainer Agent..."
    
    check_docker
    
    # Use provided port or default
    local agent_port="${AGENT_PORT:-9001}"
    
    log_info "Using Agent port: $agent_port"
    
    log_info "Checking if Portainer Agent is already running..."
    if docker ps -a --format '{{.Names}}' | grep -q "^portainer_agent$"; then
        log_warn "Portainer Agent container already exists. Removing old container..."
        docker stop portainer_agent 2>/dev/null || true
        docker rm portainer_agent 2>/dev/null || true
    fi
    
    log_info "Pulling Portainer Agent image..."
    docker pull portainer/agent:latest || log_error "Failed to pull Portainer Agent image"
    
    log_info "Starting Portainer Agent container..."
    docker run -d \
        -p ${agent_port}:9001 \
        --name portainer_agent \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /var/lib/docker/volumes:/var/lib/docker/volumes \
        portainer/agent:latest || log_error "Failed to start Portainer Agent"
    
    log_info "Waiting for Agent to be ready..."
    sleep 3
    
    if docker ps --format '{{.Names}}' | grep -q "^portainer_agent$"; then
        log_info "Portainer Agent installed and running successfully!"
        log_info "Agent listening on port $agent_port"
        log_info "Connect this agent to your Portainer main via: Environment → Add environment → Agent → http://<this-ip>:${agent_port}"
    else
        log_error "Portainer Agent container failed to start"
    fi
}

update_portainer_agent() {
    log_info "Updating Portainer Agent..."
    
    check_docker
    
    if ! docker ps -a --format '{{.Names}}' | grep -q "^portainer_agent$"; then
        log_error "Portainer Agent container not found. Run install first."
    fi
    
    # Use provided port or default
    local agent_port="${AGENT_PORT:-9001}"
    
    log_info "Using Agent port: $agent_port"
    
    log_info "Stopping Portainer Agent..."
    docker stop portainer_agent || log_error "Failed to stop Agent"
    
    log_info "Removing old Portainer Agent container..."
    docker rm portainer_agent || log_error "Failed to remove Agent"
    
    log_info "Pulling latest Portainer Agent image..."
    docker pull portainer/agent:latest || log_error "Failed to pull latest image"
    
    log_info "Starting Portainer Agent with updated image..."
    docker run -d \
        -p ${agent_port}:9001 \
        --name portainer_agent \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /var/lib/docker/volumes:/var/lib/docker/volumes \
        portainer/agent:latest || log_error "Failed to start Agent"
    
    log_info "Waiting for Agent to be ready..."
    sleep 3
    
    log_info "Portainer Agent updated successfully!"
}

uninstall_portainer_agent() {
    log_warn "Uninstalling Portainer Agent..."
    log_warn "DELETE_DATA: $DELETE_DATA"
    
    check_docker
    
    if ! docker ps -a --format '{{.Names}}' | grep -q "^portainer_agent$"; then
        log_warn "Portainer Agent container not found"
    else
        log_info "Stopping Portainer Agent..."
        docker stop portainer_agent || log_warn "Failed to stop Agent"
        
        log_info "Removing Portainer Agent container..."
        docker rm portainer_agent || log_warn "Failed to remove Agent"
    fi
    
    if [[ "$DELETE_DATA" == "yes" ]]; then
        log_info "Note: Agent doesn't use persistent data volumes"
        log_info "Portainer Agent completely uninstalled!"
    else
        log_info "Portainer Agent uninstalled!"
    fi
}

case "$ACTION" in
    install)
        install_portainer
        ;;
    
    update)
        update_portainer
        ;;
    
    uninstall)
        uninstall_portainer
        ;;
        
    client-install)
        install_portainer_agent
        ;;
    
    client-update)
        update_portainer_agent
        ;;
    
    client-uninstall)
        uninstall_portainer_agent
        ;;
    
    
    *)
        print_usage portainer && exit 1
        


esac
