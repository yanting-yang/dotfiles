#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz"

require_command curl tar
prepare_stow_package nvim
curl -Ls "$URL" | tar xz --strip-components=1 -C "$(stow_package_dir nvim)"
activate_stow_package nvim
