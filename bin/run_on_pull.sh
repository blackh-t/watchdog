#!/bin/bash
set -e # Stop immediately if any command fails

# --- CONFIGURATION ---
# Must match the SERVICE_NAME used in your main installer (postman.sh)
SERVICE_NAME="pi5_dash"
BIN_DIR="/opt/$SERVICE_NAME"
SERVICE_UNIT="$SERVICE_NAME.service"

echo "[Auto-Deploy] Triggered by Webhook..."
export PATH="/root/.cargo/bin:$PATH"

cd server
cargo build --release
sudo systemctl stop "$SERVICE_UNIT"

# Install the New Binary
sudo cp -f target/release/SERVER "$BIN_DIR/"
sudo chmod 755 "$BIN_DIR/SERVER"

# Restart the Service
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE_UNIT"

echo "[Auto-Deploy] Success! System is live."
