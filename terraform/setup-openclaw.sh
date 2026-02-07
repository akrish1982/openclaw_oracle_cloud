#!/bin/bash
# =============================================================================
# OpenClaw + Ollama + Claude + Kimi K2.5 + Telegram
# Standalone Setup Script for Ubuntu 22.04+ (ARM64 or x86_64)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/setup-openclaw.sh | sudo bash
#   -- OR --
#   sudo bash setup-openclaw.sh
#
# This script:
#   1. Installs Node.js 22 LTS
#   2. Installs Ollama + pulls a local model
#   3. Installs OpenClaw
#   4. Creates a systemd service
#   5. Walks you through configuration
# =============================================================================
set -euo pipefail

# --- Configuration (override via env vars) ---
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:14b}"
OPENCLAW_USER="${OPENCLAW_USER:-openclaw}"
NODE_MAJOR="${NODE_MAJOR:-22}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root (sudo)"
  exit 1
fi

header "OpenClaw Full Stack Setup"
info "Target: Ollama + Claude + Kimi K2.5 + Telegram"
info "Architecture: $(uname -m)"
echo ""

# =============================================================================
# Step 1: System packages
# =============================================================================
header "Step 1/6: System Packages"
apt-get update -qq
apt-get install -y -qq curl wget git jq unzip htop tmux ca-certificates
log "System packages installed"

# =============================================================================
# Step 2: Node.js
# =============================================================================
header "Step 2/6: Node.js ${NODE_MAJOR} LTS"
if command -v node &>/dev/null && [[ $(node -v | cut -d'.' -f1 | tr -d 'v') -ge $NODE_MAJOR ]]; then
  log "Node.js $(node -v) already installed"
else
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y -qq nodejs
  log "Node.js $(node -v) installed"
fi

# =============================================================================
# Step 3: Ollama
# =============================================================================
header "Step 3/6: Ollama"
if command -v ollama &>/dev/null; then
  log "Ollama already installed"
else
  curl -fsSL https://ollama.com/install.sh | sh
  log "Ollama installed"
fi

systemctl enable ollama
systemctl start ollama
sleep 5

info "Pulling model: ${OLLAMA_MODEL} (this may take 10-30 minutes)..."
info "You can skip this and pull later with: ollama pull ${OLLAMA_MODEL}"
nohup ollama pull "${OLLAMA_MODEL}" > /var/log/ollama-pull.log 2>&1 &
PULL_PID=$!
warn "Model download running in background (PID: ${PULL_PID})"
warn "Monitor with: tail -f /var/log/ollama-pull.log"

# =============================================================================
# Step 4: OpenClaw user + install
# =============================================================================
header "Step 4/6: OpenClaw"

# Create dedicated user
if ! id "$OPENCLAW_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$OPENCLAW_USER"
  log "Created user: ${OPENCLAW_USER}"
fi

# Install OpenClaw globally
if ! command -v openclaw &>/dev/null; then
  npm install -g openclaw
  log "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'installed')"
else
  log "OpenClaw already installed"
fi

# =============================================================================
# Step 5: Systemd service
# =============================================================================
header "Step 5/6: Systemd Service"

cat > /etc/systemd/system/openclaw-gateway.service << EOF
[Unit]
Description=OpenClaw Gateway
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=${OPENCLAW_USER}
WorkingDirectory=/home/${OPENCLAW_USER}
ExecStart=$(which openclaw) gateway run
Restart=always
RestartSec=30
Environment=NODE_ENV=production
Environment=HOME=/home/${OPENCLAW_USER}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
log "Systemd service created: openclaw-gateway"

# Health-check cron
cat > /etc/cron.d/openclaw-health << 'EOF'
*/30 * * * * root systemctl is-active --quiet openclaw-gateway || systemctl restart openclaw-gateway
EOF
log "Health-check cron installed (every 30 min)"

# OCI keepalive (prevent instance reclamation)
cat > /etc/cron.d/oci-keepalive << 'EOF'
*/5 * * * * root dd if=/dev/urandom bs=1M count=10 of=/dev/null 2>/dev/null; sleep 2
EOF
log "OCI keepalive cron installed"

