#!/bin/bash
set -e # Stop on error flag.

#             CONFIG
#######################################
IP="127.0.0.1"
WS_PORT=7777   # WebServer PORT.
SERVER_ENDPOINT=""
SECRET_TOKEN=""
SERVICE_NAME="pi5_dash"
BIN_DIR="/opt/$SERVICE_NAME"
WORK_DIR=$(pwd)
SYSTEMD_LIST=$WORK_DIR"/systemd.txt"
BIN_LOCAL="$WORK_DIR/bin"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

#######################################
# INSTALL TAILSCALE (if missing)
#######################################
if command -v tailscale >/dev/null 2>&1; then
    echo "✅ Tailscale already installed."
else
    echo "📦 Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! systemctl is-enabled tailscaled >/dev/null 2>&1; then
    sudo systemctl enable tailscaled
fi

if ! systemctl is-active tailscaled >/dev/null 2>&1; then
    sudo systemctl start tailscaled
fi

if ! tailscale status >/dev/null 2>&1; then
    sudo tailscale login
    sudo tailscale up
fi

# --- AUTO-DETECT ENDPOINT FOR WATCHDOG ---
# We need this now so we can write it into the watchdog script
echo "🔍 Detecting Tailscale URL..."
TS_DOMAIN=$(tailscale status --json | grep -oP '"DNSName": "\K[^"]+' | head -1 | sed 's/\.$//')
if [ -z "$TS_DOMAIN" ]; then
    SERVER_ENDPOINT="http://127.0.0.1:$WS_PORT"
    echo "⚠️  Could not detect Tailscale domain. Defaulting to local."
else
    SERVER_ENDPOINT="https://$TS_DOMAIN"
    echo "✅ Target set to: $SERVER_ENDPOINT"
fi

#######################################
# Init SECRET_TOKEN for GitHub webhook
#######################################
if [ -z "$SECRET_TOKEN" ]; then
    echo "SECRET_TOKEN undefined."
    read -r -p "Type the SECRET_TOKEN: " SECRET_TOKEN
    export SECRET_TOKEN
fi

#######################################
# funnel_webserver.service
#######################################
echo "$SERVICE_NAME-funnel_webserver.service" >>"$SYSTEMD_LIST"
sudo tee /etc/systemd/system/$SERVICE_NAME-funnel_webserver.service >/dev/null <<EOF
[Unit]
Description=$SERVICE_NAME Funnel WebServer
After=network-online.target tailscaled.service
Requires=tailscaled.service
Wants=network-online.target tailscaled.service

[Service]
Type=simple
User=root
ExecStartPre=-/usr/bin/tailscale funnel reset
ExecStart=/usr/bin/tailscale funnel --set-path / http://127.0.0.1:$WS_PORT
ExecStop=/usr/bin/tailscale funnel reset

# Retry every 5 seconds if it fails (e.g. waiting for Tailscale to wake up)
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

#######################################
# webserver.service
#######################################
echo "$SERVICE_NAME.service" >>"$SYSTEMD_LIST"
sudo tee /etc/systemd/system/$SERVICE_NAME.service >/dev/null <<EOF
[Unit]
Description=$SERVICE_NAME API Server
# After=network.target docker.service
# Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$BIN_DIR/SERVER
Restart=on-failure
RestartSec=5

Environment="TS_IP=$IP"
Environment="TS_PORT=$WS_PORT"
Environment="SCRIPT_PATH=/usr/local/bin/git_pull.sh"
Environment="SECRET_TOKEN=$SECRET_TOKEN"
Environment="WORK_DIR=$WORK_DIR"

[Install]
WantedBy=multi-user.target
EOF

# ==========================================
# WATCHDOG: NUCLEAR REBOOT EDITION
# ==========================================
echo "☢️  Installing Nuclear Watchdog..."

sudo tee /usr/local/bin/check_ping.sh >/dev/null <<EOF
#!/bin/bash

# --- CONFIGURATION ---
INTERNET_TARGET="8.8.8.8"
FUNNEL_TARGET="$SERVER_ENDPOINT"  # <-- Auto-filled by installer
# ---------------------

echo "--- Starting Connectivity Check ---"

# 1. CHECK INTERNET (Basic Connectivity)
# We ping Google to see if the Pi has ANY internet connection.
if ping -c 1 -W 5 "\$INTERNET_TARGET" > /dev/null 2>&1; then
    echo "✅ Internet Connection: OK (\$INTERNET_TARGET)"
else
    echo "❌ Internet Connection: DOWN"
    echo "   -> Reason: Cannot reach Google."
    echo "   -> Action: REBOOTING SYSTEM."

    /sbin/reboot -f
    exit 1
