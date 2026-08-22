#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

export WELCOME_SH_NO_AUTO_RUN=1
# shellcheck source=/dev/null
source "$ROOT_DIR/welcome.sh"

ORIGINAL_HOME="$HOME"
ORIGINAL_PATH="$PATH"
if [ "${NVM_DIR+x}" ]; then
    ORIGINAL_NVM_DIR="$NVM_DIR"
    HAD_NVM_DIR=1
else
    ORIGINAL_NVM_DIR=""
    HAD_NVM_DIR=0
fi

# Welcome must select the repository's Node major before validating or
# launching the app. Keep this in a subshell so its fake runtime cannot leak
# into the remaining bridge tests.
mkdir -p "$TMP_DIR/runtime-node-modules/ink" "$TMP_DIR/runtime-node-modules/react"
: >"$TMP_DIR/runtime-cli.mjs"
(
    WELCOME_NODE_MODULES="$TMP_DIR/runtime-node-modules"
    WELCOME_APP="$TMP_DIR/runtime-cli.mjs"
    RUNTIME_ACTIVE_MAJOR=22
    RUNTIME_SELECTED_PATH="$TMP_DIR/runtime-node-24/bin"
    RUNTIME_LOG="$TMP_DIR/runtime-success.log"
    : >"$RUNTIME_LOG"

    welcome_load_nvm() {
        printf 'load-nvm\n' >>"$RUNTIME_LOG"
    }

    nvm() {
        printf 'nvm:%s\n' "$*" >>"$RUNTIME_LOG"
        case "$*" in
            "use --silent 24")
                RUNTIME_ACTIVE_MAJOR=24
                PATH="$RUNTIME_SELECTED_PATH:$PATH"
                export PATH
                ;;
            *)
                return 91
                ;;
        esac
    }

    node() {
        printf 'node:%s\n' "$*" >>"$RUNTIME_LOG"
        case "${1:-}" in
            -p)
                printf '%s\n' "$RUNTIME_ACTIVE_MAJOR"
                ;;
            --version)
                printf 'v%s.1.0\n' "$RUNTIME_ACTIVE_MAJOR"
                ;;
            *)
                return 92
                ;;
        esac
    }

    welcome_require_runtime
    [ "$RUNTIME_ACTIVE_MAJOR" -eq 24 ]
    [ "${PATH%%:*}" = "$RUNTIME_SELECTED_PATH" ]
    [ "$(sed -n '1p' "$RUNTIME_LOG")" = "load-nvm" ]
    [ "$(sed -n '2p' "$RUNTIME_LOG")" = "nvm:use --silent 24" ]
    case "$(sed -n '3p' "$RUNTIME_LOG")" in
        node:-p*) ;;
        *)
            printf 'Node was validated before nvm selected the Welcome runtime\n' >&2
            exit 1
            ;;
    esac
)

# A failed local activation must stop before Node validation. Starting Welcome
# must not turn that failure into an implicit install or remote version check.
(
    WELCOME_NODE_MODULES="$TMP_DIR/runtime-node-modules"
    WELCOME_APP="$TMP_DIR/runtime-cli.mjs"
    RUNTIME_LOG="$TMP_DIR/runtime-failure.log"
    RUNTIME_OUTPUT="$TMP_DIR/runtime-failure.out"
    : >"$RUNTIME_LOG"

    welcome_load_nvm() {
        printf 'load-nvm\n' >>"$RUNTIME_LOG"
    }

    nvm() {
        printf 'nvm:%s\n' "$*" >>"$RUNTIME_LOG"
        case "$*" in
            "use --silent 24")
                return 42
                ;;
            install*|version-remote*)
                return 93
                ;;
            *)
                return 94
                ;;
        esac
    }

    node() {
        printf 'node:%s\n' "$*" >>"$RUNTIME_LOG"
        return 95
    }

    if welcome_require_runtime >"$RUNTIME_OUTPUT" 2>&1; then
        printf 'Welcome accepted a failed nvm runtime activation\n' >&2
        exit 1
    fi
    [ -s "$RUNTIME_OUTPUT" ]
    [ "$(sed -n '1p' "$RUNTIME_LOG")" = "load-nvm" ]
    [ "$(sed -n '2p' "$RUNTIME_LOG")" = "nvm:use --silent 24" ]
    [ "$(wc -l <"$RUNTIME_LOG")" -eq 2 ]
    if grep -Eq '^nvm:(install|version-remote)' "$RUNTIME_LOG"; then
        printf 'Welcome performed a network-capable Node action during startup\n' >&2
        exit 1
    fi
    if grep -q '^node:' "$RUNTIME_LOG"; then
        printf 'Welcome validated Node after nvm activation failed\n' >&2
        exit 1
    fi
)

