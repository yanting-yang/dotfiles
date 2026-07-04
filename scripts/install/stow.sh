#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

TEMP_DIR=$(mktemp -d)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

require_command curl make mktemp tar
curl -Ls "https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz" | tar xz --strip-components=1 -C "$TEMP_DIR"

cd "$TEMP_DIR"
./configure --prefix="$LOCAL_PREFIX"
make install
mkdir -p "$LOCAL_STOW_DIR"
