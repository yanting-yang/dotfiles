#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz"

require_command cp
TEMP_DIR=$(make_temp_dir)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

download_tar_to_dir "$URL" "$TEMP_DIR" --strip-components=1
prepare_stow_package nvim
copy_dir_contents "$TEMP_DIR" "$(stow_package_dir nvim)"
activate_stow_package nvim
