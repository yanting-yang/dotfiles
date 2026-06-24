#!/bin/bash
URL="https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64"
curl -Ls "$URL" | tar xz -C "$HOME"
rm -rf "$HOME/.vscode/"* "$HOME/.vscode-server/"*
