#!/bin/bash

# Check for required dependencies
for cmd in curl git rsync; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

cd "$(dirname "${BASH_SOURCE}")"

echo "Install tmux"
TAG_NAME=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/tmux/tmux-builds/releases/latest | xargs basename)
URL="https://github.com/tmux/tmux-builds/releases/download/$TAG_NAME/tmux-${TAG_NAME#v}-linux-x86_64.tar.gz"
curl -Ls "$URL" | tar xz -C "$HOME/.local/bin"

if [ -d "$HOME/.config/tmux/plugins/catppuccin" ]; then
    rm -rf "$HOME/.config/tmux/plugins/catppuccin"
fi
mkdir -p "$HOME/.config/tmux/plugins/catppuccin"
git clone -b v2.1.3 https://github.com/catppuccin/tmux.git "$HOME/.config/tmux/plugins/catppuccin/tmux"

rsync -a --no-perms .config/tmux/ "$HOME/.config/tmux/"
