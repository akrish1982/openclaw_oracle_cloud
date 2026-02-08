#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  OpenClaw Setup Script"
echo "  Oracle Cloud ARM64 Instance"
echo "============================================"

# --- Verify prerequisites ---
echo "[1/5] Checking prerequisites..."
node --version || { echo "ERROR: Node.js not found"; exit 1; }
ollama --version || { echo "ERROR: Ollama not found"; exit 1; }
echo "✓ Node.js and Ollama installed"

# --- Install OpenClaw ---
echo "[2/5] Installing OpenClaw..."
if ! command -v openclaw &>/dev/null; then
  npm install -g openclaw
  echo "✓ OpenClaw installed"
else
  echo "✓ OpenClaw already installed"
fi
openclaw --version

# --- Wait for Ollama model to finish pulling ---
echo "[3/5] Checking Ollama model status..."
echo "  (This may take a while if the model is still downloading)"
while ! ollama list | grep -q "qwen2.5-coder"; do
  echo "  Waiting for model download..."
  sleep 30
done
echo "✓ Ollama model ready"

# --- Set up systemd service for OpenClaw ---
echo "[4/5] Creating systemd service..."
cat > /etc/systemd/system/openclaw-gateway.service << 'SYSTEMD'
[Unit]
Description=OpenClaw Gateway
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=openclaw
WorkingDirectory=/home/openclaw
ExecStart=/usr/bin/openclaw gateway run
Restart=always
RestartSec=30
Environment=NODE_ENV=production
Environment=HOME=/home/openclaw

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
echo "✓ Systemd service created"

# --- Create cron job to restart gateway (stability) ---
echo "[5/5] Setting up health check cron..."
cat > /etc/cron.d/openclaw-health << 'CRON'
# Restart OpenClaw gateway if it's not responding (every 30 min)
*/30 * * * * root systemctl is-active --quiet openclaw-gateway || systemctl restart openclaw-gateway
CRON
echo "✓ Health check cron installed"

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Switch to openclaw user:  sudo su - openclaw"
echo "  2. Run onboarding wizard:    openclaw onboard"
echo "     - Select Anthropic + OpenRouter as providers"
echo "     - Paste your API keys when prompted"
echo "     - Select Telegram as your channel"
echo "     - Paste your Telegram bot token"
echo ""
echo "  OR manually configure:"
echo "  3. Copy config template:     cp /home/ubuntu/openclaw-config.json ~/.openclaw/openclaw.json"
echo "  4. Edit with your API keys:  nano ~/.openclaw/openclaw.json"
echo "  5. Start the gateway:        openclaw gateway run"
echo "     (or: sudo systemctl start openclaw-gateway)"
echo ""
echo "  6. Open Telegram, message your bot, get pairing code"
echo "  7. Approve pairing:          openclaw pair approve telegram <CODE>"
echo ""