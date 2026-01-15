#!/bin/bash
set -e # Stop on error flag.

#             CONFIG
#######################################
IP="127.0.0.1"
WS_PORT=7777   # WebServer PORT.
SERVER_ENDPOINT=""
SECRET_TOKEN=""
SERVICE_NAME="pi5_dash" # Project name
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

sudo tailscale funnel -bg --set-path / http://127.0.0.1:$WS_PORT

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

echo "------------------------------------------------"
echo "$TS_STATS"
echo "------------------------------------------------"
echo "✅ $SERVICE_NAME installation complete"
echo "Your Webhook endpoint: $SERVER_ENDPOINT/webhook"
