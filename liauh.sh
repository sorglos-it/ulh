#!/bin/bash
# LIAUH - Linux Install and Update Helper (main entry point)

LIAUH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LIAUH_DIR

# Load all required libraries
for lib in core yaml menu execute; do
    source "${LIAUH_DIR}/lib/${lib}.sh"
done

# ============================================================================
# Auto-Update Feature
# ============================================================================

_auto_update() {
    # Check if we're in a git repository
    if [[ ! -d "$LIAUH_DIR/.git" ]]; then
        return 0
    fi
    
    cd "$LIAUH_DIR"
    
    # Fetch latest from remote (silent, non-blocking)
    if ! git fetch origin &>/dev/null; then
        return 0
    fi
    
    # Check if local is behind remote
    local behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || git rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
    
    if [[ "$behind" -gt 0 ]]; then
        msg_info "Updating LIAUH ($behind commit(s) behind)..."
        
        if git pull origin main &>/dev/null || git pull origin master &>/dev/null; then
            msg_ok "LIAUH updated successfully!"
            return 0
        else
            msg_warn "Auto-update failed - proceeding anyway"
            return 1
        fi
    fi
    
    return 0
}

# ============================================================================
# CLI Flag Handling
# ============================================================================

ENABLE_AUTO_UPDATE=true

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
            if [[ -d "$LIAUH_DIR/.git" ]]; then
                cd "$LIAUH_DIR"
                git fetch origin &>/dev/null
                local behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || git rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
                if [[ "$behind" -gt 0 ]]; then
                    msg_info "Updates available! Run: bash liauh.sh --update"
                    exit 0
                else
                    msg_ok "You are up to date."
                    exit 0
                fi
            else
                msg_warn "Not a git repository"
                exit 1
            fi
            ;;
        --update)
            if [[ -d "$LIAUH_DIR/.git" ]]; then
                cd "$LIAUH_DIR"
                msg_info "Pulling latest version..."
                if git pull origin main 2>/dev/null || git pull origin master 2>/dev/null; then
                    msg_ok "Update successful!"
                    exit 0
                else
                    msg_err "Update failed. Check git status."
                    exit 1
                fi
            else
                msg_warn "Not a git repository"
                exit 1
            fi
            ;;
        *)
            echo "Unknown option: $1"
            echo ""
            echo "Usage: bash liauh.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --debug              Enable debug output"
            echo "  --no-update          Skip auto-update on startup"
            echo "  --check-update       Check if updates are available"
            echo "  --update             Apply updates manually"
            exit 1
            ;;
    esac
done

# ============================================================================
# Main Program
# ============================================================================

# Auto-update on startup (unless disabled)
if [[ "$ENABLE_AUTO_UPDATE" == "true" ]]; then
    _auto_update
fi

# Detect OS
detect_os || exit 1

# Load main configuration
yaml_load "config" || exit 1

# Start main menu loop
menu_main
