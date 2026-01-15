#!/bin/bash

# Check for required dependencies
for cmd in curl stow; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

echo "Install GitHub CLI"
if [ -d $HOME/.local/stow/gh ]; then
    stow -d "$HOME/.local/stow" -D gh
    rm -rf "$HOME/.local/stow/gh"
fi
TAG_NAME=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/cli/cli/releases/latest | xargs basename)
URL="https://github.com/cli/cli/releases/download/${TAG_NAME}/gh_${TAG_NAME#v}_linux_amd64.tar.gz"
mkdir -p "$HOME/.local/stow/gh" && curl -Ls "$URL" | tar xz --strip-components=1 -C "$HOME/.local/stow/gh"
stow -d "$HOME/.local/stow" --no-folding gh
