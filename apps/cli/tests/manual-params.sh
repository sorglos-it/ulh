#!/bin/bash
# ============================================================================
# ulh Test Script
# Demonstrates how to parse parameters passed by ulh
# Parameters come as comma-separated string: action,VAR1=val1,VAR2=val2,...
# ============================================================================


# ============================================================================
# Display parsed information
# ============================================================================

echo "=== TEST SCRIPT ==="
echo ""

# Show execution mode
echo "Execution: $([ "$EUID" -eq 0 ] && echo "SUDO (UID 0)" || echo "NORMAL (UID $EUID)")"
echo "Action: $ACTION"
echo ""

# Show all parsed variables
echo "Parsed variables:"
echo "-------------------"

# List of common variables from example scripts
for var in DOMAIN SSL_ENABLED SSL_EMAIL KEEP_CONFIG REMOVE_LOGS \
           HTTP_PORT HTTPS_PORT hostname REMOVE_CERTS EMAIL WEBSERVER \
           NODE_VERSION INSTALL_YARN REMOVE_GLOBAL_PACKAGES \
           SET_PASSWORD REDIS_PASSWORD MAX_MEMORY KEEP_DATA PORT \
           SERVER_NAME WORKER_PROCESSES CLIENT_MAX_BODY_SIZE \
           MYSQL_ROOT_PASSWORD CREATE_DATABASE DATABASE_NAME \
           CREATE_USER DATABASE_USER DATABASE_USER_PASSWORD \
           BAN_TIME MAX_RETRY ENABLE_SSH FIND_TIME; do
    
    # Get variable value using indirect expansion: ${!var}
    val="${!var}"
    
    # Only show variables that were actually passed
    [[ -n "$val" ]] && echo "  $var = $val"
done

echo ""
echo "=== DONE ==="

# Exit with success
exit 0