# Direct Bash execution must take the executable branch rather than reaching a
# top-level return intended for sourced shells.
mkdir -p "$TMP_DIR/direct-home" "$TMP_DIR/direct-nvm" "$TMP_DIR/direct-bin"
cat >"$TMP_DIR/direct-bin/node" <<'SCRIPT'
#!/bin/sh
case "${1:-}" in
    -p)
        printf '24\n'
        ;;
    --version)
        printf 'v24.1.0\n'
        ;;
    *)
        printf 'direct welcome app launched\n'
        ;;
esac
SCRIPT
chmod +x "$TMP_DIR/direct-bin/node"
cat >"$TMP_DIR/direct-nvm/nvm.sh" <<'SCRIPT'
nvm() {
    if [ "$*" = "use --silent 24" ]; then
        PATH="$DIRECT_NODE_BIN:$PATH"
        export PATH
        return 0
    fi
    return 91
}
SCRIPT
direct_output=$(WELCOME_SH_NO_AUTO_RUN=0 \
    HOME="$TMP_DIR/direct-home" \
    NVM_DIR="$TMP_DIR/direct-nvm" \
    DIRECT_NODE_BIN="$TMP_DIR/direct-bin" \
    bash "$ROOT_DIR/welcome.sh")
grep -Fq 'direct welcome app launched' <<<"$direct_output"

mkdir -p "$TMP_DIR/home" "$TMP_DIR/bin"
HOME="$TMP_DIR/home"
NVM_DIR="$TMP_DIR/nvm"
PATH="$TMP_DIR/bin"

update_checks=0
get_github_latest() {
    update_checks=$((update_checks + 1))
    printf '9.9.9'
}
get_stow_latest() {
    update_checks=$((update_checks + 1))
    printf '9.9.9'
}

load_rows 1
[ "$update_checks" -eq 0 ]

# Exercise Node's real status-row path before the action tests replace
# load_rows with focused fixtures.
PATH="$ORIGINAL_PATH"
mkdir -p "$NVM_DIR" "$TMP_DIR/status-cache"
cat >"$TMP_DIR/bin/node" <<'SCRIPT'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    printf 'v24.1.0\n'
    exit 0
fi
exit 2
SCRIPT
chmod +x "$TMP_DIR/bin/node"
ln -s "$(command -v mkdir)" "$TMP_DIR/bin/mkdir"
STATUS_NVM_LOG="$TMP_DIR/status-nvm.log"
: >"$STATUS_NVM_LOG"
cat >"$NVM_DIR/nvm.sh" <<'SCRIPT'
nvm() {
    if [ -n "${STATUS_NVM_LOG:-}" ]; then
        printf '%s\n' "$*" >>"$STATUS_NVM_LOG"
    fi

    case "${1:-}" in
        --version)
            printf '0.40.3\n'
            ;;
        version-remote)
            [ "${2:-}" = "24" ] || return 91
            printf 'v24.2.0\n'
            ;;
        *)
            return 92
            ;;
    esac
}
SCRIPT
PATH="$TMP_DIR/bin"

status_assert_node_row() {
    local expected_latest="$1" expected_status="$2" i

    STATUS_NODE_INDEX=-1
    for i in "${!COMMANDS[@]}"; do
        if [ "${COMMANDS[$i]}" = "node" ]; then
            STATUS_NODE_INDEX="$i"
            break
        fi
    done

    [ "$STATUS_NODE_INDEX" -ge 0 ]
    [ "${PATHS[$STATUS_NODE_INDEX]}" != "not installed" ]
    [ "${CURRENTS[$STATUS_NODE_INDEX]}" = "24.1.0" ]
    [ "${LATESTS[$STATUS_NODE_INDEX]}" = "$expected_latest" ]
    [ "${STATUSES[$STATUS_NODE_INDEX]}" = "$expected_status" ]
}

status_assert_node_remote_calls() {
    local expected="$1" call count=0

    while IFS= read -r call; do
        case "$call" in
            version-remote*)
                [ "$call" = "version-remote 24" ] || {
                    printf 'Node status checked an unexpected remote version: %s\n' "$call" >&2
                    return 1
                }
                count=$((count + 1))
                ;;
        esac
    done <"$STATUS_NVM_LOG"

    [ "$count" -eq "$expected" ]
}

