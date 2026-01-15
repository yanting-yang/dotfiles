#!/bin/bash

# Check for required dependencies
for cmd in curl unzip; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

echo "Install Bitwarden CLI"
TEMP_FILE=$(mktemp)
curl -Ls -o "$TEMP_FILE" "https://bitwarden.com/download/?app=cli&platform=linux"
unzip -q -o "$TEMP_FILE" -d "$HOME/.local/bin"
rm "$TEMP_FILE"
