#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

setup_case() {
    local name="$1" installed="${2:-yes}" default_alias="${3:-none}"

    CASE_DIR="$TEST_ROOT/$name"
    CASE_HOME="$CASE_DIR/home"
    CASE_NVM_DIR="$CASE_DIR/nvm"
    CASE_BIN="$CASE_DIR/bin"
    CASE_LOG="$CASE_DIR/nvm.log"
    CASE_STATE="$CASE_DIR/node-installed"
    CASE_NVM_SYMLINK_CURRENT=false
    mkdir -p "$CASE_HOME" "$CASE_NVM_DIR/alias" "$CASE_BIN"
    : >"$CASE_LOG"

    if [ "$installed" = "yes" ]; then
        : >"$CASE_STATE"
    fi
    if [ "$default_alias" != "none" ]; then
        printf '%s\n' "$default_alias" >"$CASE_NVM_DIR/alias/default"
    fi

    cat >"$CASE_BIN/node" <<'SCRIPT'
#!/bin/sh
case "${1:-}" in
    -p)
        printf '24\n'
        ;;
    --version)
        printf 'v24.1.0\n'
        ;;
    *)
        exit 2
        ;;
esac
SCRIPT
    cat >"$CASE_BIN/npm" <<'SCRIPT'
#!/bin/sh
printf 'npm:%s\n' "$*" >>"$FAKE_NVM_LOG"
SCRIPT
    chmod +x "$CASE_BIN/node" "$CASE_BIN/npm"

    cat >"$CASE_NVM_DIR/nvm.sh" <<'SCRIPT'
nvm() {
    printf 'nvm:%s\n' "$*" >>"$FAKE_NVM_LOG"
    case "${1:-}" in
        version)
            if [ -f "$FAKE_NVM_STATE" ]; then
                printf 'v24.1.0\n'
            else
                printf 'N/A\n'
            fi
            ;;
        install)
            : >"$FAKE_NVM_STATE"
            mkdir -p "$NVM_DIR/alias"
            if [ ! -e "$NVM_DIR/alias/default" ] && [ ! -L "$NVM_DIR/alias/default" ]; then
                printf '%s\n' "${2:-}" >"$NVM_DIR/alias/default"
            fi
            ;;
        use)
            [ -f "$FAKE_NVM_STATE" ] || return 3
            if [ "${NVM_SYMLINK_CURRENT:-false}" = "true" ]; then
                rm -f -- "$NVM_DIR/current"
                ln -s "$FAKE_NVM_STATE" "$NVM_DIR/current"
            fi
            PATH="$FAKE_NVM_BIN:$PATH"
            export PATH
            ;;
        *)
            return 91
            ;;
    esac
}
SCRIPT
}

run_bootstrap() {
    HOME="$CASE_HOME" \
        NVM_DIR="$CASE_NVM_DIR" \
        FAKE_NVM_BIN="$CASE_BIN" \
        FAKE_NVM_LOG="$CASE_LOG" \
        FAKE_NVM_STATE="$CASE_STATE" \
        NVM_SYMLINK_CURRENT="$CASE_NVM_SYMLINK_CURRENT" \
        "$ROOT_DIR/bootstrap.sh" "$@"
}

assert_no_home_nvmrc() {
    [ ! -e "$CASE_HOME/.nvmrc" ] && [ ! -L "$CASE_HOME/.nvmrc" ]
}

setup_case fresh
CASE_NVM_SYMLINK_CURRENT=true
output=$(run_bootstrap --dry-run)
if grep -Fq '~/.nvmrc' <<<"$output"; then
    printf 'fresh bootstrap still plans a home .nvmrc\n' >&2
    exit 1
fi
assert_no_home_nvmrc
[ ! -e "$CASE_NVM_DIR/current" ] && [ ! -L "$CASE_NVM_DIR/current" ]

setup_case absolute_link
ln -s "$ROOT_DIR/.nvmrc" "$CASE_HOME/.nvmrc"
run_bootstrap --yes >/dev/null
[ -L "$CASE_HOME/.nvmrc" ]
[ "$(readlink "$CASE_HOME/.nvmrc")" = "$ROOT_DIR/.nvmrc" ]

setup_case relative_link
ln -s "$ROOT_DIR/.nvmrc" "$CASE_DIR/repo-nvmrc"
ln -s ../repo-nvmrc "$CASE_HOME/.nvmrc"
run_bootstrap --yes >/dev/null
[ -L "$CASE_HOME/.nvmrc" ]
[ "$(readlink "$CASE_HOME/.nvmrc")" = ../repo-nvmrc ]

setup_case user_file
printf '22\n' >"$CASE_HOME/.nvmrc"
run_bootstrap --yes >/dev/null
[ "$(<"$CASE_HOME/.nvmrc")" = "22" ]

setup_case other_link
printf '20\n' >"$CASE_DIR/other.nvmrc"
ln -s "$CASE_DIR/other.nvmrc" "$CASE_HOME/.nvmrc"
run_bootstrap --yes >/dev/null
[ -L "$CASE_HOME/.nvmrc" ]
[ "$(readlink "$CASE_HOME/.nvmrc")" = "$CASE_DIR/other.nvmrc" ]

setup_case no_default no
run_bootstrap --yes >/dev/null
assert_no_home_nvmrc
[ -f "$CASE_STATE" ]
[ ! -e "$CASE_NVM_DIR/alias/default" ] && [ ! -L "$CASE_NVM_DIR/alias/default" ]
grep -Fq 'nvm:install 24' "$CASE_LOG"
grep -Fq 'nvm:use 24' "$CASE_LOG"
if grep -Fq 'nvm:alias' "$CASE_LOG"; then
    printf 'bootstrap explicitly changed the nvm default alias\n' >&2
    exit 1
fi

setup_case existing_default no 22
run_bootstrap --yes >/dev/null
[ "$(<"$CASE_NVM_DIR/alias/default")" = "22" ]
