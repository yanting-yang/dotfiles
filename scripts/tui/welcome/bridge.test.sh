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

# Remote version helpers should prefer their single-request paths, cache valid
# results, and retain their slower fallbacks for unusual remote responses.
mkdir -p "$TMP_DIR/latest-bin"
cat >"$TMP_DIR/latest-bin/curl" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >>"$STATUS_LATEST_CURL_LOG"

case "${STATUS_LATEST_CURL_MODE:-}" in
    github-direct)
        printf 'https://github.com/example/project/releases/tag/v1.2.3'
        ;;
    github-fallback)
        case "$*" in
            -fsSIL*) printf 'https://github.com/example/project/releases/tag/v2.3.4' ;;
            -fsSI*) printf 'https://github.com/example/project/releases/latest' ;;
            *) exit 91 ;;
        esac
        ;;
    stow-api)
        printf '%s\n' \
            '[' \
            '  {"ref":"refs/tags/v2.3.1"},' \
            '  {"ref": "refs/tags/v2.4.1"},' \
            '  {"ref":"refs/tags/v2.5.0-beta.1"}' \
            ']'
        ;;
    stow-fallback)
        exit 22
        ;;
    texlive-range)
        printf '%s\n' \
            'name 00texlive.config' \
            'category TLCore' \
            'depend release/2026' \
            '' \
            'name 00texlive.image'
        ;;
    *)
        exit 92
        ;;
esac
SCRIPT
cat >"$TMP_DIR/latest-bin/git" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >>"$STATUS_LATEST_GIT_LOG"

case "${STATUS_LATEST_GIT_MODE:-}" in
    stow-fallback)
        printf '%s\n' \
            '1111111111111111111111111111111111111111 refs/tags/v2.3.1' \
            '2222222222222222222222222222222222222222 refs/tags/v2.4.0' \
            '3333333333333333333333333333333333333333 refs/tags/v2.5.0-beta.1'
        ;;
    *)
        exit 93
        ;;
esac
SCRIPT
chmod +x "$TMP_DIR/latest-bin/curl" "$TMP_DIR/latest-bin/git"

