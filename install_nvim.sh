#!/bin/bash

# Configuration
STOW_DIR="$HOME/.local/stow"
PKG_NAME="nvim-linux-x86_64"
INSTALL_DIR="$STOW_DIR/$PKG_NAME"
BIN_PATH="$INSTALL_DIR/bin/nvim"
TARGET_BIN="$HOME/.local/bin/nvim"

# Function to get current version
get_current_version() {
    if [ -x "$BIN_PATH" ]; then
        "$BIN_PATH" --version | head -n 1 | awk '{print $2}'
    else
        echo ""
    fi
}

CURRENT_VERSION=$(get_current_version)

# Check what 'nvim' command resolves to
RESOLVED_BIN=$(command -v nvim)
if [ -n "$RESOLVED_BIN" ]; then
    # Resolve symlinks to absolute path
    REAL_RESOLVED=$(readlink -f "$RESOLVED_BIN")
    REAL_TARGET=$(readlink -f "$TARGET_BIN")

    if [ "$REAL_RESOLVED" != "$REAL_TARGET" ] && [ "$RESOLVED_BIN" != "$TARGET_BIN" ]; then
        echo "WARNING: 'nvim' command is currently pointing to '$RESOLVED_BIN'."
        echo "         It is NOT pointing to your local install at '$TARGET_BIN'."
        echo "         Please check your PATH variable."
    else
        echo "Success: 'nvim' command points to '$TARGET_BIN' (via stow)."
    fi
fi

echo "Checking for latest nvim version..."
TAG_NAME=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/neovim/neovim/releases/latest | xargs basename)
LATEST_VERSION="$TAG_NAME"

DO_INSTALL=false

if [ -n "$CURRENT_VERSION" ]; then
    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo "Local nvim ($BIN_PATH) is already at the latest version ($CURRENT_VERSION)."
        read -p "Reinstall? [y/N] " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            DO_INSTALL=true
        fi
    else
        echo "Local version: $CURRENT_VERSION"
        echo "Latest version: $LATEST_VERSION"
        read -p "Update to latest version? [Y/n] " response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            DO_INSTALL=true
        fi
    fi
else
    echo "nvim is not installed in $STOW_DIR."
    echo "Latest version: $LATEST_VERSION"
    read -p "Install nvim? [Y/n] " response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        DO_INSTALL=true
    fi
fi

if [ "$DO_INSTALL" = true ]; then
    echo "Installing nvim $LATEST_VERSION..."

    # Ensure stow directory exists
    mkdir -p "$STOW_DIR"

    # Remove old version if it exists
    if [ -d "$INSTALL_DIR" ]; then
        echo "Removing old version..."
        stow -d "$STOW_DIR" -D "$PKG_NAME" 2>/dev/null
        rm -rf "$INSTALL_DIR"
    fi

    # Download and extract new version
    URL="https://github.com/neovim/neovim/releases/download/$TAG_NAME/nvim-linux-x86_64.tar.gz"
    echo "Downloading from $URL..."
    curl -Ls "$URL" | tar xz -C "$STOW_DIR"

    # Stow the new version
    echo "Stowing new version..."
    stow -d "$STOW_DIR" --no-folding "$PKG_NAME"
fi

# Configuration Setup
CONFIG_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.config/nvim"
CONFIG_DEST="$HOME/.config/nvim"

echo "Checking nvim configuration..."

if [ -L "$CONFIG_DEST" ]; then
    # It is a symlink. Check where it points.
    # Use readlink -f to get absolute path of target
    CURRENT_LINK_TARGET=$(readlink -f "$CONFIG_DEST")
    EXPECTED_LINK_TARGET=$(readlink -f "$CONFIG_SRC")

    if [ "$CURRENT_LINK_TARGET" == "$EXPECTED_LINK_TARGET" ]; then
        echo "Configuration is already linked correctly."
    else
        echo "Configuration link exists but points to '$CURRENT_LINK_TARGET'."
        echo "Expected: '$EXPECTED_LINK_TARGET'"
        read -p "Replace with link to dotfiles? [y/N] " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm "$CONFIG_DEST"
            ln -s "$CONFIG_SRC" "$CONFIG_DEST"
            echo "Linked $CONFIG_SRC to $CONFIG_DEST"
        else
            echo "Skipping configuration setup."
        fi
    fi
elif [ -e "$CONFIG_DEST" ]; then
    # It exists and is not a symlink (likely a directory)
    echo "Configuration exists at '$CONFIG_DEST' and is not a symlink."
    read -p "Remove and replace with link to dotfiles? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DEST"
        echo "Removed old config."
        ln -s "$CONFIG_SRC" "$CONFIG_DEST"
        echo "Linked $CONFIG_SRC to $CONFIG_DEST"
    else
        echo "Skipping configuration setup."
    fi
else
    # Does not exist
    echo "Configuration not found at $CONFIG_DEST."
    echo "Creating link..."
    mkdir -p "$(dirname "$CONFIG_DEST")"
    ln -s "$CONFIG_SRC" "$CONFIG_DEST"
    echo "Linked $CONFIG_SRC to $CONFIG_DEST"
fi

echo "Done."
