#!/bin/bash
# =============================================================================
# OpenClaw Gateway Watchdog with Telegram Notifications
#
# Features:
#   - Checks gateway health every 2 minutes (not just systemd status)
#   - Tests actual HTTP endpoint responsiveness
#   - Auto-restarts if unresponsive
#   - Sends Telegram notification on restart
#   - Logs all actions to /var/log/openclaw-watchdog.log
#
# Installation:
#   1. Copy this script to the server:
#      scp openclaw-watchdog.sh ubuntu@YOUR_IP:/home/ubuntu/
#   2. SSH in and run:
#      sudo bash /home/ubuntu/openclaw-watchdog.sh --install
#   3. Configure your Telegram chat_id (see instructions after install)
# =============================================================================

set -euo pipefail

# --- Configuration ---
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"  # Set via env or edit below
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"       # Your chat ID (run --get-chat-id to find it)
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
HEALTH_ENDPOINT="http://127.0.0.1:${GATEWAY_PORT}/health"
LOG_FILE="/var/log/openclaw-watchdog.log"
MAX_LOG_SIZE=10485760  # 10MB

# --- Functions ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

send_telegram() {
  local message="$1"
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" \
      -d text="$message" \
      -d parse_mode="Markdown" > /dev/null 2>&1 || true
  fi
}

check_gateway() {
  # First check if systemd service is running
  if ! systemctl is-active --quiet openclaw-gateway; then
    echo "systemd_down"
    return
  fi

  # Then check if it responds to HTTP (with 5s timeout)
  if curl -sf --max-time 5 "$HEALTH_ENDPOINT" > /dev/null 2>&1; then
    echo "healthy"
  else
    # Try a simple TCP connection as fallback
    if timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/${GATEWAY_PORT}" 2>/dev/null; then
      echo "responding"
    else
      echo "unresponsive"
    fi
  fi
}

restart_gateway() {
  log "RESTARTING: OpenClaw gateway..."
  systemctl restart openclaw-gateway
  sleep 10  # Give it time to start

  # Verify it came back
  local status
  status=$(check_gateway)
  if [[ "$status" == "healthy" || "$status" == "responding" ]]; then
    log "RECOVERED: Gateway is back online"
    send_telegram "✅ *OpenClaw Gateway Recovered*
🔄 Auto-restarted successfully
📍 $(hostname)
⏰ $(date '+%Y-%m-%d %H:%M:%S')"
    return 0
  else
    log "FAILED: Gateway still not responding after restart"
    send_telegram "❌ *OpenClaw Gateway DOWN*
🔄 Auto-restart attempted but failed
📍 $(hostname)
⏰ $(date '+%Y-%m-%d %H:%M:%S')
⚠️ Manual intervention required"
    return 1
  fi
}

rotate_log() {
  if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt $MAX_LOG_SIZE ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    log "Log rotated"
  fi
}

# --- Commands ---
case "${1:-}" in
  --install)
    echo "Installing OpenClaw Watchdog..."

    # Copy script to /usr/local/bin
    cp "$0" /usr/local/bin/openclaw-watchdog
    chmod +x /usr/local/bin/openclaw-watchdog

    # Create config file for credentials
    cat > /etc/openclaw-watchdog.conf << 'EOF'
# OpenClaw Watchdog Configuration
# Edit this file to add your Telegram credentials

# Your Telegram Bot Token (from @BotFather)
TELEGRAM_BOT_TOKEN=""

# Your Telegram Chat ID (run: openclaw-watchdog --get-chat-id)
TELEGRAM_CHAT_ID=""

# Gateway port (default: 18789)
GATEWAY_PORT="18789"
EOF

    # Create systemd timer (runs every 2 minutes)
    cat > /etc/systemd/system/openclaw-watchdog.service << 'EOF'
[Unit]
Description=OpenClaw Gateway Watchdog
After=openclaw-gateway.service

[Service]
Type=oneshot
EnvironmentFile=/etc/openclaw-watchdog.conf
ExecStart=/usr/local/bin/openclaw-watchdog --check
EOF

    cat > /etc/systemd/system/openclaw-watchdog.timer << 'EOF'
