#!/usr/bin/env bash
#
# bootstrap.sh - symlink dotfiles into $HOME
#
# Existing files/folders at the destination are deleted before the symlink is
# created. Existing symlinks that already point at the right place are left
# alone.
#
# Submodules (e.g. the catppuccin tmux theme) are checked out first, so a plain
# "git clone" of this repo works as well as "git clone --recurse-submodules".

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Relative paths inside the repo; each is linked to $HOME/<same path>.
LINKS=(
  ".config/kitty"
  ".config/nvim"
  ".config/tmux"
  ".ssh/config"
  ".zprofile"
  ".zshrc"
)

# Equivalent to having cloned with --recurse-submodules.
init_submodules() {
  if [ ! -f "$DOTFILES_DIR/.gitmodules" ]; then
    return
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "warn:  git not found, skipping submodules"
    return
  fi

  echo "sub:   git submodule update --init --recursive"
  git -C "$DOTFILES_DIR" submodule update --init --recursive
}

link() {
  local rel="$1"
  local src="$DOTFILES_DIR/$rel"
  local dest="$HOME/$rel"

  if [ ! -e "$src" ]; then
    echo "skip:  $rel (not in $DOTFILES_DIR)"
    return
  fi

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "ok:    $dest -> $src"
    return
  fi

  # -e is false for a broken symlink, so check -L too.
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    rm -rf "$dest"
    echo "rm:    $dest"
  fi

  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  echo "link:  $dest -> $src"
}

init_submodules

for rel in "${LINKS[@]}"; do
  link "$rel"
done
