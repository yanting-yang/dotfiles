#!/bin/bash
TAG_NAME=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/tmux/tmux-builds/releases/latest | xargs basename)
URL="https://github.com/tmux/tmux-builds/releases/download/$TAG_NAME/tmux-${TAG_NAME#v}-linux-x86_64.tar.gz"
mkdir -p "$HOME/.local/bin"
curl -Ls "$URL" | tar xz -C "$HOME/.local/bin"
