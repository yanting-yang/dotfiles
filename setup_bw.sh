#!/bin/bash

# Check for required dependencies
for cmd in bw; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

echo "Setup Bitwarden CLI"
export BW_SESSION=$(bw login --raw)
echo "export GH_TOKEN=$(bw get password GH_TOKEN)" >> "$HOME/.bashrc"