WELCOME_UPDATE_CACHE_DIR="$TMP_DIR/status-cache" load_rows 0
status_assert_node_row unchecked installed
status_assert_node_remote_calls 0
if row_is_actionable "$STATUS_NODE_INDEX"; then
    printf 'Node was actionable before remote versions were requested\n' >&2
    exit 1
fi

WELCOME_UPDATE_CACHE_DIR="$TMP_DIR/status-cache" load_rows 1
status_assert_node_row 24.2.0 update
status_assert_node_remote_calls 1
row_is_actionable "$STATUS_NODE_INDEX"
IFS= read -r cached_node_latest <"$TMP_DIR/status-cache/node-24.latest"
[ "$cached_node_latest" = "24.2.0" ]

WELCOME_UPDATE_CACHE_DIR="$TMP_DIR/status-cache" load_rows 1
status_assert_node_row 24.2.0 update
status_assert_node_remote_calls 1

[ "$(row_status /tmp/node 24.2.0 24.1.0 node)" = "current" ]
CURRENTS[$STATUS_NODE_INDEX]="24.2.0"
LATESTS[$STATUS_NODE_INDEX]="24.1.0"
if row_is_actionable "$STATUS_NODE_INDEX"; then
    printf 'Node was actionable for a same-major downgrade\n' >&2
    exit 1
fi

: >"$NVM_DIR/nvm.sh"
unset -f nvm

PATH="$ORIGINAL_PATH"
cat >"$HOME/code" <<'SCRIPT'
#!/usr/bin/env bash
printf 'code 1.0.0\n'
SCRIPT
chmod +x "$HOME/code"
code_is_running() {
    return 1
}

welcome_run_tool_uninstaller code >/dev/null
[ ! -e "$HOME/code" ]

# The maple font row reports its marker version and uninstalls by removing the
# managed font directory.
maple_font_dir="$HOME/.local/share/fonts/maple"
mkdir -p "$maple_font_dir"
: >"$maple_font_dir/MapleMonoNF-Regular.ttf"
printf '7.9\n' >"$maple_font_dir/.maple-version"

WELCOME_UPDATE_CACHE_DIR="$TMP_DIR/status-cache" load_rows 0
MAPLE_INDEX=-1
for i in "${!COMMANDS[@]}"; do
    if [ "${COMMANDS[$i]}" = "maple" ]; then
        MAPLE_INDEX="$i"
        break
    fi
done
[ "$MAPLE_INDEX" -ge 0 ]
[ "${PATHS[$MAPLE_INDEX]}" = "$maple_font_dir" ]
[ "${CURRENTS[$MAPLE_INDEX]}" = "7.9" ]
[ "${STATUSES[$MAPLE_INDEX]}" = "installed" ]
row_is_uninstallable "$MAPLE_INDEX"

welcome_run_tool_uninstaller maple >/dev/null
[ ! -d "$maple_font_dir" ]

HOME="$ORIGINAL_HOME"
PATH="$ORIGINAL_PATH"
if [ "$HAD_NVM_DIR" -eq 1 ]; then
    NVM_DIR="$ORIGINAL_NVM_DIR"
    export NVM_DIR
else
    unset NVM_DIR
fi

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

FAKE_NVM_LOG="$TMP_DIR/fake-nvm.log"
FAKE_NODE_CURRENT=""
FAKE_NODE_LATEST=""
FAKE_NODE_DEFAULT_TARGET=""
FAKE_NODE_REPORTED_OVERRIDE=""
FAKE_NVM_FAIL=""
FAKE_NODE_INSTALLED=()

fake_node_is_installed() {
    local candidate="$1" installed

    for installed in "${FAKE_NODE_INSTALLED[@]}"; do
        [ "$installed" = "$candidate" ] && return 0
    done

    return 1
}

fake_node_latest_installed_for_major() {
    local major="$1" installed latest="N/A"

    for installed in "${FAKE_NODE_INSTALLED[@]}"; do
        case "$installed" in
            "v$major".*)
                latest="$installed"
                ;;
        esac
    done

    printf '%s' "$latest"
}

