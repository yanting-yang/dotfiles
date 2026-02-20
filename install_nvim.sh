#!/bin/bash
if [ -d "$HOME/.local/stow/nvim" ]; then
    stow -d "$HOME/.local/stow" -D nvim
    rm -rf "$HOME/.local/stow/nvim"
fi
URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz"
mkdir -p "$HOME/.local/stow/nvim"
curl -Ls "$URL" | tar xz --strip-components=1 -C "$HOME/.local/stow/nvim"
stow -d "$HOME/.local/stow" --no-folding nvim