[Unit]
Description=Run OpenClaw Watchdog every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF

    # Remove old cron-based health check
    rm -f /etc/cron.d/openclaw-health

    systemctl daemon-reload
    systemctl enable openclaw-watchdog.timer
    systemctl start openclaw-watchdog.timer

    echo ""
    echo "✓ Watchdog installed and running!"
    echo ""
    echo "Next steps:"
    echo "  1. Get your Telegram chat ID:"
    echo "     - Message your bot on Telegram (any message)"
    echo "     - Run: openclaw-watchdog --get-chat-id"
    echo ""
    echo "  2. Configure Telegram notifications:"
    echo "     sudo nano /etc/openclaw-watchdog.conf"
    echo "     # Add your TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID"
    echo ""
    echo "  3. Test it works:"
    echo "     sudo openclaw-watchdog --test"
    echo ""
    echo "Logs: tail -f $LOG_FILE"
    echo "Status: systemctl list-timers openclaw-watchdog.timer"
    ;;

  --get-chat-id)
    # Read token from config if not set
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]] && [[ -f /etc/openclaw-watchdog.conf ]]; then
      source /etc/openclaw-watchdog.conf
    fi

    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
      echo "Error: TELEGRAM_BOT_TOKEN not set"
      echo "Edit /etc/openclaw-watchdog.conf first, or export TELEGRAM_BOT_TOKEN"
      exit 1
    fi

    echo "Fetching recent messages to your bot..."
    echo "(Make sure you've sent a message to your bot first)"
    echo ""

    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates")

    if echo "$response" | grep -q '"ok":true'; then
      chat_ids=$(echo "$response" | grep -oP '"chat":\{"id":\K[0-9-]+' | sort -u)
      if [[ -n "$chat_ids" ]]; then
        echo "Found chat ID(s):"
        echo "$chat_ids"
        echo ""
        echo "Add one of these to /etc/openclaw-watchdog.conf as TELEGRAM_CHAT_ID"
      else
        echo "No messages found. Please:"
        echo "  1. Open Telegram and find your bot"
        echo "  2. Send it any message (like 'hi')"
        echo "  3. Run this command again"
      fi
    else
      echo "Error getting updates. Check your bot token."
      echo "Response: $response"
    fi
    ;;

  --check)
    # Load config
    if [[ -f /etc/openclaw-watchdog.conf ]]; then
      source /etc/openclaw-watchdog.conf
    fi

    rotate_log

    status=$(check_gateway)
    case "$status" in
      healthy|responding)
        # All good, no action needed
        ;;
      systemd_down)
        log "ALERT: Gateway systemd service is down"
        restart_gateway
        ;;
      unresponsive)
        log "ALERT: Gateway is unresponsive (systemd running but not responding)"
        restart_gateway
        ;;
    esac
    ;;

  --test)
    # Load config
    if [[ -f /etc/openclaw-watchdog.conf ]]; then
      source /etc/openclaw-watchdog.conf
    fi

    echo "Testing watchdog..."
    echo ""

    echo "1. Checking gateway status..."
    status=$(check_gateway)
    echo "   Status: $status"
    echo ""

    echo "2. Testing Telegram notification..."
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
      send_telegram "🧪 *Watchdog Test*
This is a test notification from OpenClaw Watchdog.
📍 $(hostname)
⏰ $(date '+%Y-%m-%d %H:%M:%S')"
      echo "   Sent! Check your Telegram."
    else
      echo "   Skipped: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not configured"
      echo "   Edit /etc/openclaw-watchdog.conf to enable notifications"
    fi
    echo ""

    echo "3. Timer status:"
    systemctl list-timers openclaw-watchdog.timer --no-pager 2>/dev/null || echo "   Timer not installed"
    ;;

  --status)
    echo "=== OpenClaw Watchdog Status ==="
    echo ""
    echo "Timer:"
    systemctl list-timers openclaw-watchdog.timer --no-pager 2>/dev/null || echo "Not installed"
    echo ""
    echo "Recent log entries:"
    tail -20 "$LOG_FILE" 2>/dev/null || echo "No logs yet"
    ;;

  --uninstall)
    echo "Removing OpenClaw Watchdog..."
    systemctl stop openclaw-watchdog.timer 2>/dev/null || true
    systemctl disable openclaw-watchdog.timer 2>/dev/null || true
    rm -f /etc/systemd/system/openclaw-watchdog.service
    rm -f /etc/systemd/system/openclaw-watchdog.timer
    rm -f /usr/local/bin/openclaw-watchdog
    rm -f /etc/openclaw-watchdog.conf
    systemctl daemon-reload
    echo "✓ Watchdog removed"
    ;;

  *)
    echo "OpenClaw Gateway Watchdog"
    echo ""
    echo "Usage:"
    echo "  --install      Install watchdog as systemd timer"
    echo "  --get-chat-id  Find your Telegram chat ID"
    echo "  --check        Run a health check (used by timer)"
    echo "  --test         Test watchdog and send test notification"
    echo "  --status       Show watchdog status and recent logs"
    echo "  --uninstall    Remove watchdog"
    ;;
esac
