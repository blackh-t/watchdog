<div align="center">
  
# 🐕 Watchdog

**A resilient, self-healing auto-deployment agent for edge devices.**

![Rust](https://img.shields.io/badge/Built_with-Rust-orange?style=flat-square)
![Systemd](https://img.shields.io/badge/Service-Systemd-green?style=flat-square)
![Tailscale](https://img.shields.io/badge/Network-Tailscale-blue?style=flat-square)
</div>

> [!WARNING]
> **This project includes a Hard Reboot mechanism.**
> If the connection check fails, the device **WILL** reboot immediately. Do not run this on critical systems.

>Watchdog allows you to automatically build and deploy Rust Webapp on your device (like a Raspberry Pi) simply by pushing to GitHub. It uses **Tailscale Funnel** to securely expose your local webhook to the network and features a **nuclear boot** that forces a hardware reset if the connection ever drops.

## Features

>- **Auto-Deploy:** Automatically pulls code, compiles, and restarts services via GitHub Webhooks.
>- **Tailscale Funnel:** Exposes your local server to the public internet securely (no router port forwarding needed).
>- **Nuclear Watchdog:** Monitors the public endpoint 24/7. If the site is unreachable, it forces a kernel-level reboot to restore connectivity.
>- **Rust Integrated:** Handles `cargo build --release` by making changes to ` /bin/run_on_pull.sh`, which is detected and executed by a systemd unit.

## Prerequisites

>- A Linux device
>- Root privileges (sudo).
>- A [Tailscale](https://tailscale.com) account.

## Installation

### 1. Fork the Repository
> Click the **Fork** button at the top right of this page to create your own copy of the repository.

### 2. Clone to your Device
> SSH into your device and clone your forked repository:

```bash
git clone https://github.com/YOUR_USERNAME/watchdog.git
cd watchdog

```

### 3. Run the Installer

>Make the script executable and run it with root privileges:

```bash
chmod +x postman.sh
sudo ./postman.sh

```

>**During installation, you will be asked to:**
>1. **Log in to Tailscale** (if not already connected).
>2. **Enter a SECRET_TOKEN**: Choose a secure password (you will need this for GitHub).

### 4. Setup GitHub Webhook

>Once the installation finishes, the script will output your **Webhook Endpoint** (e.g., `https://device-name.ts.net/webhook`).

>1. Go to your GitHub Repository Settings > **Webhooks** > **Add webhook**.
>2. **Payload URL**: Paste the URL provided by the installer.
>3. **Content type**: Select `application/json`.
>4. **Secret**: Enter the `SECRET_TOKEN` you created during installation.
>5. Click **Add webhook**.

## How it Works

>1. You push code to GitHub.
>2. GitHub sends a webhook to your device via the secure Tailscale Funnel.
>3. **Watchdog** verifies the secret, pulls the latest code, recompiles the project, and restarts the service.
>4. If the connection fails at any point, the **Watchdog** reboots the system to ensure it comes back online.
