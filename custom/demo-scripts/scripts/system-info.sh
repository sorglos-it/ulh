#!/bin/bash
# System Information Demo Script

ACTION="${1%%,*}"

case "$ACTION" in
    show)
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║         📊 System Information          ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "Hostname:     $(hostname)"
        echo "OS:           $(uname -s)"
        echo "Kernel:       $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Uptime:       $(uptime -p 2>/dev/null || uptime)"
        echo ""
        exit 0
        ;;
    disk)
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║         💾 Disk Usage                  ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        df -h
        echo ""
        exit 0
        ;;
    *)
        echo "Unknown action: $ACTION" >&2
        exit 1
        ;;
esac
