#!/bin/bash
set -e

# LIAUH Installation Script
# Installs dependencies and starts LIAUH

echo "📦 Installing dependencies..."
sudo apt-get update && sudo apt-get install -y git

echo "📥 Cloning LIAUH..."
cd ~ && git clone https://github.com/sorglos-it/liauh.git

echo "🚀 Starting LIAUH..."
cd liauh && bash liauh.sh


