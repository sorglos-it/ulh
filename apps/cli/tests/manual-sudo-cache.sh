#!/bin/bash
# Simple sudo cache test
# This script calls sudo twice to show password caching

set -e
source "$(dirname "$0")/../classes/bootstrap.sh"
# Script entscheidet selbst wann geparst werden soll:
parse_parameters "$1"

case "$ACTION" in
    test)
        echo "=== SUDO CACHE TEST ==="
        echo ""
        echo "First sudo call (should ask for password or use cache):"
        sudo whoami
        echo ""
        
        echo "Second sudo call (should NOT ask for password - uses cache):"
        sudo whoami
        echo ""
        
        echo "If both commands ran without a password prompt on the second one,"
        echo "then sudo password caching is working correctly!"
        echo ""
        echo "=== DONE ==="
        exit 0
        ;;
    *)
        echo "Unknown action: $ACTION"
        exit 1
        ;;
esac
