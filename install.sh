#!/bin/bash
# Compatibility: the published one-liner
#   wget -qO - https://raw.githubusercontent.com/sorglos-it/ulh/main/install.sh | bash
# still fetches this file. The installer is tools/install.sh. This file can go
# once that one-liner is no longer published anywhere.
set -o pipefail

main() {
    local here="${BASH_SOURCE[0]:-}"
    if [[ -f "$here" && -f "$(dirname "$here")/tools/install.sh" ]]; then
        exec bash "$(dirname "$here")/tools/install.sh" "$@"
    fi

    local url="https://raw.githubusercontent.com/sorglos-it/ulh/main/tools/install.sh"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" | bash -s -- "$@"
    else
        wget -qO - "$url" | bash -s -- "$@"
    fi
}

main "$@"
