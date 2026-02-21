#!/bin/bash

# ULH Server Patch Script - Update Remotely on multiple servers
# Usage: ./patch-servers.sh [server1] [server2] ...
# Or: ./patch-servers.sh (uses default SERVERS list below)

set -e

# ============================================================
# CONFIGURE YOUR SERVERS HERE
# ============================================================

SERVERS=(
    # Add your servers like this:
    # "user@192.168.1.100"
    # "root@server.example.com"
)

# ============================================================
# OPTIONAL: Override with command-line arguments
# ============================================================

if [[ $# -gt 0 ]]; then
    SERVERS=("$@")
fi

# Check if servers are configured
if [[ ${#SERVERS[@]} -eq 0 ]]; then
    echo "❌ No servers configured"
    echo ""
    echo "Usage: ./patch-servers.sh [server1] [server2] ..."
    echo "Example: ./patch-servers.sh root@192.168.1.100 root@server2.lan"
    echo ""
    echo "Or edit this script and add servers to the SERVERS array"
    exit 1
fi

echo "🔄 ULH Server Patch Script"
echo "========================="
echo ""
echo "Servers to patch: ${#SERVERS[@]}"
for server in "${SERVERS[@]}"; do
    echo "  - $server"
done
echo ""

# ============================================================
# PATCH FUNCTION
# ============================================================

patch_server() {
    local server=$1
    
    echo "📦 Patching: $server"
    
    # SSH into server and run ulh.sh remotely update
    ssh -o ConnectTimeout=10 "$server" bash << 'EOF'
if [[ ! -d ~/ulh ]]; then
    echo "❌ ULH not installed at ~/ulh"
    exit 1
fi

echo "Running: cd ~/ulh && bash ulh.sh remotely update"
cd ~/ulh && bash ulh.sh remotely update
EOF
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Patched: $server"
    else
        echo "❌ Failed: $server"
        return 1
    fi
}

# ============================================================
# PATCH ALL SERVERS
# ============================================================

SUCCESS=0
FAILED=0

for server in "${SERVERS[@]}"; do
    if patch_server "$server"; then
        ((SUCCESS++))
    else
        ((FAILED++))
    fi
    echo ""
done

# ============================================================
# SUMMARY
# ============================================================

echo "📊 Patch Summary"
echo "================"
echo "✅ Success: $SUCCESS"
echo "❌ Failed:  $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi

echo "🎉 All servers patched successfully!"
