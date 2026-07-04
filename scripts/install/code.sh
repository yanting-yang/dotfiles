#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"
source "$SCRIPT_DIR/../lib/code.sh"

URL="https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64"
code_running_status=0

if code_is_running; then
    printf 'code is running; skipping update.\n'
    exit 0
else
    code_running_status=$?
fi

if [ "$code_running_status" -eq 2 ]; then
    die "could not check whether code is running; skipping update"
fi

require_command cp find
TEMP_DIR=$(make_temp_dir)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

download_tar_to_dir "$URL" "$TEMP_DIR"
[ -x "$TEMP_DIR/code" ] || die "downloaded code archive did not contain an executable code binary"
cp "$TEMP_DIR/code" "$HOME/code"
clear_dir_contents "$HOME/.vscode"
clear_dir_contents "$HOME/.vscode-server"