fake_node_resolve_version() {
    local requested="$1"

    case "$requested" in
        default)
            fake_node_resolve_version "$FAKE_NODE_DEFAULT_TARGET"
            ;;
        [0-9]*)
            if [[ "$requested" =~ ^[0-9]+$ ]]; then
                fake_node_latest_installed_for_major "$requested"
            elif fake_node_is_installed "v$requested"; then
                printf 'v%s' "$requested"
            else
                printf 'N/A'
            fi
            ;;
        v[0-9]*)
            if fake_node_is_installed "$requested"; then
                printf '%s' "$requested"
            else
                printf 'N/A'
            fi
            ;;
        *)
            printf 'N/A'
            ;;
    esac
}

fake_node_reset() {
    FAKE_NODE_CURRENT="v24.1.0"
    FAKE_NODE_LATEST="v24.2.0"
    FAKE_NODE_DEFAULT_TARGET="v24.1.0"
    FAKE_NODE_REPORTED_OVERRIDE=""
    FAKE_NVM_FAIL=""
    FAKE_NODE_INSTALLED=("v22.9.0" "v24.0.0" "v24.1.0")
    NVM_DIR="$TMP_DIR/fake-nvm"
    mkdir -p "$NVM_DIR/alias"
    printf '%s\n' "$FAKE_NODE_DEFAULT_TARGET" >"$NVM_DIR/alias/default"
    : >"$FAKE_NVM_LOG"
}

fake_node_assert_installed() {
    fake_node_is_installed "$1" || {
        printf 'expected Node %s to remain installed\n' "$1" >&2
        return 1
    }
}

fake_node_assert_absent() {
    if fake_node_is_installed "$1"; then
        printf 'expected Node %s to be uninstalled\n' "$1" >&2
        return 1
    fi
}

welcome_load_nvm() {
    return 0
}

node() {
    case "${1:-}" in
        --version)
            printf '%s\n' "${FAKE_NODE_REPORTED_OVERRIDE:-$FAKE_NODE_CURRENT}"
            ;;
        *)
            printf 'unexpected fake node arguments: %s\n' "$*" >&2
            return 97
            ;;
    esac
}

nvm() {
    local command="${1:-}" requested installed
    local remaining=()

    shift || true
    printf '%s%s\n' "$command" "${*:+ $*}" >>"$FAKE_NVM_LOG"

    case "$command" in
        version-remote)
            [ "${1:-}" = "24" ] || return 96
            printf '%s\n' "$FAKE_NODE_LATEST"
            ;;
        install)
            requested="${1:-}"
            [ "$requested" = "$FAKE_NODE_LATEST" ] || return 95
            [ "$FAKE_NVM_FAIL" != "install" ] || return 41
            if ! fake_node_is_installed "$requested"; then
                FAKE_NODE_INSTALLED+=("$requested")
            fi
            FAKE_NODE_CURRENT="$requested"
            ;;
        use)
            requested="${1:-}"
            [ "$FAKE_NVM_FAIL" != "use" ] || return 42
            fake_node_is_installed "$requested" || return 3
            FAKE_NODE_CURRENT="$requested"
            ;;
        current)
            printf '%s\n' "$FAKE_NODE_CURRENT"
            ;;
        version)
            fake_node_resolve_version "${1:-}"
            printf '\n'
            ;;
        alias)
            [ "${1:-}" = "default" ] || return 94
            if [ "$#" -eq 1 ]; then
                printf 'default -> %s (-> %s)\n' \
                    "$FAKE_NODE_DEFAULT_TARGET" \
                    "$(fake_node_resolve_version default)"
            else
                FAKE_NODE_DEFAULT_TARGET="$2"
                printf '%s\n' "$FAKE_NODE_DEFAULT_TARGET" >"$NVM_DIR/alias/default"
                printf 'default -> %s\n' "$FAKE_NODE_DEFAULT_TARGET"
            fi
            ;;
        ls)
            [ "$FAKE_NVM_FAIL" != "ls" ] || return 45
            for installed in "${FAKE_NODE_INSTALLED[@]}"; do
                case "$installed" in
                    v24.*)
                        if [ "$installed" = "$FAKE_NODE_CURRENT" ]; then
                            printf '%s\n' "->     $installed"
                        else
                            printf '%s\n' "       $installed"
                        fi
                        ;;
                esac
            done
            ;;
        uninstall)
            requested="${1:-}"
            [ "$requested" != "$FAKE_NODE_CURRENT" ] || return 43
            [ "$FAKE_NVM_FAIL" != "uninstall" ] || return 44
            for installed in "${FAKE_NODE_INSTALLED[@]}"; do
                [ "$installed" = "$requested" ] || remaining+=("$installed")
            done
            FAKE_NODE_INSTALLED=("${remaining[@]}")
            ;;
        *)
            printf 'unexpected fake nvm arguments: %s %s\n' "$command" "$*" >&2
            return 93
            ;;
    esac
}

