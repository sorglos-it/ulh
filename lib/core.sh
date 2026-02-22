#!/bin/bash
# ulh - Core Library: Colors, OS detection, debug logging, utilities

# Load colors from centralized library
source "$(dirname "$0")/colors.sh"

DEBUG=${DEBUG:-false}

# Debug logging - only output if DEBUG=true
debug() {
    [[ "$DEBUG" == true ]] && echo "DEBUG: $*" >&2
}

# ============================================================================
# Output Functions - All write to stderr to keep stdout clean
# ============================================================================

msg()     { printf "%b\n" "$*" >&2; }
msg_ok()  { msg "${C_GREEN}✓ $*${C_RESET}"; }
msg_err() { msg "${C_RED}✗ $*${C_RESET}"; }
msg_warn(){ msg "${C_YELLOW}⚠ $*${C_RESET}"; }
msg_info(){ msg "${C_CYAN}ℹ $*${C_RESET}"; }
die()     { msg_err "$*"; exit 1; }

# ============================================================================
# Formatting Functions
# ============================================================================

header() {
    local text="$*" w=60 pad=$(( (60 - ${#1} - 2) / 2 ))
    echo "" >&2
    printf "%b" "$C_BOLD_CYAN" >&2
    printf '═%.0s' $(seq 1 $w) >&2; echo "" >&2
    printf "%*s%s%*s\n" $pad "" "$text" $pad "" >&2
    printf '═%.0s' $(seq 1 $w) >&2
    printf "%b\n\n" "$C_RESET" >&2
}

separator() { printf "%78s\n" | tr ' ' '-'; }

# ============================================================================
# Operating System Detection
# ============================================================================

declare -g OS_FAMILY="" OS_DISTRO="" OS_VERSION=""

detect_os() {
    [[ "$(uname -s)" != "Linux" ]] && { msg_err "Linux only"; return 1; }
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_DISTRO="${ID,,}"
        OS_VERSION="${VERSION_ID:-unknown}"
        
        case "$OS_DISTRO" in
            ubuntu|debian|raspbian|linuxmint|pop) OS_FAMILY="debian" ;;
            fedora|rhel|centos|rocky|alma)        OS_FAMILY="redhat" ;;
            arch|archarm|manjaro|endeavouros)              OS_FAMILY="arch" ;;
            opensuse*|sles)                        OS_FAMILY="suse" ;;
            alpine)                                OS_FAMILY="alpine" ;;
            *)                                     OS_FAMILY="unknown" ;;
        esac
    elif [[ -f /etc/redhat-release ]]; then
        OS_FAMILY="redhat"; OS_DISTRO="redhat"
    elif [[ -f /etc/debian_version ]]; then
        OS_FAMILY="debian"; OS_DISTRO="debian"
    else
        OS_FAMILY="unknown"; OS_DISTRO="unknown"
    fi

    export OS_FAMILY OS_DISTRO OS_VERSION
    debug "OS: $OS_DISTRO ($OS_FAMILY) $OS_VERSION"
    return 0
}

show_os_info() {
    echo "OS: ${OS_DISTRO} (${OS_FAMILY}) ${OS_VERSION}"
}

# ============================================================================
# OS Convenience Functions
# ============================================================================

is_debian_based() { [[ "$OS_FAMILY" == "debian" ]]; }
is_redhat_based() { [[ "$OS_FAMILY" == "redhat" ]]; }
is_arch_based()   { [[ "$OS_FAMILY" == "arch" ]]; }
is_suse_based()   { [[ "$OS_FAMILY" == "suse" ]]; }
is_alpine()       { [[ "$OS_FAMILY" == "alpine" ]]; }

get_pkg_manager() {
    case "$OS_FAMILY" in
        debian)  echo "apt" ;;
        redhat)  command -v dnf &>/dev/null && echo "dnf" || echo "yum" ;;
        arch)    echo "pacman" ;;
        suse)    echo "zypper" ;;
        alpine)  echo "apk" ;;
        *)       echo "unknown" ;;
    esac
}

check_sudo() {
    [[ $EUID -eq 0 ]] && return 0
    command -v sudo &>/dev/null && sudo -n true 2>/dev/null
}

has_sudo_access() { check_sudo; }
