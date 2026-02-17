#!/bin/bash
# Hello World Demo Script

ACTION="${1:-run}"

# Parse comma-separated parameters
FULL_PARAMS="$1"
ACTION="${FULL_PARAMS%%,*}"
PARAMS_REST="${FULL_PARAMS#*,}"

# Parse variables
if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        if [[ -n "$key" ]]; then
            export "$key=$val"
        fi
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

# Default value if not set
NAME="${NAME:-World}"

case "$ACTION" in
    run)
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║        🎉 Hello, $NAME! 🎉           ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "This is a demo custom script from the demo-scripts repository!"
        echo ""
        exit 0
        ;;
    *)
        echo "Unknown action: $ACTION" >&2
        exit 1
        ;;
esac
