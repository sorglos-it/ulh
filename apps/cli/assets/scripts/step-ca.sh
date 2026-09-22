#!/bin/bash

# step-ca - Private Certificate Authority
# Install, update, and uninstall step-ca and step-cli for all Linux distributions
# https://smallstep.com/docs/step-ca/installation

set -e
source "$(dirname "$0")/../../classes/bootstrap.sh"
parse_parameters "$1"

# Smallstep package names per distro
get_pkg_names() {
    detect_os
    case "$PKG_TYPE" in
        apk)
            # Alpine uses different package names
            STEP_CLI_PKG="step-cli"
            STEP_CA_PKG="step-certificates"
            ;;
        *)
            STEP_CLI_PKG="step-cli"
            STEP_CA_PKG="step-ca"
            ;;
    esac
}

# Add Smallstep repository
setup_repo() {
    log_info "Setting up Smallstep repository..."

    case "$PKG_TYPE" in
        deb)
            $PKG_INSTALL curl gpg ca-certificates || log_error "Failed to install prerequisites"
            curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg -o /etc/apt/keyrings/smallstep.asc
            cat <<EOF > /etc/apt/sources.list.d/smallstep.sources
Types: deb
URIs: https://packages.smallstep.com/stable/debian
Suites: debs
Components: main
Signed-By: /etc/apt/keyrings/smallstep.asc
EOF
            ;;
        rpm)
            cat <<EOT > /etc/yum.repos.d/smallstep.repo
[smallstep]
name=Smallstep
baseurl=https://packages.smallstep.com/stable/fedora/
enabled=1
repo_gpgcheck=0
gpgcheck=1
gpgkey=https://packages.smallstep.com/keys/smallstep-0x889B19391F774443.gpg
EOT
            ;;
        pacman|apk)
            # Arch and Alpine have community packages, no extra repo needed
            ;;
        zypper)
            log_warn "No official SUSE repo - falling back to binary install"
            install_binary
            return 1
            ;;
    esac
    log_info "Repository configured"
}

# Fallback: install from binary tarballs
install_binary() {
    log_info "Installing from binary..."
    local arch=$(uname -m)
    local step_arch=""

    case "$arch" in
        x86_64)  step_arch="amd64" ;;
        aarch64) step_arch="arm64" ;;
        armv7l)  step_arch="armv7" ;;
        armv6l)  step_arch="armv6" ;;
        *) log_error "Unsupported architecture: $arch" ;;
    esac

    # Install step-cli
    log_info "Downloading step-cli..."
    curl -LO "https://dl.smallstep.com/cli/docs-ca-install/latest/step_linux_${step_arch}.tar.gz" || log_error "Failed to download step-cli"
    tar -xf "step_linux_${step_arch}.tar.gz"
    cp "step_linux_${step_arch}/bin/step" /usr/bin/
    rm -rf "step_linux_${step_arch}" "step_linux_${step_arch}.tar.gz"

    # Install step-ca
    log_info "Downloading step-ca..."
    curl -LO "https://dl.smallstep.com/certificates/docs-ca-install/latest/step-ca_linux_${step_arch}.tar.gz" || log_error "Failed to download step-ca"
    tar -xf "step-ca_linux_${step_arch}.tar.gz"
    cp "step-ca_linux_${step_arch}/step-ca" /usr/bin/
    rm -rf "step-ca_linux_${step_arch}" "step-ca_linux_${step_arch}.tar.gz"

    log_info "Binary install complete"
}

