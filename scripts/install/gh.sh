#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

TAG_NAME=$(latest_github_tag cli/cli)
URL="https://github.com/cli/cli/releases/download/${TAG_NAME}/gh_${TAG_NAME#v}_linux_amd64.tar.gz"

require_command cp
TEMP_DIR=$(make_temp_dir)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

download_tar_to_dir "$URL" "$TEMP_DIR" --strip-components=1
prepare_stow_package gh
copy_dir_contents "$TEMP_DIR" "$(stow_package_dir gh)"
activate_stow_package gh
