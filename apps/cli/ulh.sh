#!/bin/bash
# ulh - unknown linux helper (main entry point)
#
# Start:  bash ~/ulh/apps/cli/ulh.sh
# The old way, cd ~/ulh && bash ulh.sh, still works (forwarder in the root).

# The language of the system decides the language of ulh. ulh switches to
# C.UTF-8 right below (proper string lengths), so it keeps the original here -
# also across the restart after an update.
export ULH_SYS_LOCALE="${ULH_SYS_LOCALE:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}"

# Set UTF-8 locale for proper string length calculation
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

ulh_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # apps/cli
ULH_ROOT="$(cd "${ulh_DIR}/../.." && pwd)"                 # the git clone
ulh_VERSION="$(tr -d '[:space:]' < "${ulh_DIR}/VERSION" 2>/dev/null)"
ulh_VERSION="${ulh_VERSION:-unknown}"
export ulh_VERSION ulh_DIR ULH_ROOT

# Load all required libraries (order matters: dependencies first)
for lib in core yaml lang menu execute repos update userdata; do
    source "${ulh_DIR}/classes/${lib}.sh"
done

# --lang first: the help and every message after it already speak that language
ULH_LANG_ARG=""
ULH_LANG_GIVEN=false
for ((i = 1; i <= $#; i++)); do
    if [[ "${!i}" == "--lang" || "${!i}" == "--language" ]]; then
        j=$((i + 1)); ULH_LANG_ARG="${!j:-}"; ULH_LANG_GIVEN=true
    fi
done
lang_init "$ULH_LANG_ARG"
if [[ "$ULH_LANG_GIVEN" == true ]] && ! lang_valid "${ULH_LANG_ARG,,}"; then
    msg_err "$(t main.unknown_lang "$ULH_LANG_ARG" "${ULH_LANGUAGES[*]}")"
    exit 1
fi

# ============================================================================
# CLI Flag Handling
# ============================================================================

ULH_ARGS=("$@")          # handed on when ulh restarts itself after an update
ENABLE_AUTO_UPDATE=true

print_help() {
    echo "$(t help.usage)"
    echo ""
    echo "$(t help.options)"
    printf '  %-24s %s\n' "--debug" "$(t help.debug)"
    printf '  %-24s %s\n' "--no-update" "$(t help.no_update)"
    printf '  %-24s %s\n' "--check-update" "$(t help.check_update)"
    printf '  %-24s %s\n' "--update" "$(t help.update)"
    printf '  %-24s %s\n' "--lang de|en|fr|it|es" "$(t help.lang)"
    printf '  %-24s %s\n' "-h, --help" "$(t help.help)"
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
        --lang|--language)
            # already read above
            shift; [[ $# -gt 0 ]] && shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "$(t main.unknown_option "$1")"
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
