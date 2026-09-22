#!/bin/bash
# ulh Installation Script - installs ulh into ~/ulh, or updates it there.
# Works on all Linux distributions (Debian, Red Hat, Arch, SUSE, Alpine)
#
# One-liner:
#   wget -qO - https://raw.githubusercontent.com/sorglos-it/ulh/main/tools/install.sh | bash
# Needs git - installs it with the package manager if it is missing.

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
            PKG_UPDATE="dnf makecache"
            PKG_INSTALL="dnf install -y"
            ;;
        arch|archarm|manjaro|endeavouros)
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

main() {
    local dir="${HOME}/ulh"

    # Use sudo only if not root
    local SUDO=""
    [[ $EUID -eq 0 ]] || SUDO="sudo"

    if ! command -v git >/dev/null 2>&1; then
        echo "🔍 Detecting OS..."
        detect_os
        echo "✓ Detected: $OS_DISTRO ($OS_FAMILY)"
        echo ""

        echo "📦 Installing git..."
        if ! $SUDO $PKG_UPDATE; then
            echo "❌ Failed to update package lists"
            exit 1
        fi
        if ! $SUDO $PKG_INSTALL git; then
            echo "❌ Failed to install git"
            exit 1
        fi
    fi

    echo "📥 Setting up ulh..."
    if [[ -d "${dir}/.git" ]]; then
        echo "  (ulh directory exists, pulling latest updates...)"
        git -C "$dir" -c core.fileMode=false pull --ff-only origin main 2>/dev/null ||
            git -C "$dir" -c core.fileMode=false pull --ff-only origin master 2>/dev/null ||
            echo "  ⚠ Update failed - ulh tries again on its next start"
    elif [[ -e "$dir" ]]; then
        echo "❌ ${dir} exists but is no git clone of ulh - move it away and run this again"
        exit 1
    else
        echo "  Cloning from GitHub..."
        if ! git clone https://github.com/sorglos-it/ulh.git "$dir"; then
            echo "❌ Failed to clone ulh"
            exit 1
        fi
    fi

    echo "✅ ulh installed successfully!"
    echo ""
    echo "To start ulh, run:"
    echo "  bash ~/ulh/apps/cli/ulh.sh"
}

main "$@"
