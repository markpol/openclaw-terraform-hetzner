#!/bin/bash
# =============================================================================
# OpenClaw Push Workspace Script
# =============================================================================
# Purpose: Push a single local file or directory into the remote workspace.
# Usage:
#   ./scripts/push-workspace.sh --source <path> [--dest <relative/path>] [--host <vps_ip>]
#
# This script:
#   1. Validates the local source path
#   2. Uploads it to ~/.openclaw/workspace on the VPS
#   3. Replaces the remote target atomically after extraction
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
  ./scripts/push-workspace.sh --source <path> [--dest <relative/path>] [--host <vps_ip>]

Examples:
  ./scripts/push-workspace.sh --source ./tmp/prompt.txt
  ./scripts/push-workspace.sh --source ./my-workspace --dest agents/main/agent
  make workspace-push SOURCE=./tmp/prompt.txt DEST=agents/main/agent/prompt.txt
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

if [[ ! -e "$SOURCE_PATH" ]]; then
    echo "Error: Source path not found: $SOURCE_PATH"
    exit 1
fi

if [[ -z "$DEST_PATH" ]]; then
    DEST_PATH=$(basename "$SOURCE_PATH")
fi

DEST_PATH="${DEST_PATH%/}"
if [[ -z "$DEST_PATH" ]]; then
    DEST_PATH=$(basename "$SOURCE_PATH")
fi

if [[ "$DEST_PATH" = /* ]]; then
    echo "Error: --dest must be relative to $REMOTE_WORKSPACE_DIR"
    exit 1
fi

if [[ "$DEST_PATH" == ".." || "$DEST_PATH" == ../* || "$DEST_PATH" == */.. || "$DEST_PATH" == */../* ]]; then
    echo "Error: --dest cannot contain parent-directory traversal"
    exit 1
fi

if [[ -n "$VPS_IP" ]]; then
    :
elif [[ -n "${SERVER_IP:-}" ]]; then
    VPS_IP="$SERVER_IP"
else
    if command -v terraform &> /dev/null && [[ -d "$TERRAFORM_DIR/.terraform" ]]; then
        VPS_IP=$(cd "$TERRAFORM_DIR" && terraform output -raw server_ip 2>/dev/null) || {
            echo "Error: Could not get VPS IP from terraform output."
            echo "Usage: $0 --source <path> [--dest <relative/path>] [--host <vps_ip>]"
            exit 1
        }
    else
        echo "Error: No VPS IP provided and terraform not available."
        echo "Usage: $0 --source <path> [--dest <relative/path>] [--host <vps_ip>]"
        exit 1
    fi
fi

SOURCE_PATH="${SOURCE_PATH%/}"
SOURCE_NAME=$(basename "$SOURCE_PATH")
SOURCE_PARENT=$(dirname "$SOURCE_PATH")
REMOTE_TARGET="$REMOTE_WORKSPACE_DIR/$DEST_PATH"
REMOTE_PARENT=$(dirname "$REMOTE_TARGET")

LOCAL_ARCHIVE=$(mktemp -t openclaw-workspace-push.XXXXXX.tar.gz)
REMOTE_ARCHIVE="/tmp/openclaw-workspace-push-$$.tar.gz"

cleanup() {
    rm -f "$LOCAL_ARCHIVE"
}

trap cleanup EXIT

echo "=== OpenClaw Push Workspace ==="
echo "VPS IP: $VPS_IP"
echo "Source: $SOURCE_PATH"
echo "Target: $VPS_USER@$VPS_IP:$REMOTE_TARGET"
echo ""

echo "[...] Packaging source..."
tar -C "$SOURCE_PARENT" -czf "$LOCAL_ARCHIVE" "$SOURCE_NAME"

echo "[...] Uploading archive..."
scp $SSH_OPTS "$LOCAL_ARCHIVE" "$VPS_USER@$VPS_IP:$REMOTE_ARCHIVE"

echo "[...] Updating remote workspace..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" bash -s -- \
    "$REMOTE_WORKSPACE_DIR" \
    "$REMOTE_PARENT" \
    "$REMOTE_TARGET" \
    "$SOURCE_NAME" \
    "$REMOTE_ARCHIVE" <<'REMOTE_SCRIPT'
set -euo pipefail

remote_workspace_dir="$1"
remote_parent="$2"
remote_target="$3"
source_name="$4"
remote_archive="$5"
tmp_dir=$(mktemp -d)

cleanup_remote() {
    rm -rf "$tmp_dir"
    rm -f "$remote_archive"
}

trap cleanup_remote EXIT

mkdir -p "$remote_workspace_dir"
mkdir -p "$remote_parent"
tar -xzf "$remote_archive" -C "$tmp_dir"
rm -rf "$remote_target"
mv "$tmp_dir/$source_name" "$remote_target"
REMOTE_SCRIPT

echo "[OK] Workspace updated at $REMOTE_TARGET"
