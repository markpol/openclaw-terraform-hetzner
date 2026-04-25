#!/bin/bash
# =============================================================================
# OpenClaw Setup Auth Script
# =============================================================================
# Purpose: Authenticate the GitHub CLI inside the OpenClaw container.
# Usage: ./scripts/setup-auth.sh [VPS_IP]
#
# This script:
#   1. Reads GH_TOKEN from secrets/openclaw.env
#   2. SSHes to the VPS and enters the OpenClaw docker-compose project
#   3. Runs 'gh auth login --with-token' inside the openclaw-gateway container
#
# This stores GitHub CLI credentials inside the running container so tools that
# rely on gh can authenticate against GitHub.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

VPS_USER="openclaw"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
TERRAFORM_DIR="infra/terraform/envs/prod"

source $(dirname $0)/../secrets/openclaw.env

GH_TOKEN="${GH_TOKEN:-}"

# -----------------------------------------------------------------------------
# Validate github token
# -----------------------------------------------------------------------------

if [[ -z "$GH_TOKEN" ]]; then
    echo "Error: GH_TOKEN not set"
    echo ""
    echo "Add the following to your secrets/openclaw.env and re-run:"
    echo "export GH_TOKEN=\"your_github_person_access_token\""
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

echo "=== OpenClaw Setup Auth ==="
echo "VPS IP: $VPS_IP"
echo ""

# -----------------------------------------------------------------------------
# Push setup token to VPS
# -----------------------------------------------------------------------------

OPENCLAW_DIR="\$HOME/openclaw"

echo "[...] Authenticating with Github in Openclaw container ..."

ssh $SSH_OPTS "$VPS_USER@$VPS_IP" bash -s <<REMOTE_SCRIPT
cd "$OPENCLAW_DIR"
docker compose exec openclaw-gateway bash -c "echo $GH_TOKEN | gh auth login --with-token"
echo "[OK] Finished Github authentication."
REMOTE_SCRIPT

echo ""
echo "=== Done ==="
echo ""
