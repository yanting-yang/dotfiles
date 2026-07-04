#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

TAG_NAME=$(latest_github_tag tmux/tmux-builds)
URL="https://github.com/tmux/tmux-builds/releases/download/$TAG_NAME/tmux-${TAG_NAME#v}-linux-x86_64.tar.gz"

require_command cp
TEMP_DIR=$(make_temp_dir)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

download_tar_to_dir "$URL" "$TEMP_DIR"
mkdir -p "$LOCAL_BIN_DIR"
copy_dir_contents "$TEMP_DIR" "$LOCAL_BIN_DIR"
