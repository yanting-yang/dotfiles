#!/bin/bash

# Check for required dependencies
for cmd in curl stow; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

echo "Install Neovim"
if [ -d "$HOME/.local/stow/nvim-linux-x86_64" ]; then
    stow -d "$HOME/.local/stow" -D nvim-linux-x86_64
    rm -rf "$HOME/.local/stow/nvim-linux-x86_64"
fi
curl -Ls https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz | tar xz -C "$HOME/.local/stow"
stow -d "$HOME/.local/stow" --no-folding nvim-linux-x86_64

cd "$(dirname "$BASH_SOURCE")"
rsync -a --no-perms .config/nvim/ "$HOME/.config/nvim/"
