#!/bin/bash
# =============================================================================
# OpenClaw Pull Workspace Script
# =============================================================================
# Purpose: Pull a single remote file or directory from the workspace.
# Usage:
#   ./scripts/pull-workspace.sh --source <relative/path> [--dest <local/path>] [--host <vps_ip>]
#
# This script:
#   1. Validates the remote source path
#   2. Downloads it from ~/.openclaw/workspace on the VPS
#   3. Replaces the local destination atomically after extraction
# =============================================================================

set -euo pipefail

VPS_USER="openclaw"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"
TERRAFORM_DIR="infra/terraform/envs/prod"
REMOTE_WORKSPACE_DIR="/home/openclaw/.openclaw/workspace"

SOURCE_PATH=""
DEST_PATH=""
VPS_IP=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/pull-workspace.sh --source <relative/path> [--dest <local/path>] [--host <vps_ip>]

Examples:
  ./scripts/pull-workspace.sh --source agents/main/agent/prompt.txt
  ./scripts/pull-workspace.sh --source agents/main/agent --dest ./tmp/agent
  make workspace-pull SOURCE=agents/main/agent DEST=./tmp/agent
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            SOURCE_PATH="${2:-}"
            shift 2
            ;;
        --dest)
            DEST_PATH="${2:-}"
            shift 2
            ;;
        --host)
            VPS_IP="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1"
            echo ""
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$SOURCE_PATH" ]]; then
    echo "Error: --source is required"
    echo ""
    usage
    exit 1
fi

SOURCE_PATH="${SOURCE_PATH%/}"
if [[ -z "$SOURCE_PATH" ]]; then
    echo "Error: --source cannot be empty"
    exit 1
fi

if [[ "$SOURCE_PATH" = /* ]]; then
    echo "Error: --source must be relative to $REMOTE_WORKSPACE_DIR"
    exit 1
fi

if [[ "$SOURCE_PATH" == ".." || "$SOURCE_PATH" == ../* || "$SOURCE_PATH" == */.. || "$SOURCE_PATH" == */../* ]]; then
    echo "Error: --source cannot contain parent-directory traversal"
    exit 1
fi

if [[ -z "$DEST_PATH" ]]; then
    DEST_PATH=$(basename "$SOURCE_PATH")
fi

DEST_PATH="${DEST_PATH%/}"
if [[ -z "$DEST_PATH" ]]; then
    DEST_PATH=$(basename "$SOURCE_PATH")
fi

if [[ -n "$VPS_IP" ]]; then
    :
elif [[ -n "${SERVER_IP:-}" ]]; then
    VPS_IP="$SERVER_IP"
else
    if command -v terraform &> /dev/null && [[ -d "$TERRAFORM_DIR/.terraform" ]]; then
        VPS_IP=$(cd "$TERRAFORM_DIR" && terraform output -raw server_ip 2>/dev/null) || {
            echo "Error: Could not get VPS IP from terraform output."
            echo "Usage: $0 --source <relative/path> [--dest <local/path>] [--host <vps_ip>]"
            exit 1
        }
    else
        echo "Error: No VPS IP provided and terraform not available."
        echo "Usage: $0 --source <relative/path> [--dest <local/path>] [--host <vps_ip>]"
        exit 1
    fi
fi

REMOTE_TARGET="$REMOTE_WORKSPACE_DIR/$SOURCE_PATH"
REMOTE_PARENT=$(dirname "$REMOTE_TARGET")
REMOTE_NAME=$(basename "$REMOTE_TARGET")
LOCAL_TARGET="$DEST_PATH"
LOCAL_PARENT=$(dirname "$LOCAL_TARGET")

LOCAL_ARCHIVE=$(mktemp -t openclaw-workspace-pull.XXXXXX.tar.gz)
LOCAL_TMP_DIR=$(mktemp -d -t openclaw-workspace-pull.XXXXXX)

cleanup() {
    rm -f "$LOCAL_ARCHIVE"
    rm -rf "$LOCAL_TMP_DIR"
}

trap cleanup EXIT

echo "=== OpenClaw Pull Workspace ==="
echo "VPS IP: $VPS_IP"
echo "Source: $VPS_USER@$VPS_IP:$REMOTE_TARGET"
echo "Destination: $LOCAL_TARGET"
echo ""

echo "[...] Downloading archive..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" bash -s -- \
    "$REMOTE_TARGET" \
    "$REMOTE_PARENT" \
    "$REMOTE_NAME" <<'REMOTE_SCRIPT' > "$LOCAL_ARCHIVE"
set -euo pipefail

remote_target="$1"
remote_parent="$2"
remote_name="$3"

if [[ ! -e "$remote_target" ]]; then
    echo "Error: Remote source path not found: $remote_target" >&2
    exit 1
fi

tar -C "$remote_parent" -czf - "$remote_name"
REMOTE_SCRIPT

echo "[...] Extracting locally..."
mkdir -p "$LOCAL_PARENT"
tar -xzf "$LOCAL_ARCHIVE" -C "$LOCAL_TMP_DIR"
rm -rf "$LOCAL_TARGET"
mv "$LOCAL_TMP_DIR/$REMOTE_NAME" "$LOCAL_TARGET"

echo "[OK] Workspace pulled to $LOCAL_TARGET"