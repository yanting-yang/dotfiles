#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

export WELCOME_SH_NO_AUTO_RUN=1
# shellcheck source=/dev/null
source "$ROOT_DIR/welcome.sh"

fake_installer="$TMP_DIR/fake-installer.sh"
fake_marker="$TMP_DIR/fake-installed"
cat >"$fake_installer" <<'SCRIPT'
#!/usr/bin/env bash
printf 'fake installer ran\n'
printf 'yes\n' >"$FAKE_MARKER"
SCRIPT
chmod +x "$fake_installer"
export FAKE_MARKER="$fake_marker"

load_rows() {
    COMMANDS=("fake")
    PATHS=("not installed")
    CURRENTS=("unknown")
    LATESTS=("1.0.0")
    INSTALLERS=("$fake_installer")
    STATUSES=("missing")
}

row_is_actionable() {
    return 0
}

welcome_run_tool_installer fake 0 >/dev/null
[ "$(cat "$fake_marker")" = "yes" ]

welcome_load_nvm() {
    return 0
}

nvm() {
    printf 'nvm %s\n' "$*"
}

output=$(welcome_run_nvm_action nvm_use v24.0.0)
case "$output" in
    *"Using Node v24.0.0"*);;
    *)
        printf 'missing nvm use output\n' >&2
        exit 1
        ;;
esac
