#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

TAG_NAME=$(latest_github_tag subframe7536/maple-font)
URL="https://github.com/subframe7536/maple-font/releases/download/${TAG_NAME}/MapleMono-NF-CN-unhinted.zip"
FONT_DIR="$HOME/.local/share/fonts/maple"

require_command cp find
TEMP_DIR=$(make_temp_dir)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

download_zip_to_dir "$URL" "$TEMP_DIR"

mkdir -p "$FONT_DIR"
clear_dir_contents "$FONT_DIR"
find "$TEMP_DIR" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -exec cp -a {} "$FONT_DIR/" \;

if ! find "$FONT_DIR" -maxdepth 1 -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit | grep -q .; then
    die "no font files were extracted from $URL"
fi

printf '%s\n' "${TAG_NAME#v}" >"$FONT_DIR/.maple-version"

if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
fi