(
    PATH="$TMP_DIR/latest-bin:$ORIGINAL_PATH"
    STATUS_LATEST_CURL_LOG="$TMP_DIR/latest-curl.log"
    STATUS_LATEST_GIT_LOG="$TMP_DIR/latest-git.log"
    export PATH STATUS_LATEST_CURL_LOG STATUS_LATEST_GIT_LOG

    github_cache="$TMP_DIR/github-direct-cache"
    mkdir -p "$github_cache"
    : >"$STATUS_LATEST_CURL_LOG"
    : >"$STATUS_LATEST_GIT_LOG"
    STATUS_LATEST_CURL_MODE=github-direct
    export STATUS_LATEST_CURL_MODE
    github_latest=$(WELCOME_UPDATE_CACHE_DIR="$github_cache" \
        get_github_latest https://github.com/example/project github-direct)
    [ "$github_latest" = "1.2.3" ]
    [ "$(sed -n '1p' "$STATUS_LATEST_CURL_LOG")" = \
        '-fsSI -o /dev/null -w %{redirect_url} https://github.com/example/project/releases/latest' ]
    [ "$(wc -l <"$STATUS_LATEST_CURL_LOG")" -eq 1 ]
    IFS= read -r github_cached <"$github_cache/github-direct.latest"
    [ "$github_cached" = "1.2.3" ]

    github_latest=$(WELCOME_UPDATE_CACHE_DIR="$github_cache" \
        get_github_latest https://github.com/example/project github-direct)
    [ "$github_latest" = "1.2.3" ]
    [ "$(wc -l <"$STATUS_LATEST_CURL_LOG")" -eq 1 ]

    : >"$STATUS_LATEST_CURL_LOG"
    STATUS_LATEST_CURL_MODE=github-fallback
    export STATUS_LATEST_CURL_MODE
    github_latest=$(WELCOME_UPDATE_CACHE_DIR= \
        get_github_latest https://github.com/example/project github-fallback)
    [ "$github_latest" = "2.3.4" ]
    mapfile -t github_fallback_calls <"$STATUS_LATEST_CURL_LOG"
    [ "${#github_fallback_calls[@]}" -eq 2 ]
    [ "${github_fallback_calls[0]}" = \
        '-fsSI -o /dev/null -w %{redirect_url} https://github.com/example/project/releases/latest' ]
    [ "${github_fallback_calls[1]}" = \
        '-fsSIL -o /dev/null -w %{url_effective} https://github.com/example/project/releases/latest' ]

    : >"$STATUS_LATEST_CURL_LOG"
    : >"$STATUS_LATEST_GIT_LOG"
    STATUS_LATEST_CURL_MODE=stow-api
    STATUS_LATEST_GIT_MODE=stow-api
    export STATUS_LATEST_CURL_MODE STATUS_LATEST_GIT_MODE
    stow_latest=$(WELCOME_UPDATE_CACHE_DIR= get_stow_latest)
    [ "$stow_latest" = "2.4.1" ]
    [ "$(sed -n '1p' "$STATUS_LATEST_CURL_LOG")" = \
        '-fsSL -H Accept: application/vnd.github+json https://api.github.com/repos/aspiers/stow/git/matching-refs/tags/v' ]
    [ "$(wc -l <"$STATUS_LATEST_CURL_LOG")" -eq 1 ]
    [ ! -s "$STATUS_LATEST_GIT_LOG" ]

    : >"$STATUS_LATEST_CURL_LOG"
    : >"$STATUS_LATEST_GIT_LOG"
    STATUS_LATEST_CURL_MODE=stow-fallback
    STATUS_LATEST_GIT_MODE=stow-fallback
    export STATUS_LATEST_CURL_MODE STATUS_LATEST_GIT_MODE
    stow_latest=$(WELCOME_UPDATE_CACHE_DIR= get_stow_latest)
    [ "$stow_latest" = "2.4.0" ]
    [ "$(wc -l <"$STATUS_LATEST_CURL_LOG")" -eq 1 ]
    [ "$(sed -n '1p' "$STATUS_LATEST_GIT_LOG")" = \
        'ls-remote --tags --refs https://github.com/aspiers/stow.git v*' ]
    [ "$(wc -l <"$STATUS_LATEST_GIT_LOG")" -eq 1 ]

    texlive_cache="$TMP_DIR/texlive-cache"
    mkdir -p "$texlive_cache"
    : >"$STATUS_LATEST_CURL_LOG"
    STATUS_LATEST_CURL_MODE=texlive-range
    export STATUS_LATEST_CURL_MODE
    texlive_latest=$(WELCOME_UPDATE_CACHE_DIR="$texlive_cache" get_texlive_latest)
    [ "$texlive_latest" = "2026" ]
    [ "$(sed -n '1p' "$STATUS_LATEST_CURL_LOG")" = \
        '-fsSL --range 0-16383 --max-filesize 32768 --max-time 20 https://mirror.ctan.org/systems/texlive/tlnet/tlpkg/texlive.tlpdb' ]
    [ "$(wc -l <"$STATUS_LATEST_CURL_LOG")" -eq 1 ]
    IFS= read -r texlive_cached <"$texlive_cache/texlive.latest"
    [ "$texlive_cached" = "2026" ]

    texlive_latest=$(WELCOME_UPDATE_CACHE_DIR="$texlive_cache" get_texlive_latest)
    [ "$texlive_latest" = "2026" ]
    [ "$(wc -l <"$STATUS_LATEST_CURL_LOG")" -eq 1 ]
)

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

# Row callbacks must observe each completed row as it is appended, in table
# order. Use two installed-tool stubs so the first events also prove that a
# retrieved remote version and its derived status are available immediately.
PATH="$ORIGINAL_PATH"
cat >"$HOME/code" <<'SCRIPT'
#!/bin/sh
printf 'code 1.0.0\n'
SCRIPT
cat >"$TMP_DIR/bin/gh" <<'SCRIPT'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    printf 'gh version 2.0.0\n'
fi
SCRIPT
chmod +x "$HOME/code" "$TMP_DIR/bin/gh"
ln -s "$(command -v awk)" "$TMP_DIR/bin/awk"
ln -s "$(command -v head)" "$TMP_DIR/bin/head"
PATH="$TMP_DIR/bin"

STATUS_ROW_CALLBACK_LOG="$TMP_DIR/status-row-callback.log"
STATUS_REMOTE_CHECK_LOG="$TMP_DIR/status-remote-check.log"

get_github_latest() {
    local cache_key="$2"

    printf '%s\n' "$cache_key" >>"$STATUS_REMOTE_CHECK_LOG"
    case "$cache_key" in
        code) printf '1.1.0' ;;
        gh) printf '2.1.0' ;;
        *) printf '9.9.9' ;;
    esac
}

