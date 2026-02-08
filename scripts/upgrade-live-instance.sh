#!/bin/bash
# =============================================================================
# Upgrade a running OpenClaw OCI instance with:
#   - Python 3 + pip + venv
#   - Playwright + Chromium (headless browser automation)
#   - ClawHub + skills
#   - Tailscale (optional — skipped if no auth key provided)
#
# Usage:
#   scp scripts/upgrade-live-instance.sh ubuntu@<INSTANCE_IP>:~/
#   ssh ubuntu@<INSTANCE_IP>
#   sudo bash upgrade-live-instance.sh [--tailscale-key tskey-auth-xxxxx]
#
# This script is SAFE to run on a live instance. It does NOT touch:
#   - Existing OpenClaw config (~/.openclaw/openclaw.json)
#   - Existing Ollama models
#   - Existing systemd services
#   - Terraform state
# =============================================================================

set -euo pipefail

TAILSCALE_AUTH_KEY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tailscale-key)
            TAILSCALE_AUTH_KEY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: sudo bash upgrade-live-instance.sh [--tailscale-key tskey-auth-xxxxx]"
            exit 1
            ;;
    esac
done

echo "============================================"
echo "  OpenClaw Instance Upgrade"
echo "  $(date)"
echo "============================================"
echo ""

# ============================================================
# 1. Install system packages (browser deps + Python)
# ============================================================
echo "[1/5] Installing system packages..."
apt-get update -qq

apt-get install -y -qq \
    python3 python3-pip python3-venv \
    libnss3 libatk-bridge2.0-0 libdrm2 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2 libpango-1.0-0 libcairo2 \
    libcups2 libatspi2.0-0 libxshmfence1

echo "✓ System packages installed"

# ============================================================
# 2. Install Playwright + Chromium
# ============================================================
echo "[2/5] Installing Playwright + Chromium..."
npm install -g playwright 2>/dev/null || npm install -g playwright
npx playwright install chromium
echo "✓ Playwright + Chromium installed"

# ============================================================
# 3. Install ClawHub and skills
# ============================================================
echo "[3/5] Installing ClawHub and skills..."
npm install -g clawhub 2>/dev/null || npm install -g clawhub

# Create skills directory if it doesn't exist
mkdir -p /home/openclaw/.openclaw/skills
cd /home/openclaw/.openclaw/skills

echo "  Installing skills from ClawHub..."
SKILLS=(
    "chirp"               # Twitter/X posting and replies
    "pinch-to-post"       # Cross-post to Twitter, LinkedIn, Mastodon
    "openai-image-gen"    # Image generation via OpenAI
    "fal-ai"              # Image/video generation via fal.ai
    "mailchannels"        # Send emails
    "autofillin"          # Browser form automation
    "python"              # Python coding guidelines
    "skill-creator"       # Create new custom skills
    "gmail"
)

for skill in "${SKILLS[@]}"; do
    echo "  → Installing $skill..."
    clawhub install "$skill" || echo "  ⚠ Failed to install $skill (may already exist or not found)"
done

chown -R openclaw:openclaw /home/openclaw/.openclaw
echo "✓ ClawHub and skills installed"

# ============================================================
# 4. Install Tailscale (optional)
# ============================================================
echo "[4/5] Tailscale setup..."
if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "✓ Tailscale installed"
else
    echo "✓ Tailscale already installed"
fi

if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=openclaw-oci --ssh
    echo "✓ Tailscale connected (hostname: openclaw-oci, SSH enabled)"
else
    echo "⚠ No Tailscale auth key provided."
    echo "  To connect later: sudo tailscale up --hostname=openclaw-oci --ssh"
fi

# ============================================================
# 5. Patch OpenClaw config (non-destructive merge)
# ============================================================
echo "[5/5] Patching OpenClaw config..."

OPENCLAW_CONFIG="/home/openclaw/.openclaw/openclaw.json"

if [ -f "$OPENCLAW_CONFIG" ]; then
    # Check if skills section already exists
    if python3 -c "import json; c=json.load(open('$OPENCLAW_CONFIG')); assert 'skills' not in c" 2>/dev/null; then
        # Add skills section using python3 (safe JSON merge)
        python3 << 'PYEOF'
import json

config_path = "/home/openclaw/.openclaw/openclaw.json"

with open(config_path, 'r') as f:
    config = json.load(f)

# Add skills config if not present
if 'skills' not in config:
    config['skills'] = {
        "install": {
            "preferBrew": False,
            "nodeManager": "npm"
        },
        "entries": {
            "chirp": {"enabled": True},
            "pinch-to-post": {"enabled": True},
            "openai-image-gen": {"enabled": True},
            "fal-ai": {"enabled": True},
            "mailchannels": {"enabled": True},
            "autofillin": {"enabled": True},
            "python": {"enabled": True},
            "skill-creator": {"enabled": True}
        }
    }

# Add gateway.tailscale config if not present
if 'gateway' not in config:
    config['gateway'] = {}

if 'tailscale' not in config.get('gateway', {}):
    config['gateway']['tailscale'] = {
        "mode": "serve",
        "resetOnExit": True
    }

if 'bind' not in config.get('gateway', {}):
    config['gateway']['bind'] = "loopback"

gateway_auth = config.get('gateway', {}).get('auth', {})
if 'allowTailscale' not in gateway_auth:
    if 'auth' not in config['gateway']:
        config['gateway']['auth'] = {}
    config['gateway']['auth']['allowTailscale'] = True

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("✓ Config updated with skills + gateway.tailscale sections")
PYEOF
    else
        echo "✓ Skills section already exists in config — skipping"
    fi
else
    echo "⚠ OpenClaw config not found at $OPENCLAW_CONFIG"
    echo "  Run 'sudo su - openclaw && openclaw onboard' first, then re-run this script"
fi

chown -R openclaw:openclaw /home/openclaw/.openclaw

echo ""
echo "============================================"
echo "  Upgrade Complete!"
echo "============================================"
echo ""
echo "What to do next:"
echo ""
echo "  1. Add API keys for skills that need them:"
echo "     sudo su - openclaw"
echo "     nano ~/.openclaw/openclaw.json"
echo "     → openai-image-gen needs: \"apiKey\": \"sk-...\""
echo "     → fal-ai needs:          \"apiKey\": \"...\""
echo "     → mailchannels needs:    \"apiKey\": \"...\""
echo ""
echo "  2. Restart the gateway to pick up changes:"
echo "     sudo systemctl restart openclaw-gateway"
echo ""
echo "  3. Verify skills are loaded:"
echo "     sudo su - openclaw"
echo "     openclaw skills list --eligible"
echo ""
if command -v tailscale &>/dev/null && tailscale status &>/dev/null; then
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
    echo "  4. Tailscale is connected!"
    echo "     Dashboard: https://openclaw-oci/"
    echo "     Tailscale IP: $TS_IP"
    echo "     SSH: ssh openclaw-oci"
    echo ""
fi
