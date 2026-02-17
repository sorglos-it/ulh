#!/bin/bash
# File Backup Demo Script

ACTION="${1%%,*}"
FULL_PARAMS="$1"
PARAMS_REST="${FULL_PARAMS#*,}"

# Parse variables
if [[ -n "$PARAMS_REST" && "$PARAMS_REST" != "$FULL_PARAMS" ]]; then
    while IFS='=' read -r key val; do
        if [[ -n "$key" ]]; then
            export "$key=$val"
        fi
    done <<< "${PARAMS_REST//,/$'\n'}"
fi

SOURCE_FILE="${SOURCE_FILE:-/etc/hosts}"
BACKUP_DIR="${BACKUP_DIR:-/tmp}"

case "$ACTION" in
    backup)
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║         💾 File Backup                 ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        
        if [[ ! -f "$SOURCE_FILE" ]]; then
            echo "❌ Error: File not found: $SOURCE_FILE" >&2
            exit 1
        fi
        
        if [[ ! -d "$BACKUP_DIR" ]]; then
            echo "❌ Error: Backup directory not found: $BACKUP_DIR" >&2
            exit 1
        fi
        
        FILENAME=$(basename "$SOURCE_FILE")
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_FILE="$BACKUP_DIR/${FILENAME}.backup.${TIMESTAMP}"
        
        cp "$SOURCE_FILE" "$BACKUP_FILE" || {
            echo "❌ Error: Failed to backup file" >&2
            exit 1
        }
        
        echo "✅ Backup successful!"
        echo ""
        echo "Source:  $SOURCE_FILE"
        echo "Backup:  $BACKUP_FILE"
        echo "Size:    $(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null) bytes"
        echo ""
        exit 0
        ;;
    *)
        echo "Unknown action: $ACTION" >&2
        exit 1
        ;;
esac
