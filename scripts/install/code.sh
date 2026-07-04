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

require_command curl tar
curl -Ls "$URL" | tar xz -C "$HOME"
rm -rf "$HOME/.vscode/"* "$HOME/.vscode-server/"*
