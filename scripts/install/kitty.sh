#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

TAG_NAME=$(latest_github_tag kovidgoyal/kitty)
URL="https://github.com/kovidgoyal/kitty/releases/download/${TAG_NAME}/kitty-${TAG_NAME#v}-x86_64.txz"

require_command cp
TEMP_DIR=$(make_temp_dir)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

download_txz_to_dir "$URL" "$TEMP_DIR"
prepare_stow_package kitty
copy_dir_contents "$TEMP_DIR" "$(stow_package_dir kitty)"
activate_stow_package kitty
