#!/bin/bash
NVM_DIR="$HOME/.config/nvm"
if [ ! -d "$NVM_DIR" ]; then
    git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
fi
cd "$NVM_DIR"
git fetch --tags origin
git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1)`
