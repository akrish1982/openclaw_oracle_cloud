#!/bin/bash
# =============================================================================
# QUICK REFERENCE: Command Cheat Sheet
# =============================================================================
# This file is for reference — don't run it directly.

# ╔═══════════════════════════════════════════════════════════════╗
# ║  PHASE 1: DEPLOY OCI INFRASTRUCTURE (run locally)           ║
# ╚═══════════════════════════════════════════════════════════════╝

# 1. Clone / copy this project
# 2. Configure:
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars   # Fill in your OCI credentials + image OCID

# 3. Deploy:
terraform init
terraform plan
terraform apply

# 4. Get the IP:
terraform output instance_public_ip

# ╔═══════════════════════════════════════════════════════════════╗
# ║  PHASE 2: SETUP OPENCLAW (run on the OCI instance)          ║
# ╚═══════════════════════════════════════════════════════════════╝

# SSH in (use the output from terraform):
ssh -i ~/.ssh/id_rsa ubuntu@<INSTANCE_IP>

# Wait for cloud-init:
cloud-init status --wait

# Run the setup script:
sudo bash /home/ubuntu/setup-openclaw.sh

# ╔═══════════════════════════════════════════════════════════════╗
# ║  PHASE 3: CONFIGURE OPENCLAW                                ║
# ╚═══════════════════════════════════════════════════════════════╝

# --- Option A: Interactive wizard ---
sudo su - openclaw
openclaw onboard
# Follow prompts: pick Anthropic, OpenRouter, Ollama, Telegram

# --- Option B: Manual config ---
sudo su - openclaw
nano ~/.openclaw/openclaw.json
# Replace PASTE_YOUR_*_HERE with real keys
openclaw gateway run

# --- Option C: Use Claude subscription (no API key needed) ---
# On your LOCAL machine (with Claude Code CLI):
claude setup-token
# Copy the token
# Then on the OCI instance:
sudo su - openclaw
openclaw models auth paste-token --provider anthropic

# ╔═══════════════════════════════════════════════════════════════╗
# ║  PHASE 4: CONNECT TELEGRAM                                  ║
# ╚═══════════════════════════════════════════════════════════════╝

# 1. Create bot: Open Telegram, search @BotFather, /newbot
# 2. Copy the token BotFather gives you
# 3. Start the gateway:
sudo systemctl start openclaw-gateway

# 4. Message your bot in Telegram → you get a pairing code
# 5. Approve:
openclaw pair approve telegram <PAIRING_CODE>

# ╔═══════════════════════════════════════════════════════════════╗
# ║  DAILY OPERATIONS                                            ║
# ╚═══════════════════════════════════════════════════════════════╝

# --- Switch models in Telegram ---
# Just send these as messages to your bot:
/model claude     # → Claude Sonnet 4
/model opus       # → Claude Opus 4.5 (expensive)
/model haiku      # → Claude Haiku (fast, cheap)
/model kimi       # → Kimi K2.5 (cheap, strong)
/model local      # → Ollama local model (free)

# --- Monitor ---
sudo journalctl -u openclaw-gateway -f         # Gateway logs
openclaw status                                  # Status check
ollama list                                      # Ollama models
ollama ps                                        # Running models

# --- Manage ---
sudo systemctl restart openclaw-gateway          # Restart
sudo systemctl stop openclaw-gateway             # Stop
sudo systemctl enable openclaw-gateway           # Auto-start on boot

# --- Update ---
sudo npm update -g openclaw                      # Update OpenClaw
ollama pull qwen2.5-coder:14b                    # Update model

# --- Pull additional Ollama models ---
ollama pull qwen3:14b
ollama pull deepseek-r1:14b
ollama pull llama3.3:8b

# ╔═══════════════════════════════════════════════════════════════╗
# ║  TROUBLESHOOTING                                             ║
# ╚═══════════════════════════════════════════════════════════════╝

# OpenClaw not responding:
sudo systemctl restart openclaw-gateway
openclaw status

# Ollama not working:
sudo systemctl restart ollama
ollama ps

# Check cloud-init logs (first boot issues):
sudo cat /var/log/cloud-init-output.log

# Check firewall (OCI Ubuntu needs iptables flush):
sudo iptables -L -n
# If traffic blocked:
sudo iptables -F && sudo netfilter-persistent save

# Telegram pairing issues:
openclaw pair list
# Re-pair: message bot again for new code

# Disk full:
df -h
ollama rm <unused-model>
