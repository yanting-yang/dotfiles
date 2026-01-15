#!/bin/bash

# Check for required dependencies
for cmd in curl make; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

echo "Install stow"
TEMP_DIR=$(mktemp -d)
(
    cd "$TEMP_DIR"
    curl -s "https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz" | tar xz --strip-components=1
    ./configure --prefix="$HOME/.local" && make install
)
rm -rf "$TEMP_DIR"
mkdir -p "$HOME/.local/stow"
