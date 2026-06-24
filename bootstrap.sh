#!/bin/bash
cd "$(dirname "${BASH_SOURCE}")"
rm "$HOME/.profile"; ln -s "$PWD/.profile" "$HOME/.profile"
rm "$HOME/.bash"*; ln -s "$PWD/.bashrc" "$HOME/.bashrc"
rm "$HOME/.ssh/config"; ln -s "$PWD/.ssh/config" "$HOME/.ssh/config"
mkdir -p "$HOME/.config"
rm -rf "$HOME/.config/git"; ln -s "$PWD/.config/git" "$HOME/.config/git"
rm -rf "$HOME/.config/nvim"; ln -s "$PWD/.config/nvim" "$HOME/.config/nvim"
