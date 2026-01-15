#!/bin/bash

cd "$(dirname "${BASH_SOURCE}")"

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
