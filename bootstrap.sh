#!/bin/bash

cd "$(dirname "${BASH_SOURCE}")"
rm "$HOME/.profile"; ln -s "$PWD/.profile" "$HOME/.profile"
rm "$HOME/.bashrc"; ln -s "$PWD/.bashrc" "$HOME/.bashrc"
rm "$HOME/.ssh/config"; ln -s "$PWD/.ssh/config" "$HOME/.ssh/config"
rm -rf "$HOME/.config/git"; ln -s "$PWD/.config/git" "$HOME/.config/git"
rm -rf "$HOME/.config/nvim"; ln -s "$PWD/.config/nvim" "$HOME/.config/nvim"

rsync -a --no-perms .config/ "$HOME/.config/"
rsync -a --no-perms .ssh/ "$HOME/.ssh/"
rsync -a --no-perms .bashrc "$HOME/.bashrc"
export PATH="$HOME/.local/bin:$PATH"

./install_stow.sh
./install_tmux.sh
./install_nvim.sh
./install_gh.sh
./install_bw.sh
./setup_bw.sh
./install_nvm.sh

echo "Please run:"
echo "source ~/.bashrc"