# =============================================================================
# Step 6: Write config template
# =============================================================================
header "Step 6/6: Configuration Template"

OPENCLAW_HOME="/home/${OPENCLAW_USER}"
mkdir -p "${OPENCLAW_HOME}/.openclaw"

cat > "${OPENCLAW_HOME}/.openclaw/openclaw.json" << JSONEOF
{
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434",
        "models": [
          {
            "id": "ollama/${OLLAMA_MODEL}",
            "name": "Local Ollama (${OLLAMA_MODEL})",
            "contextWindow": 65536,
            "maxTokens": 8192
          }
        ]
      },
      "anthropic": {
        "apiKey": "PASTE_YOUR_ANTHROPIC_API_KEY_HERE",
        "models": [
          {
            "id": "anthropic/claude-sonnet-4-20250514",
            "name": "Claude Sonnet 4",
            "contextWindow": 200000,
            "maxTokens": 8192
          },
          {
            "id": "anthropic/claude-haiku",
            "name": "Claude Haiku",
            "contextWindow": 200000,
            "maxTokens": 4096
          }
        ]
      },
      "openrouter": {
        "baseUrl": "https://openrouter.ai/api/v1",
        "apiKey": "PASTE_YOUR_OPENROUTER_API_KEY_HERE",
        "api": "openai-completions",
        "models": [
          {
            "id": "openrouter/moonshotai/kimi-k2.5",
            "name": "Kimi K2.5",
            "contextWindow": 131072,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-20250514",
        "fallback": [
          "openrouter/moonshotai/kimi-k2.5",
          "ollama/${OLLAMA_MODEL}"
        ]
      },
      "modelPatterns": {
        "heartbeat": "ollama/${OLLAMA_MODEL}",
        "subAgent": "openrouter/moonshotai/kimi-k2.5"
      },
      "modelAliases": {
        "claude": "anthropic/claude-sonnet-4-20250514",
        "haiku": "anthropic/claude-haiku",
        "kimi": "openrouter/moonshotai/kimi-k2.5",
        "local": "ollama/${OLLAMA_MODEL}"
      }
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "PASTE_YOUR_TELEGRAM_BOT_TOKEN_HERE"
    }
  }
}
JSONEOF

chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_HOME}/.openclaw"
log "Config template written to ${OPENCLAW_HOME}/.openclaw/openclaw.json"

# =============================================================================
# Done!
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "  ${GREEN}✓ Installation Complete!${NC}"
echo ""
echo "  Choose ONE of these configuration paths:"
echo ""
echo -e "  ${BLUE}Option A: Interactive Wizard (recommended)${NC}"
echo "    sudo su - ${OPENCLAW_USER}"
echo "    openclaw onboard"
echo ""
echo -e "  ${BLUE}Option B: Manual Config${NC}"
echo "    sudo su - ${OPENCLAW_USER}"
echo "    nano ~/.openclaw/openclaw.json"
echo "    # Replace the PASTE_YOUR_*_HERE placeholders"
echo "    openclaw gateway run"
echo ""
echo -e "  ${BLUE}Option C: Claude Subscription (no API key)${NC}"
echo "    # On any machine with Claude Code CLI installed:"
echo "    claude setup-token"
echo "    # Copy the token, then on this server:"
echo "    sudo su - ${OPENCLAW_USER}"
echo "    openclaw models auth paste-token --provider anthropic"
echo ""
echo "  After configuring, pair Telegram:"
echo "    1. Message your bot on Telegram → get pairing code"
echo "    2. openclaw pair approve telegram <CODE>"
echo ""
echo "  Start as service:"
echo "    sudo systemctl start openclaw-gateway"
echo "    sudo systemctl enable openclaw-gateway"
echo ""
echo "  Switch models in Telegram chat:"
echo "    /model claude    → Claude Sonnet 4"
echo "    /model kimi      → Kimi K2.5"
echo "    /model local     → Ollama (local)"
echo "    /model haiku     → Claude Haiku (fast)"
echo ""
echo "  Monitor:"
echo "    sudo journalctl -u openclaw-gateway -f"
echo "    openclaw status"
echo "    ollama list"
echo "    tail -f /var/log/ollama-pull.log"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
