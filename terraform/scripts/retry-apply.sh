#!/bin/bash
# =============================================================================
# Retry terraform apply until ARM capacity is available
# OCI Free Tier A1 instances are often out of capacity.
# This script retries every 60 seconds until it succeeds.
# Usage: bash scripts/retry-apply.sh
# =============================================================================

set -euo pipefail

MAX_ATTEMPTS=480  # 8 hours of retrying
SLEEP_SECONDS=639 # 10 minutes plus a few more seconds
ATTEMPT=0

echo "============================================"
echo "  OCI ARM Instance - Retry Loop"
echo "  Will retry every ${SLEEP_SECONDS}s (max ${MAX_ATTEMPTS} attempts)"
echo "  Press Ctrl+C to stop"
echo "============================================"
echo ""

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] Attempt $ATTEMPT of $MAX_ATTEMPTS..."

    if terraform apply -auto-approve 2>&1 | tee /tmp/tf-apply-output.txt; then
        echo ""
        echo "============================================"
        echo "  SUCCESS! Instance created on attempt $ATTEMPT"
        echo "============================================"
        exit 0
    fi

    # Check if the error is specifically "Out of host capacity"
    if grep -q "Out of host capacity" /tmp/tf-apply-output.txt; then
        echo "  → Out of capacity. Retrying in ${SLEEP_SECONDS}s..."
        sleep $SLEEP_SECONDS
    else
        echo ""
        echo "  → Failed with a DIFFERENT error (not capacity). Stopping."
        exit 1
    fi
done

echo ""
echo "============================================"
echo "  Gave up after $MAX_ATTEMPTS attempts."
echo "  Try a different region or try again later."
echo "============================================"
exit 1
