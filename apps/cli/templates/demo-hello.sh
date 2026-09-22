#!/bin/bash

# hello - Hello World Demo Script
# Simple greeting demonstration script with customizable name parameter

set -e
source "$(dirname "$0")/../../../lib/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

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
        sleep 10
        exit 0
        ;;
    *)
        print_usage hello && exit 1
esac