fi

# 2. CHECK FUNNEL (The real test)
# If internet is fine, we specifically check if the Funnel is accessible from the outside.
# -s: Silent, --head: Headers only, --fail: Fail on error code, --max-time 10: Timeout
if curl -s --head --fail --max-time 10 "\$FUNNEL_TARGET" > /dev/null; then
    echo "✅ Tailscale Funnel: UP (\$FUNNEL_TARGET)"
    exit 0
else
    echo "❌ Tailscale Funnel: DOWN"
    echo "   -> Reason: Internet is up, but Funnel URL is unreachable."
    echo "   -> Action: NUCLEAR REBOOT INITIATED."

    # --- NUCLEAR REBOOT SEQUENCE ---
    systemctl --force --force reboot &
    sleep 2
    /usr/sbin/reboot -f -f
    /sbin/reboot -f -f
    # Kernel Panic Trigger
    echo 1 > /proc/sys/kernel/sysrq
    echo b > /proc/sysrq-trigger

    exit 1
fi
EOF

sudo chmod +x /usr/local/bin/check_ping.sh

# ------------------------------------------
# Create the Watchdog Service
# ------------------------------------------
sudo tee /etc/systemd/system/$SERVICE_NAME-watchdog.service >/dev/null <<EOF
[Unit]
Description=$SERVICE_NAME Nuclear Watchdog

[Service]
User=root
Type=oneshot
ExecStart=/usr/local/bin/check_ping.sh
EOF

# ------------------------------------------
# Create the Watchdog Timer
# ------------------------------------------
echo "$SERVICE_NAME-watchdog.timer" >>"$SYSTEMD_LIST"
sudo tee /etc/systemd/system/$SERVICE_NAME-watchdog.timer >/dev/null <<EOF
[Unit]
Description=Run Tailscale Watchdog every 10 minutes

[Timer]
# Wait 5 minutes after boot before first check
OnBootSec=5min
# Then check every 10 minutes
OnUnitActiveSec=10min
Unit=$SERVICE_NAME-watchdog.service

[Install]
WantedBy=timers.target
EOF

#######################################
# git_pull.sh
#######################################
sudo tee $WORK_DIR/bin/git_pull.sh >/dev/null <<EOF
#!/bin/bash
cd $WORK_DIR

GIT_OUTPUT=\$(git pull)
echo "\$GIT_OUTPUT"

if echo "\$GIT_OUTPUT" | grep -q "Fast-forward"; then
    if [ -f bin/run_on_pull.sh ]; then
        cp -f bin/run_on_pull.sh /usr/local/bin/
        chmod +x /usr/local/bin/run_on_pull.sh
        echo "[UPDATED] run_on_pull.sh"
    fi
else
    echo "[SKIP] No changes"
fi
EOF

#######################################
# run_on_pull.service
#######################################
sudo tee /etc/systemd/system/$SERVICE_NAME-run_on_pull.service >/dev/null <<EOF
[Unit]
Description=$SERVICE_NAME run_on_pull hook
ConditionPathExists=/usr/local/bin/run_on_pull.sh

[Service]
Type=oneshot
User=root
WorkingDirectory=$WORK_DIR
Environment="PATH=/root/.cargo/bin:/usr/bin:/bin"
ExecStart=/usr/local/bin/run_on_pull.sh
EOF

#######################################
# INSTALL RUST (IF NEEDED)
#######################################
if ! command -v cargo >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
fi

export PATH="/root/.cargo/bin:$PATH"

#######################################
# BUILD SERVER
#######################################
cd "$WORK_DIR/server"
cargo build --release
sudo install -m 755 target/release/SERVER "$BIN_DIR/SERVER"

#######################################
# ENABLE SERVICES
#######################################
sudo systemctl daemon-reload
while read -r UNIT; do
    if [ ! -z "$UNIT" ]; then
        sudo systemctl enable --now "$UNIT"
    fi
done <"$SYSTEMD_LIST"

#######################################
# INSTALL HELPER SCRIPTS
#######################################
sudo install -m 755 "$BIN_LOCAL/git_pull.sh" /usr/local/bin/git_pull.sh
[[ -f "$BIN_LOCAL/run_on_pull.sh" ]] && sudo install -m 755 "$BIN_LOCAL/run_on_pull.sh" /usr/local/bin/run_on_pull.sh

echo "✅ $SERVICE_NAME installation complete"
echo "☢️  Watchdog is ACTIVE on target: $SERVER_ENDPOINT"
echo "Your Webhook endpoint: $SERVER_ENDPOINT/webhook"
