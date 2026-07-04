#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

NVM_DIR="${NVM_DIR:-$HOME/.config/nvm}"

require_command git

if [ -d "$NVM_DIR" ] && [ ! -d "$NVM_DIR/.git" ]; then
    die "$NVM_DIR exists but is not a git checkout"
fi

if [ ! -d "$NVM_DIR" ]; then
    git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
fi

git -C "$NVM_DIR" fetch --tags origin
LATEST_TAG=$(git -C "$NVM_DIR" describe --abbrev=0 --tags --match "v[0-9]*" \
    "$(git -C "$NVM_DIR" rev-list --tags --max-count=1)")
git -C "$NVM_DIR" checkout "$LATEST_TAG"
