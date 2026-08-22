#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

require_command git

SUB_PATH=".config/tmux/plugins/catppuccin/tmux"
SUB_DIR="$DOTFILES_DIR/$SUB_PATH"

git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$DOTFILES_DIR is not a git repository; cannot manage the catppuccin/tmux submodule"

TAG_NAME=$(latest_github_tag catppuccin/tmux)

# Check out the submodule working tree if it has not been initialized yet.
if [ ! -e "$SUB_DIR/.git" ]; then
    git -C "$DOTFILES_DIR" submodule update --init -- "$SUB_PATH"
fi

# Move the submodule to the requested release tag and stage the new pointer so
# the version bump is recorded in the parent repository.
git -C "$SUB_DIR" fetch --tags --force origin
git -C "$SUB_DIR" checkout --detach "refs/tags/$TAG_NAME"
git -C "$DOTFILES_DIR" add -- "$SUB_PATH"

printf 'catppuccin/tmux is at %s\n' "$TAG_NAME"
