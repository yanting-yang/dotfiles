#!/bin/bash

cd "$(dirname "${BASH_SOURCE}")"

rsync --exclude ".git/" --exclude "bootstrap.sh" --exclude "README.md" -a --no-perms . "$HOME"
export PATH="$HOME/.local/bin:$PATH"

echo "Install stow"
TEMP_DIR=$(mktemp -d)
(
    cd "$TEMP_DIR"
    curl -s "https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz" | tar xz --strip-components=1
    ./configure --prefix="$HOME/.local" &> /dev/null
    make install &> /dev/null
)
rm -rf "$TEMP_DIR"
mkdir -p "$HOME/.local/stow"

echo "Install GitHub CLI"
if [ -d $HOME/.local/stow/gh ]; then
    stow -d "$HOME/.local/stow" -D gh
    rm -rf "$HOME/.local/stow/gh"
fi
TAG_NAME=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/cli/cli/releases/latest | xargs basename)
URL="https://github.com/cli/cli/releases/download/${TAG_NAME}/gh_${TAG_NAME#v}_linux_amd64.tar.gz"
mkdir -p "$HOME/.local/stow/gh" && curl -Ls "$URL" | tar xz --strip-components=1 -C "$HOME/.local/stow/gh"
stow -d "$HOME/.local/stow" --no-folding gh

echo "Install Bitwarden CLI"
TEMP_FILE=$(mktemp)
curl -Ls -o "$TEMP_FILE" "https://bitwarden.com/download/?app=cli&platform=linux"
unzip -q -o "$TEMP_FILE" -d "$HOME/.local/bin"
rm "$TEMP_FILE"

echo "Install Neovim"
if [ -d "$HOME/.local/stow/nvim-linux-x86_64" ]; then
    stow -d "$HOME/.local/stow" -D nvim-linux-x86_64
    rm -rf "$HOME/.local/stow/nvim-linux-x86_64"
fi
curl -Ls https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz | tar xz -C "$HOME/.local/stow"
stow -d "$HOME/.local/stow" --no-folding nvim-linux-x86_64

echo "Install tmux"
TAG_NAME=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/tmux/tmux-builds/releases/latest | xargs basename)
URL="https://github.com/tmux/tmux-builds/releases/download/$TAG_NAME/tmux-${TAG_NAME#v}-linux-x86_64.tar.gz"
curl -Ls "$URL" | tar xz -C "$HOME/.local/bin"

echo "Setup Bitwarden CLI"
export BW_SESSION=$(bw login --raw)
echo "export GH_TOKEN=$(bw get password GH_TOKEN)" >> "$HOME/.bashrc"

echo "Please run:"
echo "source ~/.bashrc"
