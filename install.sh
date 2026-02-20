#!/bin/bash

# ulh Installation Script
# Works on all Linux distributions (Debian, Red Hat, Arch, SUSE, Alpine)

set -euo pipefail

# ============================================================================
# Detect OS and Package Manager
# ============================================================================

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_DISTRO="${ID,,}"
        OS_VERSION="${VERSION_ID:-unknown}"
    else
        echo "❌ Cannot detect OS (no /etc/os-release found)"
        exit 1
    fi
    
    case "$OS_DISTRO" in
        ubuntu|debian|raspbian|linuxmint|pop)
            OS_FAMILY="debian"
            PKG_UPDATE="apt-get update"
            PKG_INSTALL="apt-get install -y"
            ;;
        fedora|rhel|centos|rocky|alma)
            OS_FAMILY="redhat"
            PKG_UPDATE="dnf check-update || true"
            PKG_INSTALL="dnf install -y"
            ;;
        arch|manjaro|endeavouros)
            OS_FAMILY="arch"
            PKG_UPDATE="pacman -Sy"
            PKG_INSTALL="pacman -S --noconfirm"
            ;;
        opensuse*|sles)
            OS_FAMILY="suse"
            PKG_UPDATE="zypper refresh"
            PKG_INSTALL="zypper install -y"
            ;;
        alpine)
            OS_FAMILY="alpine"
            PKG_UPDATE="apk update"
            PKG_INSTALL="apk add"
            ;;
        *)
            echo "❌ Unsupported distribution: $OS_DISTRO"
            exit 1
            ;;
    esac
}

# ============================================================================
# Main Installation
# ============================================================================

# Use sudo only if not root
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "🔍 Detecting OS..."
detect_os
echo "✓ Detected: $OS_DISTRO ($OS_FAMILY)"
echo ""

echo "📦 Installing dependencies..."
if ! $SUDO $PKG_UPDATE; then
    echo "❌ Failed to update package lists"
    exit 1
fi

if ! $SUDO $PKG_INSTALL git; then
    echo "❌ Failed to install git"
    exit 1
fi

echo "📥 Setting up ulh..."
cd ~

# Check if ulh directory already exists
if [[ -d "ulh" ]]; then
    echo "  (ulh directory exists, pulling latest updates...)"
    cd ulh
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true
else
    echo "  Cloning from GitHub..."
    if ! git clone https://github.com/sorglos-it/ulh.git; then
        echo "❌ Failed to clone ulh"
        exit 1
    fi
    cd ulh
fi

echo "✅ ulh installed successfully!"
echo ""
echo "To start ulh, run:"
echo "  cd ~/ulh && bash ulh.sh"
