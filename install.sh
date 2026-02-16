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

echo "📥 Cloning LIAUH..."
if ! cd ~ && git clone https://github.com/sorglos-it/liauh.git; then
    echo "❌ Failed to clone LIAUH"
    exit 1
fi

echo "🚀 Starting LIAUH..."
cd liauh
bash liauh.sh


