#!/bin/bash

# LIAUH Installation Script
# Installs dependencies and starts LIAUH

echo "📦 Installing dependencies..."
if ! sudo apt-get update; then
    echo "❌ Failed to update package lists"
    exit 1
fi

if ! sudo apt-get install -y git; then
    echo "❌ Failed to install git"
    exit 1
fi

echo "📥 Setting up LIAUH..."
cd ~

# Check if liauh directory already exists
if [[ -d "liauh" ]]; then
    echo "  (liauh directory exists, pulling latest updates...)"
    cd liauh
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true
else
    echo "  Cloning from GitHub..."
    if ! git clone https://github.com/sorglos-it/liauh.git; then
        echo "❌ Failed to clone LIAUH"
        exit 1
    fi
    cd liauh
fi

echo "🚀 Starting LIAUH..."
bash liauh.sh