load_rows() {
    COMMANDS=("node")
    PATHS=("$NVM_DIR/versions/node/$FAKE_NODE_CURRENT/bin/node")
    CURRENTS=("${FAKE_NODE_CURRENT#v}")
    LATESTS=("${FAKE_NODE_LATEST#v}")
    INSTALLERS=("")
    STATUSES=("update")
}

node_action_file="$TMP_DIR/node-action.env"
node_result_file="$TMP_DIR/node-result.txt"
printf '%s\n' \
    'ACTION=install_tool' \
    'COMMAND=node' \
    'INCLUDE_UPDATES=1' \
    'VIEW=tools' >"$node_action_file"

# Exercise the real action-file dispatch. The selected version must remain active
# in this shell after output capture, while only stale versions of its major go.
fake_node_reset
FAKE_NODE_INSTALLED+=("v24.3.0")
welcome_execute_action_file "$node_action_file" "$node_result_file"
[ "$FAKE_NODE_CURRENT" = "$FAKE_NODE_LATEST" ]
[ "$FAKE_NODE_DEFAULT_TARGET" = "24" ]
fake_node_assert_absent v24.0.0
fake_node_assert_absent v24.1.0
fake_node_assert_installed v24.2.0
fake_node_assert_installed v22.9.0
fake_node_assert_installed v24.3.0
grep -Fq 'install v24.2.0' "$FAKE_NVM_LOG"
grep -Fq 'use v24.2.0' "$FAKE_NVM_LOG"
grep -Fq 'uninstall v24.0.0' "$FAKE_NVM_LOG"
grep -Fq 'uninstall v24.1.0' "$FAKE_NVM_LOG"
if grep -Fq 'uninstall v22.9.0' "$FAKE_NVM_LOG"; then
    printf 'Node cleanup crossed the current major boundary\n' >&2
    exit 1
fi
grep -Fq 'Action completed.' "$node_result_file"

# A failed use must stop before destructive cleanup and leave every old version.
fake_node_reset
FAKE_NVM_FAIL="use"
welcome_execute_action_file "$node_action_file" "$node_result_file"
fake_node_assert_installed v24.0.0
fake_node_assert_installed v24.1.0
fake_node_assert_installed v22.9.0
if grep -Fq 'uninstall ' "$FAKE_NVM_LOG"; then
    printf 'Node cleanup ran after the update action failed\n' >&2
    exit 1
fi
grep -Fq 'Action failed with exit 42.' "$node_result_file"

# A stale or partial mirror must never cause a same-major downgrade.
fake_node_reset
FAKE_NODE_CURRENT="v24.2.0"
FAKE_NODE_LATEST="v24.1.0"
FAKE_NODE_INSTALLED=("v22.9.0" "v24.1.0" "v24.2.0")
welcome_execute_action_file "$node_action_file" "$node_result_file"
fake_node_assert_installed v24.1.0
fake_node_assert_installed v24.2.0
fake_node_assert_installed v22.9.0
if grep -Eq '^(install|uninstall) ' "$FAKE_NVM_LOG"; then
    printf 'Node mutation ran for a same-major downgrade\n' >&2
    exit 1
fi
grep -Fq 'Refusing to downgrade Node from 24.2.0 to 24.1.0.' "$node_result_file"
grep -Fq 'Action failed with exit 2.' "$node_result_file"

# If installed versions cannot be enumerated, report failure and keep them.
fake_node_reset
FAKE_NVM_FAIL="ls"
welcome_execute_action_file "$node_action_file" "$node_result_file"
fake_node_assert_installed v24.0.0
fake_node_assert_installed v24.1.0
fake_node_assert_installed v22.9.0
if grep -Fq 'uninstall ' "$FAKE_NVM_LOG"; then
    printf 'Node cleanup ran after installed-version enumeration failed\n' >&2
    exit 1
fi
grep -Fq 'Could not list installed Node 24.x versions' "$node_result_file"
grep -Fq 'Action failed with exit 1.' "$node_result_file"
