#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

TAG_NAME=$(latest_github_tag cli/cli)
URL="https://github.com/cli/cli/releases/download/${TAG_NAME}/gh_${TAG_NAME#v}_linux_amd64.tar.gz"

require_command curl tar
prepare_stow_package gh
curl -Ls "$URL" | tar xz --strip-components=1 -C "$(stow_package_dir gh)"
activate_stow_package gh
