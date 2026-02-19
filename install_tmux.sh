#!/bin/bash

TARGET_DIR="$HOME/.local/bin"
TARGET_BIN="$TARGET_DIR/tmux"

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# 1. Check local installation
if [ -x "$TARGET_BIN" ]; then
  CURRENT_VERSION=$("$TARGET_BIN" -V | awk '{print $2}')
else
  CURRENT_VERSION=""
fi

# 2. Check what 'tmux' command resolves to
RESOLVED_TMUX=$(command -v tmux)
if [ -n "$RESOLVED_TMUX" ]; then
  # Resolve absolute path just in case, though command -v usually does it for binaries
  # We compare strings.
  if [ "$RESOLVED_TMUX" != "$TARGET_BIN" ]; then
    echo "WARNING: 'tmux' command is currently pointing to '$RESOLVED_TMUX'."
    echo "         It is NOT pointing to your local install at '$TARGET_BIN'."
    echo "         Please check your PATH variable."
  else
    echo "Success: 'tmux' command points to '$TARGET_BIN'."
  fi
fi

# 3. Get latest version
echo "Checking for latest tmux version..."
TAG_NAME=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/tmux/tmux-builds/releases/latest | xargs basename)
LATEST_VERSION="${TAG_NAME#v}"

# 4. Compare and Prompt
if [ -n "$CURRENT_VERSION" ]; then
  if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
    echo "Local tmux ($TARGET_BIN) is already at the latest version ($CURRENT_VERSION)."
    read -p "Reinstall? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      exit 0
    fi
  else
    echo "Local version: $CURRENT_VERSION"
    echo "Latest version: $LATEST_VERSION"
    read -p "Update to latest version? [Y/n] " response
    if [[ "$response" =~ ^[Nn]$ ]]; then
      exit 0
    fi
  fi
else
  echo "tmux is not installed in $TARGET_DIR."
  echo "Latest version: $LATEST_VERSION"
  read -p "Install tmux? [Y/n] " response
  if [[ "$response" =~ ^[Nn]$ ]]; then
    exit 0
  fi
fi

# 5. Install
echo "Installing tmux $LATEST_VERSION to $TARGET_DIR..."
URL="https://github.com/tmux/tmux-builds/releases/download/$TAG_NAME/tmux-${LATEST_VERSION}-linux-x86_64.tar.gz"

curl -Ls "$URL" | tar xz -C "$TARGET_DIR"

echo "Done."
