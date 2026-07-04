#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

require_command make

TEMP_DIR=$(make_temp_dir)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

download_tar_to_dir "https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz" "$TEMP_DIR" --strip-components=1

cd "$TEMP_DIR"
./configure --prefix="$LOCAL_PREFIX"
make install
mkdir -p "$LOCAL_STOW_DIR"
