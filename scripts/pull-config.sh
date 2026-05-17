#!/bin/bash
# =============================================================================
# OpenClaw Pull Config Script
# =============================================================================
# Purpose: Pull the primary config files from the VPS into the local config directories.
# Usage: ./scripts/pull-config.sh [VPS_IP]
#
# This script:
#   1. Validates the local config directories
#   2. Downloads ~/.openclaw/openclaw.json and ~/.regulator/config.yaml from the VPS
#   3. Replaces the local copies atomically
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

VPS_USER="openclaw"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
TERRAFORM_DIR="infra/terraform/envs/prod"

OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-}"
REGULATOR_CONFIG_DIR="${REGULATOR_CONFIG_DIR:-}"

LOCAL_OPENCLAW_CONFIG_DIR="$OPENCLAW_CONFIG_DIR/config"
LOCAL_REGULATOR_CONFIG_DIR="$REGULATOR_CONFIG_DIR"

REMOTE_OPENCLAW_CONFIG_FILE="/home/openclaw/.openclaw/openclaw.json"
REMOTE_REGULATOR_CONFIG_FILE="/home/openclaw/.regulator/config.yaml"

# -----------------------------------------------------------------------------
# Validate local directories
# -----------------------------------------------------------------------------

if [[ -z "$OPENCLAW_CONFIG_DIR" ]]; then
    echo "Error: OPENCLAW_CONFIG_DIR not set"
    echo ""
    echo "Set it in config/inputs.sh or export it:"
    echo "  export OPENCLAW_CONFIG_DIR=/path/to/your/openclaw-config"
    exit 1
fi

if [[ ! -d "$LOCAL_OPENCLAW_CONFIG_DIR" ]]; then
    echo "Error: $LOCAL_OPENCLAW_CONFIG_DIR directory not found"
    echo ""
    echo "Make sure OPENCLAW_CONFIG_DIR points to your openclaw-config repository"
    exit 1
fi

if [[ -z "$REGULATOR_CONFIG_DIR" ]]; then
    echo "Error: REGULATOR_CONFIG_DIR not set"
    echo ""
    echo "Set it in config/inputs.sh or export it:"
    echo "  export REGULATOR_CONFIG_DIR=/path/to/your/regulator_config"
    exit 1
fi

if [[ ! -d "$LOCAL_REGULATOR_CONFIG_DIR" ]]; then
    echo "Error: $LOCAL_REGULATOR_CONFIG_DIR directory not found"
    echo ""
    echo "Make sure REGULATOR_CONFIG_DIR points to your regulator-config repository data directory"
    exit 1
fi

# -----------------------------------------------------------------------------
# Get VPS IP
# -----------------------------------------------------------------------------

if [[ -n "${1:-}" ]]; then
    VPS_IP="$1"
else
    if command -v terraform &> /dev/null && [[ -d "$TERRAFORM_DIR/.terraform" ]]; then
        VPS_IP=$(cd "$TERRAFORM_DIR" && terraform output -raw server_ip 2>/dev/null) || {
            echo "Error: Could not get VPS IP from terraform output."
            echo "Usage: $0 <VPS_IP>"
            exit 1
        }
    else
        echo "Error: No VPS IP provided and terraform not available."
        echo "Usage: $0 <VPS_IP>"
        exit 1
    fi
fi

LOCAL_TMP_ROOT=$(mktemp -d -t openclaw-pull-config.XXXXXX)

cleanup() {
    rm -rf "$LOCAL_TMP_ROOT"
}

trap cleanup EXIT

pull_file() {
    local remote_file="$1"
    local local_file="$2"
    local label="$3"
    local temp_file="$LOCAL_TMP_ROOT/$label"

    echo "[...] Pulling $(basename "$remote_file")..."

    ssh $SSH_OPTS "$VPS_USER@$VPS_IP" "test -f '$remote_file'"
    scp $SSH_OPTS "$VPS_USER@$VPS_IP:$remote_file" "$temp_file"
    mv "$temp_file" "$local_file"

    echo "[OK] Pulled $(basename "$local_file")"
}

echo "=== OpenClaw Pull Config ==="
echo "VPS IP: $VPS_IP"
echo "OpenClaw Config File: $LOCAL_OPENCLAW_CONFIG_DIR/openclaw.json"
echo "Regulator Config File: $LOCAL_REGULATOR_CONFIG_DIR/config.yaml"
echo ""

pull_file "$REMOTE_OPENCLAW_CONFIG_FILE" "$LOCAL_OPENCLAW_CONFIG_DIR/openclaw.json" "openclaw.json"
pull_file "$REMOTE_REGULATOR_CONFIG_FILE" "$LOCAL_REGULATOR_CONFIG_DIR/config.yaml" "config.yaml"

echo ""
echo "=== Done ==="