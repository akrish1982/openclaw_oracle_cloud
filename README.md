# TODO

1. Move all terraform code to terraform folder and ensure all other configurations work

# OpenClaw on Oracle Cloud (OCI) Free Tier

Deploy OpenClaw with **Ollama**, **Kimi K2.5** (via OpenRouter), and **Claude** (via Anthropic API/subscription) on an Oracle Cloud Always-Free ARM instance, connected to **Telegram**.

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Oracle Cloud VCN (10.0.0.0/16)                 │
│  ┌─────────────────────────────────────────────┐ │
│  │  Public Subnet (10.0.1.0/24)               │ │
│  │  ┌───────────────────────────────────────┐  │ │
│  │  │  Ampere A1 (4 OCPU / 24GB RAM)       │  │ │
│  │  │  Ubuntu 22.04 Minimal (ARM64)         │  │ │
│  │  │                                       │  │ │
│  │  │  ┌─────────┐  ┌───────────────────┐  │  │ │
│  │  │  │ Ollama  │  │ OpenClaw Gateway  │  │  │ │
│  │  │  │ (local) │  │  :18789            │  │  │ │
│  │  │  └─────────┘  └───────────────────┘  │  │ │
│  │  │        │              │               │  │ │
│  │  │        └──────┬───────┘               │  │ │
│  │  │               │                       │  │ │
│  │  │   ┌───────────┴────────────┐          │  │ │
│  │  │   │   Model Providers      │          │  │ │
│  │  │   │  • Ollama (local)      │          │  │ │
│  │  │   │  • Claude (Anthropic)  │          │  │ │
│  │  │   │  • Kimi K2.5 (OpenR.)  │          │  │ │
│  │  │   └───────────┬────────────┘          │  │ │
│  │  │               │                       │  │ │
│  │  │         ┌─────┴─────┐                 │  │ │
│  │  │         │ Telegram  │                 │  │ │
│  │  │         │   Bot     │                 │  │ │
│  │  │         └───────────┘                 │  │ │
│  │  └───────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

## Prerequisites

1. **Oracle Cloud Account** (Free Tier): https://www.oracle.com/cloud/free/
2. **OCI CLI configured** with API keys
3. **Terraform >= 1.5** installed locally
4. **SSH key pair** for instance access
5. **API Keys** (get these ready):
   - Anthropic API key (from https://console.anthropic.com) — OR — Claude subscription setup-token
   - OpenRouter API key (from https://openrouter.ai/keys) for Kimi K2.5
   - Telegram Bot Token (from @BotFather on Telegram)

## Quick Start

### Step 1: Gather OCI credentials

```bash
# Find your tenancy OCID and user OCID
oci iam compartment list --all --query "data[0].\"compartment-id\"" --raw-output

# Find your region
oci iam region-subscription list --query "data[0].\"region-name\"" --raw-output

# Find ARM image OCID for your region (Ubuntu 22.04 minimal aarch64)
oci compute image list \
  --compartment-id <YOUR_TENANCY_OCID> \
  --operating-system "Canonical Ubuntu" \
  --operating-system-version "22.04 Minimal aarch64" \
  --shape "VM.Standard.A1.Flex" \
  --sort-by TIMECREATED --sort-order DESC \
  --limit 1 \
  --query "data[0].id" --raw-output
```

### Step 2: Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### Step 3: Deploy infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### Step 4: SSH in and run OpenClaw setup

```bash
# Get the public IP from terraform output
ssh -i ~/.ssh/your_key ubuntu@$(terraform output -raw instance_public_ip)

# Run the OpenClaw setup script (already deployed via cloud-init)
# It will be in /home/ubuntu/setup-openclaw.sh
sudo bash /home/ubuntu/setup-openclaw.sh
```

### Step 5: Configure OpenClaw

```bash
# Run onboarding as the 'openclaw' user
sudo su - openclaw
openclaw onboard
# Follow the wizard: select providers, paste API keys, choose Telegram

# OR use the pre-built config (edit first!)
cp /home/ubuntu/openclaw-config.json ~/.openclaw/openclaw.json
nano ~/.openclaw/openclaw.json  # Add your API keys
openclaw gateway restart
```

### Step 6: Pair Telegram

1. Open your Telegram bot and send "hello"
2. You'll receive a pairing code
3. Run: `openclaw pair approve telegram <CODE>`

## File Structure

```
openclaw-oci/
├── README.md                  # This file
├── terraform/
│   ├── main.tf                # OCI provider + VCN + subnet + instance
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Useful outputs (IP, SSH command)
│   ├── terraform.tfvars.example
│   └── cloud-init.yaml        # Cloud-init to bootstrap the instance
└── scripts/
    ├── setup-openclaw.sh      # Main setup script (runs on the instance)
    └── openclaw-config.json   # Template config for multi-model routing
```

## Cost

**$0/month** on Oracle Cloud Always Free tier:
- 4 OCPU ARM Ampere A1 + 24 GB RAM (free)
- 200 GB block storage (free)
- 10 TB outbound data/month (free)

API costs depend on usage:
- **Ollama (local)**: Free, runs on the instance
- **Claude Sonnet**: ~$3/M input, $15/M output tokens (or subscription)
- **Kimi K2.5 via OpenRouter**: ~$0.60/M input tokens (very cheap)

## Important Notes

- OCI free-tier ARM instances can be hard to get in some regions due to capacity. You may need to retry or try a different region.
- Oracle may reclaim idle instances (CPU <20% over 7 days). The OpenClaw gateway + Ollama should keep it above threshold.
- Ollama on ARM64 with 24GB RAM can comfortably run models up to ~14B parameters (e.g., qwen2.5-coder:14b).
- For Kimi K2.5, using OpenRouter is the most reliable path since direct NVIDIA endpoint integration has known issues with OpenClaw (see GitHub issue #9498).

## What's included:

terraform/ — Full OCI infrastructure as code:

-VCN + public subnet + internet gateway + security list (SSH only inbound)
- ARM Ampere A1 instance (4 OCPU / 24GB RAM — all free tier)
- Cloud-init that auto-installs Node.js, Ollama, and bootstraps everything on first boot


scripts/setup-openclaw.sh — Standalone setup script that installs OpenClaw, creates a systemd service, and writes the multi-model config
scripts/openclaw-config.json — Multi-model routing config with Claude as primary, Kimi K2.5 as fallback/sub-agent, and Ollama for heartbeats (saves cost)
scripts/cheatsheet.sh — Quick reference for all commands

#### Key things to know before deploying:

Kimi K2.5 via OpenRouter is the reliable path — direct NVIDIA endpoint integration has known bugs with OpenClaw (GitHub issue #9498)
Claude subscription works via claude setup-token from Claude Code CLI (no API key needed), or you can use a standard API key
ARM instance capacity can be tight in some OCI regions — you may need to retry or pick a different region
The config uses model aliasing so you can switch models in Telegram with /model claude, /model kimi, /model local
An OCI keepalive cron prevents Oracle from reclaiming the idle instance

You'll need to fill in terraform.tfvars with your OCI credentials and the Ubuntu image OCID for your region before running terraform apply.