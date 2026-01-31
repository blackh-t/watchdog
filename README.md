<div align="center">
  
# ✉️ Postman
**Postman** automates deployment for your repository, with Github Webhook.

![Rust](https://img.shields.io/badge/Built_with-Rust-orange?style=flat-square)
![Tailscale](https://img.shields.io/badge/Network-Tailscale-blue?style=flat-square)

</div>

### Key Features

- **Secure Access:** Uses Tailscale Funnel to expose your local server securely (no port forwarding required).
- **Auto-Deploy:** Automatically pulls updates via GitHub Webhooks.
- **Custom Scripting:** Executes `run_on_pull.sh` on every update to handle builds or restarts.

---

### Prerequisites

- Linux OS with Root privileges.
- A [Tailscale](https://tailscale.com) account.

---

### Setup Guide

**1. Clone & Install**
Clone the repository to your device and run the installer as root:

```bash
git clone https://github.com/YOUR_USERNAME/Watchdog.git
cd Watchdog
chmod +x postman.sh
sudo ./postman.sh

```

**2. Configure**
Follow the on-screen prompts to:

- Log in to **Tailscale**.
- Create a **SECRET_TOKEN** (Save this for the next step).
- _Copy the **Webhook Endpoint URL** provided at the end of the script._

**3. Add GitHub Webhook**
Go to your GitHub Repo **Settings** > **Webhooks** > **Add webhook**:

- **Payload URL:** Paste the URL from Step 2.
- **Content type:** `application/json`.
- **Secret:** Enter your `SECRET_TOKEN`.
- Click **Add webhook**.

---

### How It Works

1. You push code to GitHub.
2. GitHub notifies your device via the secure Tailscale link.
3. **Postman** verifies the secret, pulls the code, and triggers `run_on_pull.sh`.
