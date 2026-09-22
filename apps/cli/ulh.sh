#!/bin/bash
# ulh - unknown linux helper (main entry point)
#
# Start:  bash ~/ulh/apps/cli/ulh.sh
# The old way, cd ~/ulh && bash ulh.sh, still works (forwarder in the root).

# Set UTF-8 locale for proper string length calculation
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

ulh_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # apps/cli
ULH_ROOT="$(cd "${ulh_DIR}/../.." && pwd)"                 # the git clone
ulh_VERSION="$(tr -d '[:space:]' < "${ulh_DIR}/VERSION" 2>/dev/null)"
ulh_VERSION="${ulh_VERSION:-unknown}"
export ulh_VERSION ulh_DIR ULH_ROOT

# Load all required libraries (order matters: dependencies first)
for lib in core yaml menu execute repos update userdata; do
    source "${ulh_DIR}/classes/${lib}.sh"
done

# ============================================================================
# CLI Flag Handling
# ============================================================================

ULH_ARGS=("$@")          # handed on when ulh restarts itself after an update
ENABLE_AUTO_UPDATE=true

print_help() {
    echo "Usage: bash apps/cli/ulh.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --debug              Enable debug output"
    echo "  --no-update          Skip auto-update on startup"
    echo "  --check-update       Check if updates are available"
    echo "  --update             Apply updates manually"
    echo "  -h, --help           Show this help"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG=true
            shift
            ;;
        --no-update)
            ENABLE_AUTO_UPDATE=false
            shift
            ;;
        --check-update)
            update_check
            exit $?
            ;;
        --update)
            update_apply
            exit $?
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo ""
            print_help
            exit 1
            ;;
    esac
done

# ============================================================================
# Main Program
# ============================================================================

# Auto-update on startup (unless disabled) - restarts itself when it pulled
if [[ "$ENABLE_AUTO_UPDATE" == "true" ]]; then
    update_auto
fi

# Your own files: take over the old custom/ folder once, create what is missing
userdata_migrate
userdata_init

# Detect OS
detect_os || exit 1

# Load the catalog of all ulh scripts
yaml_load "assets/catalog" || exit 1

# Initialize custom repositories (clone/pull and merge configs)
repo_init "$ulh_DIR"

# Start main menu loop
menu_main
