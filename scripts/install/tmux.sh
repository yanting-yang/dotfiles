#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

TAG_NAME=$(latest_github_tag tmux/tmux-builds)
URL="https://github.com/tmux/tmux-builds/releases/download/$TAG_NAME/tmux-${TAG_NAME#v}-linux-x86_64.tar.gz"

require_command curl tar
mkdir -p "$LOCAL_BIN_DIR"
curl -Ls "$URL" | tar xz -C "$LOCAL_BIN_DIR"