status_record_completed_row() {
    local index="$1" row_count="${#COMMANDS[@]}"

    [ "$index" -eq $((row_count - 1)) ]
    [ "${#PATHS[@]}" -eq "$row_count" ]
    [ "${#CURRENTS[@]}" -eq "$row_count" ]
    [ "${#LATESTS[@]}" -eq "$row_count" ]
    [ "${#INSTALLERS[@]}" -eq "$row_count" ]
    [ "${#STATUSES[@]}" -eq "$row_count" ]
    printf '%s|%s|%s|%s\n' \
        "$row_count" "${COMMANDS[$index]}" "${LATESTS[$index]}" "${STATUSES[$index]}" \
        >>"$STATUS_ROW_CALLBACK_LOG"
}

: >"$STATUS_ROW_CALLBACK_LOG"
: >"$STATUS_REMOTE_CHECK_LOG"
load_rows 1 status_record_completed_row

mapfile -t status_callback_rows <"$STATUS_ROW_CALLBACK_LOG"
expected_callback_commands=(code gh nvim nvm node stow tmux cat-tmux kitty latex maple)
[ "${#status_callback_rows[@]}" -eq "${#expected_callback_commands[@]}" ]
for i in "${!expected_callback_commands[@]}"; do
    IFS='|' read -r callback_count callback_command callback_latest callback_status \
        <<<"${status_callback_rows[$i]}"
    [ "$callback_count" -eq $((i + 1)) ]
    [ "$callback_command" = "${expected_callback_commands[$i]}" ]
done
[ "${status_callback_rows[0]}" = '1|code|1.1.0|update' ]
[ "${status_callback_rows[1]}" = '2|gh|2.1.0|update' ]
mapfile -t status_remote_checks <"$STATUS_REMOTE_CHECK_LOG"
[ "${status_remote_checks[*]}" = 'code gh' ]

# Omitting the callback retains the one-shot local behavior, does not leak the
# previous callback, and does not perform remote checks.
: >"$STATUS_ROW_CALLBACK_LOG"
: >"$STATUS_REMOTE_CHECK_LOG"
load_rows 0
[ ! -s "$STATUS_ROW_CALLBACK_LOG" ]
[ ! -s "$STATUS_REMOTE_CHECK_LOG" ]
[ "${COMMANDS[0]}|${LATESTS[0]}|${STATUSES[0]}" = 'code|unchecked|installed' ]
[ "${COMMANDS[1]}|${LATESTS[1]}|${STATUSES[1]}" = 'gh|unchecked|installed' ]
[ "${COMMANDS[9]}|${LATESTS[9]}|${STATUSES[9]}" = 'latex|unchecked|missing' ]
row_is_actionable 9
if row_is_uninstallable 9; then
    printf 'missing LaTeX unexpectedly exposed an uninstall action\n' >&2
    exit 1
fi

# The real status exporter must forward those callbacks as newline-delimited
# events instead of buffering until every row is ready. Keep the subprocess
# offline with a curl stub and a PATH containing only the intended fixtures.
PATH="$ORIGINAL_PATH"
ln -s "$(PATH="$ORIGINAL_PATH" command -v dirname)" "$TMP_DIR/bin/dirname"
ln -s "$(PATH="$ORIGINAL_PATH" command -v readlink)" "$TMP_DIR/bin/readlink"
STATUS_STREAM_CURL_LOG="$TMP_DIR/status-stream-curl.log"
: >"$STATUS_STREAM_CURL_LOG"
cat >"$TMP_DIR/bin/curl" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >>"$STATUS_STREAM_CURL_LOG"
case "$*" in
    '-fsSI -o /dev/null -w %{redirect_url} https://github.com/microsoft/vscode/releases/latest')
        printf 'https://github.com/microsoft/vscode/releases/tag/v1.1.0'
        ;;
    '-fsSI -o /dev/null -w %{redirect_url} https://github.com/cli/cli/releases/latest')
        printf 'https://github.com/cli/cli/releases/tag/v2.1.0'
        ;;
    *) exit 91 ;;
