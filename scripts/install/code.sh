#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

URL="https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64"

require_command curl tar
curl -Ls "$URL" | tar xz -C "$HOME"
rm -rf "$HOME/.vscode/"* "$HOME/.vscode-server/"*
