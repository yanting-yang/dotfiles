#!/bin/bash
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
curl -s "https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz" | tar xz --strip-components=1
./configure --prefix="$HOME/.local" && make install
rm -rf "$TEMP_DIR"
mkdir -p "$HOME/.local/stow"