esac
SCRIPT
chmod +x "$TMP_DIR/bin/curl"

mapfile -t status_stream_events < <(
    HOME="$HOME" \
        NVM_DIR="$NVM_DIR" \
        PATH="$TMP_DIR/bin" \
        STATUS_STREAM_CURL_LOG="$STATUS_STREAM_CURL_LOG" \
        WELCOME_UPDATE_CACHE_DIR= \
        /bin/bash "$ROOT_DIR/scripts/tui/welcome/status.sh" tools --updates --stream
)
[ "${#status_stream_events[@]}" -eq 12 ]
for i in {0..10}; do
    [[ "${status_stream_events[$i]}" == '{"kind":"tool-row","row":'* ]]
done
[[ "${status_stream_events[0]}" == *'"command":"code"'* ]]
[[ "${status_stream_events[0]}" == *'"latest":"1.1.0"'* ]]
[[ "${status_stream_events[0]}" == *'"status":"update"'* ]]
[[ "${status_stream_events[1]}" == *'"command":"gh"'* ]]
[[ "${status_stream_events[1]}" == *'"latest":"2.1.0"'* ]]
[ "${status_stream_events[11]}" = '{"kind":"tools-complete","includeUpdates":true}' ]
mapfile -t status_stream_curl_calls <"$STATUS_STREAM_CURL_LOG"
[ "${#status_stream_curl_calls[@]}" -eq 2 ]
[ "${status_stream_curl_calls[0]}" = \
    '-fsSI -o /dev/null -w %{redirect_url} https://github.com/microsoft/vscode/releases/latest' ]
[ "${status_stream_curl_calls[1]}" = \
    '-fsSI -o /dev/null -w %{redirect_url} https://github.com/cli/cli/releases/latest' ]

status_local_json=$(
    HOME="$HOME" \
        NVM_DIR="$NVM_DIR" \
        PATH="$TMP_DIR/bin" \
        STATUS_STREAM_CURL_LOG="$STATUS_STREAM_CURL_LOG" \
        WELCOME_UPDATE_CACHE_DIR= \
        /bin/bash "$ROOT_DIR/scripts/tui/welcome/status.sh" tools --local
)
[[ "$status_local_json" == '{"kind":"tools","includeUpdates":false,"rows":['* ]]
[[ "$status_local_json" != *$'\n'* ]]

# LaTeX reports the annual TeX Live release, checks CTAN only when explicitly
# requested, and never offers a downgrade when the local release is newer.
mkdir -p "$TMP_DIR/latex-bin"
cat >"$TMP_DIR/latex-bin/latex" <<'SCRIPT'
#!/bin/sh
printf 'pdfTeX 3.141592653 (TeX Live %s)\n' "$FAKE_TEXLIVE_YEAR"
SCRIPT
cat >"$TMP_DIR/latex-bin/tlmgr" <<'SCRIPT'
#!/bin/sh
printf 'tlmgr revision 12345\n'
printf 'TeX Live (https://tug.org/texlive) version %s\n' "$FAKE_TEXLIVE_YEAR"
SCRIPT
chmod +x "$TMP_DIR/latex-bin/latex" "$TMP_DIR/latex-bin/tlmgr"
ln -s "$(PATH="$ORIGINAL_PATH" command -v sed)" "$TMP_DIR/bin/sed"

TEXLIVE_REMOTE_LOG="$TMP_DIR/texlive-remote.log"
: >"$TEXLIVE_REMOTE_LOG"
TEXLIVE_REMOTE_YEAR=2026
get_texlive_latest() {
    printf 'check\n' >>"$TEXLIVE_REMOTE_LOG"
    printf '%s' "$TEXLIVE_REMOTE_YEAR"
}