install_step_ca() {
    log_info "Installing step-ca..."
    get_pkg_names

    # Check if already installed
    if command -v step-ca &>/dev/null; then
        log_info "step-ca is already installed"
        step-ca version 2>/dev/null || true
        return 0
    fi

    $PKG_UPDATE || true

    # Try package manager first
    case "$PKG_TYPE" in
        deb|rpm)
            setup_repo
            $PKG_UPDATE || true
            $PKG_INSTALL "$STEP_CLI_PKG" "$STEP_CA_PKG" || {
                log_warn "Package install failed, trying binary..."
                install_binary
            }
            ;;
        pacman)
            $PKG_INSTALL "$STEP_CLI_PKG" "$STEP_CA_PKG" || log_error "Failed to install step-ca"
            ;;
        apk)
            $PKG_INSTALL "$STEP_CLI_PKG" "$STEP_CA_PKG" || log_error "Failed to install step-ca"
            ;;
        *)
            install_binary
            ;;
    esac

    # Verify
    if command -v step-ca &>/dev/null; then
        log_info "step-ca installed successfully!"
        step-ca version 2>/dev/null || true
    else
        log_error "step-ca installation failed"
    fi

    if command -v step &>/dev/null; then
        log_info "step-cli installed successfully!"
        step version 2>/dev/null || true
    fi
}

update_step_ca() {
    log_info "Updating step-ca..."
    get_pkg_names

    if ! command -v step-ca &>/dev/null; then
        log_error "step-ca is not installed"
    fi

    $PKG_UPDATE || true

    case "$PKG_TYPE" in
        deb)
            $PKG_INSTALL --only-upgrade "$STEP_CLI_PKG" "$STEP_CA_PKG" 2>/dev/null || \
            $PKG_INSTALL "$STEP_CLI_PKG" "$STEP_CA_PKG" || log_error "Failed to update"
            ;;
        rpm)
            dnf upgrade -y "$STEP_CLI_PKG" "$STEP_CA_PKG" || log_error "Failed to update"
            ;;
        pacman)
            $PKG_INSTALL "$STEP_CLI_PKG" "$STEP_CA_PKG" || log_error "Failed to update"
            ;;
        apk)
            apk upgrade "$STEP_CLI_PKG" "$STEP_CA_PKG" || log_error "Failed to update"
            ;;
        *)
            # Binary: reinstall latest
            install_binary
            ;;
    esac

    log_info "step-ca updated successfully!"
    step-ca version 2>/dev/null || true
    step version 2>/dev/null || true
}

uninstall_step_ca() {
    log_info "Uninstalling step-ca..."
    get_pkg_names

    if ! command -v step-ca &>/dev/null && ! command -v step &>/dev/null; then
        log_error "step-ca is not installed"
    fi

    # Stop service if running
    if systemctl is-active --quiet step-ca 2>/dev/null; then
        log_info "Stopping step-ca service..."
        systemctl stop step-ca || true
        systemctl disable step-ca || true
    fi

    case "$PKG_TYPE" in
        deb)
            dpkg -r "$STEP_CA_PKG" "$STEP_CLI_PKG" 2>/dev/null || true
            ;;
        rpm)
            dnf remove -y "$STEP_CA_PKG" "$STEP_CLI_PKG" 2>/dev/null || true
            ;;
        pacman)
            pacman -R --noconfirm "$STEP_CA_PKG" "$STEP_CLI_PKG" 2>/dev/null || true
            ;;
        apk)
            apk del "$STEP_CA_PKG" "$STEP_CLI_PKG" 2>/dev/null || true
            ;;
        *)
            # Binary install cleanup
            rm -f /usr/bin/step /usr/bin/step-ca
            ;;
    esac

    # Remove repo if present
    rm -f /etc/apt/sources.list.d/smallstep.sources 2>/dev/null
    rm -f /etc/apt/keyrings/smallstep.asc 2>/dev/null
    rm -f /etc/yum.repos.d/smallstep.repo 2>/dev/null

    log_info "step-ca uninstalled successfully!"
    log_warn "Config directory ~/.step was NOT removed. Delete manually if needed."
}

case "$ACTION" in
    install)   install_step_ca ;;
    update)    update_step_ca ;;
    uninstall) uninstall_step_ca ;;
    *)         print_usage step-ca && exit 1 ;;
esac