status_assert_latex_row() {
    local expected_current="$1" expected_latest="$2" expected_status="$3" i

    STATUS_LATEX_INDEX=-1
    for i in "${!COMMANDS[@]}"; do
        if [ "${COMMANDS[$i]}" = "latex" ]; then
            STATUS_LATEX_INDEX="$i"
            break
        fi
    done

    [ "$STATUS_LATEX_INDEX" -ge 0 ]
    [ "${PATHS[$STATUS_LATEX_INDEX]}" != "not installed" ]
    [ "${CURRENTS[$STATUS_LATEX_INDEX]}" = "$expected_current" ]
    [ "${LATESTS[$STATUS_LATEX_INDEX]}" = "$expected_latest" ]
    [ "${STATUSES[$STATUS_LATEX_INDEX]}" = "$expected_status" ]
    if row_is_uninstallable "$STATUS_LATEX_INDEX"; then
        printf 'LaTeX unexpectedly exposed an uninstall action\n' >&2
        return 1
    fi
}

PATH="$TMP_DIR/latex-bin:$TMP_DIR/bin"
FAKE_TEXLIVE_YEAR=2025
export FAKE_TEXLIVE_YEAR
load_rows 0
status_assert_latex_row 2025 unchecked installed
[ ! -s "$TEXLIVE_REMOTE_LOG" ]

load_rows 1
status_assert_latex_row 2025 2026 update
[ "$(PATH="$ORIGINAL_PATH" wc -l <"$TEXLIVE_REMOTE_LOG")" -eq 1 ]
row_is_actionable "$STATUS_LATEX_INDEX"

FAKE_TEXLIVE_YEAR=2026
load_rows 1
status_assert_latex_row 2026 2026 current
[ "$(PATH="$ORIGINAL_PATH" wc -l <"$TEXLIVE_REMOTE_LOG")" -eq 2 ]
if row_is_actionable "$STATUS_LATEX_INDEX"; then
    printf 'current LaTeX unexpectedly exposed an update action\n' >&2
    exit 1
fi

FAKE_TEXLIVE_YEAR=2027
load_rows 1
status_assert_latex_row 2027 2026 current
[ "$(PATH="$ORIGINAL_PATH" wc -l <"$TEXLIVE_REMOTE_LOG")" -eq 3 ]
if row_is_actionable "$STATUS_LATEX_INDEX"; then
    printf 'LaTeX offered a downgrade to an older TeX Live release\n' >&2
    exit 1
fi

PATH="$TMP_DIR/bin"

# Exercise Node's real status-row path before the action tests replace
# load_rows with focused fixtures.
PATH="$ORIGINAL_PATH"
mkdir -p "$NVM_DIR" "$TMP_DIR/status-cache" "$TMP_DIR/status-fast-cache"
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

nvm_get_mirror() {
    if [ -n "${STATUS_NVM_LOG:-}" ]; then
        printf 'get-mirror:%s\n' "$*" >>"$STATUS_NVM_LOG"
    fi

    [ "${STATUS_NVM_FAST_PATH:-0}" -eq 1 ] || return 96
    [ "$*" = "node std" ] || return 97
    printf 'https://nodejs.org/dist/'
}

nvm_download() {
    if [ -n "${STATUS_NVM_LOG:-}" ]; then
        printf 'download:%s\n' "$*" >>"$STATUS_NVM_LOG"
    fi

    [ "${STATUS_NVM_FAST_PATH:-0}" -eq 1 ] || return 98
    [ "$*" = \
        "-L -s --header Range: bytes=0-255 https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt -o -" ] \
        || return 99
    printf '%s\n' \
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  node-v24.3.0-linux-x64.tar.xz'
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

STATUS_NVM_FAST_PATH=1
WELCOME_UPDATE_CACHE_DIR="$TMP_DIR/status-fast-cache" load_rows 1
status_assert_node_row 24.3.0 update
status_assert_node_remote_calls 0
PATH="$ORIGINAL_PATH" grep -Fxq 'get-mirror:node std' "$STATUS_NVM_LOG"
PATH="$ORIGINAL_PATH" grep -Fxq \
    'download:-L -s --header Range: bytes=0-255 https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt -o -' \
    "$STATUS_NVM_LOG"
[ "$(PATH="$ORIGINAL_PATH" grep -c '^download:' "$STATUS_NVM_LOG")" -eq 1 ]
IFS= read -r cached_fast_node_latest <"$TMP_DIR/status-fast-cache/node-24.latest"
[ "$cached_fast_node_latest" = "24.3.0" ]

STATUS_NVM_FAST_PATH=0
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

# The catppuccin/tmux plugin row is detected from the linked config tree and is
# installable but never offers a managed uninstall action.
catppuccin_plugin_dir="$HOME/.config/tmux/plugins/catppuccin/tmux"
mkdir -p "$catppuccin_plugin_dir"
: >"$catppuccin_plugin_dir/catppuccin.tmux"

WELCOME_UPDATE_CACHE_DIR="$TMP_DIR/status-cache" load_rows 0
CATPPUCCIN_INDEX=-1
for i in "${!COMMANDS[@]}"; do
    if [ "${COMMANDS[$i]}" = "cat-tmux" ]; then
        CATPPUCCIN_INDEX="$i"
        break
    fi
done
[ "$CATPPUCCIN_INDEX" -ge 0 ]
[ "${PATHS[$CATPPUCCIN_INDEX]}" = "$catppuccin_plugin_dir" ]
[ "${STATUSES[$CATPPUCCIN_INDEX]}" = "installed" ]
if row_is_uninstallable "$CATPPUCCIN_INDEX"; then
    printf 'catppuccin/tmux must not expose a managed uninstall action\n' >&2
    exit 1
fi

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

# A successful LaTeX action activates the installer's stable TeX Live path in
# this parent shell, so the next Welcome render can observe it immediately.
fake_latex_installer="$TMP_DIR/fake-latex-installer.sh"
cat >"$fake_latex_installer" <<'SCRIPT'
#!/usr/bin/env bash
set -e
if [ "${FAKE_LATEX_FAIL:-0}" -eq 1 ]; then
    printf 'specific LaTeX installer failure\n' >&2
    exit 37
fi
mkdir -p "$TEXLIVE_ROOT/current/bin/x86_64-linux"
: >"$TEXLIVE_ROOT/current/bin/x86_64-linux/latex"
chmod +x "$TEXLIVE_ROOT/current/bin/x86_64-linux/latex"
SCRIPT
chmod +x "$fake_latex_installer"

load_rows() {
    COMMANDS=("latex")
    PATHS=("not installed")
    CURRENTS=("unknown")
    LATESTS=("2026")
    INSTALLERS=("$fake_latex_installer")
    STATUSES=("missing")
}

TEXLIVE_ROOT="$TMP_DIR/fake-texlive"
export TEXLIVE_ROOT
PATH="$ORIGINAL_PATH"
welcome_run_tool_installer latex 0 >/dev/null
[ "${PATH%%:*}" = "$TEXLIVE_ROOT/current/bin/x86_64-linux" ]

latex_action_file="$TMP_DIR/latex-action.env"
latex_result_file="$TMP_DIR/latex-result.txt"
latex_live_output="$TMP_DIR/latex-live-output.txt"
printf '%s\n' \
    'ACTION=install_tool' \
    'COMMAND=latex' \
    'INCLUDE_UPDATES=0' \
    'VIEW=tools' >"$latex_action_file"

FAKE_LATEX_FAIL=1
export FAKE_LATEX_FAIL
welcome_execute_action_file "$latex_action_file" "$latex_result_file" \
    >"$latex_live_output"
grep -Fq 'specific LaTeX installer failure' "$latex_live_output"
grep -Fq 'specific LaTeX installer failure' "$latex_result_file"
grep -Fq 'Action failed with exit 37.' "$latex_result_file"
if grep -Fq 'Installer output was shown in the terminal.' "$latex_result_file"; then
    printf 'failed LaTeX action discarded its diagnostic output\n' >&2
    exit 1
fi

FAKE_LATEX_FAIL=0
export FAKE_LATEX_FAIL
TEXLIVE_ROOT="$TMP_DIR/fake-texlive-action"
PATH="$ORIGINAL_PATH"
welcome_execute_action_file "$latex_action_file" "$latex_result_file" \
    >"$latex_live_output"
[ "${PATH%%:*}" = "$TEXLIVE_ROOT/current/bin/x86_64-linux" ]
grep -Fq 'Action completed.' "$latex_result_file"
unset TEXLIVE_ROOT
unset FAKE_LATEX_FAIL
PATH="$ORIGINAL_PATH"

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
