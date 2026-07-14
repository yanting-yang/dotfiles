#!/usr/bin/env bash

TOOL_STATUS_DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL_STATUS_INSTALL_DIR="$TOOL_STATUS_DOTFILES_DIR/scripts/install"
TOOL_STATUS_LOCAL_PREFIX="${LOCAL_PREFIX:-$HOME/.local}"
TOOL_STATUS_LOCAL_BIN_DIR="$TOOL_STATUS_LOCAL_PREFIX/bin"
TOOL_STATUS_LOCAL_STOW_DIR="$TOOL_STATUS_LOCAL_PREFIX/stow"
TOOL_STATUS_LATEST_UNCHECKED="unchecked"

LATEST_UNCHECKED="$TOOL_STATUS_LATEST_UNCHECKED"

COMMANDS=()
PATHS=()
CURRENTS=()
LATESTS=()
INSTALLERS=()
STATUSES=()

get_github_latest() {
    local url="$1" cache_key="${2:-github}" latest

    if tool_status_cache_read "$cache_key"; then
        return 0
    fi
    command -v curl >/dev/null 2>&1 || return 0
    latest=$(curl -Ls -o /dev/null -w '%{url_effective}' "$url/releases/latest" 2>/dev/null) || return 0
    latest="${latest##*/}"
    latest="${latest#v}"

    if [ -n "$latest" ] && [ "$latest" != "latest" ]; then
        tool_status_cache_write "$cache_key" "$latest"
        printf '%s' "$latest"
    fi
}

get_stow_latest() {
    local latest

    if tool_status_cache_read stow; then
        return 0
    fi
    command -v curl >/dev/null 2>&1 || return 0
    latest=$(curl -Ls https://ftp.gnu.org/gnu/stow/ 2>/dev/null \
        | sed -n 's/.*stow-\([0-9][0-9.]*\)\.tar\.gz.*/\1/p' \
        | sort -V \
        | tail -1)

    if [ -n "$latest" ]; then
        tool_status_cache_write stow "$latest"
        printf '%s' "$latest"
    fi
}

tool_status_cache_read() {
    local key="$1" file cached

    [ -n "${WELCOME_UPDATE_CACHE_DIR:-}" ] || return 1
    tool_status_cache_key_is_safe "$key" || return 1

    file="$WELCOME_UPDATE_CACHE_DIR/$key.latest"
    [ -s "$file" ] || return 1
    IFS= read -r cached <"$file" || return 1
    [ -n "$cached" ] || return 1
    printf '%s' "$cached"
}

tool_status_cache_write() {
    local key="$1" value="$2" file

    [ -n "${WELCOME_UPDATE_CACHE_DIR:-}" ] || return 0
    tool_status_cache_key_is_safe "$key" || return 0
    [ -n "$value" ] || return 0

    mkdir -p "$WELCOME_UPDATE_CACHE_DIR" 2>/dev/null || return 0
    file="$WELCOME_UPDATE_CACHE_DIR/$key.latest"
    printf '%s\n' "$value" >"$file" 2>/dev/null || true
}

tool_status_cache_key_is_safe() {
    [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]]
}

get_cmd_path() {
    local cmd="$1"
    local path resolved

    if ! path=$(command -v "$cmd" 2>/dev/null); then
        return 1
    fi

    resolved=$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")
    if [ "$resolved" != "$path" ]; then
        printf '%s -> %s' "$path" "$resolved"
    else
        printf '%s' "$path"
    fi
}

latest_is_newer() {
    local current="$1" latest="$2"

    [ -n "$latest" ] \
        && [ "$latest" != "$LATEST_UNCHECKED" ] \
        && [ "$latest" != "unknown" ] \
        && [ "$current" != "unknown" ] \
        && [ "$latest" != "$current" ]
}

row_status() {
    local path="$1" current="$2" latest="$3"

    if [ "$path" = "not installed" ]; then
        printf 'missing'
    elif [ "$latest" = "$LATEST_UNCHECKED" ]; then
        printf 'installed'
    elif latest_is_newer "$current" "$latest"; then
        printf 'update'
    elif [ "$latest" = "unknown" ] || [ "$current" = "unknown" ]; then
        printf 'check'
    else
        printf 'current'
    fi
}

clear_rows() {
    COMMANDS=()
    PATHS=()
    CURRENTS=()
    LATESTS=()
    INSTALLERS=()
    STATUSES=()
}

add_row() {
    local command="$1" path="$2" current="${3:-unknown}" latest="${4:-unknown}" installer="${5:-}"
    local status

    [ -n "$current" ] || current="unknown"
    [ -n "$latest" ] || latest="unknown"
    status=$(row_status "$path" "$current" "$latest")

    COMMANDS+=("$command")
    PATHS+=("$path")
    CURRENTS+=("$current")
    LATESTS+=("$latest")
    INSTALLERS+=("$installer")
    STATUSES+=("$status")
}

add_missing_row() {
    add_row "$1" "not installed" "unknown" "${2:-unknown}" "${3:-}"
}

add_cmd_row() {
    local label="$1" cmd="$2" current="$3" latest="$4" installer="$5"
    local path

    if path=$(get_cmd_path "$cmd"); then
        add_row "$label" "$path" "$current" "$latest" "$installer"
    else
        add_missing_row "$label" "$latest" "$installer"
    fi
}

tool_status_path_mentions_prefix() {
    local path="$1" prefix="$2"

    case "$path" in
        "$prefix"|"$prefix"/*|*" -> $prefix"|*" -> $prefix"/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

load_rows() {
    local include_updates="${1:-0}"
    local code_latest code_current
    local gh_latest gh_current
    local nvim_latest nvim_current
    local nvm_latest nvm_current nvm_dir
    local stow_latest stow_current
    local tmux_latest tmux_current
    local code_bin="$HOME/code"

    clear_rows

    code_latest="$LATEST_UNCHECKED"
    if [ -x "$code_bin" ]; then
        [ "$include_updates" -eq 1 ] && code_latest=$(get_github_latest https://github.com/microsoft/vscode code)
        code_current=$("$code_bin" --version 2>/dev/null | head -1 | awk '{print $2}')
        add_row "code" "$code_bin" "$code_current" "$code_latest" "$TOOL_STATUS_INSTALL_DIR/code.sh"
    else
        add_missing_row "code" "$code_latest" "$TOOL_STATUS_INSTALL_DIR/code.sh"
    fi

    gh_latest="$LATEST_UNCHECKED"
    if command -v gh >/dev/null 2>&1; then
        [ "$include_updates" -eq 1 ] && gh_latest=$(get_github_latest https://github.com/cli/cli gh)
        gh_current=$(gh --version 2>/dev/null | awk 'NR==1{print $3}')
        add_cmd_row "gh" "gh" "$gh_current" "$gh_latest" "$TOOL_STATUS_INSTALL_DIR/gh.sh"
    else
        add_missing_row "gh" "$gh_latest" "$TOOL_STATUS_INSTALL_DIR/gh.sh"
    fi

    nvim_latest="$LATEST_UNCHECKED"
    if command -v nvim >/dev/null 2>&1; then
        [ "$include_updates" -eq 1 ] && nvim_latest=$(get_github_latest https://github.com/neovim/neovim nvim)
        nvim_current=$(NVIM_LOG_FILE="${NVIM_LOG_FILE:-/tmp/nvim-welcome.log}" nvim --version 2>/dev/null \
            | awk 'NR==1{print $2}' \
            | sed 's/^v//')
        add_cmd_row "nvim" "nvim" "$nvim_current" "$nvim_latest" "$TOOL_STATUS_INSTALL_DIR/nvim.sh"
    else
        add_missing_row "nvim" "$nvim_latest" "$TOOL_STATUS_INSTALL_DIR/nvim.sh"
    fi

    nvm_latest="$LATEST_UNCHECKED"
    nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"
    if [ -s "$nvm_dir/nvm.sh" ]; then
        [ "$include_updates" -eq 1 ] && nvm_latest=$(get_github_latest https://github.com/nvm-sh/nvm nvm)
        # shellcheck source=/dev/null
        source "$nvm_dir/nvm.sh" --no-use
        nvm_current=$(nvm --version 2>/dev/null)
        add_row "nvm" "$nvm_dir/nvm.sh (shell function)" "$nvm_current" "$nvm_latest" "$TOOL_STATUS_INSTALL_DIR/nvm.sh"
    else
        add_missing_row "nvm" "$nvm_latest" "$TOOL_STATUS_INSTALL_DIR/nvm.sh"
    fi

    stow_latest="$LATEST_UNCHECKED"
    if command -v stow >/dev/null 2>&1; then
        [ "$include_updates" -eq 1 ] && stow_latest=$(get_stow_latest)
        stow_current=$(stow --version 2>/dev/null | grep -oE '[0-9.]+' | head -1)
        add_cmd_row "stow" "stow" "$stow_current" "$stow_latest" "$TOOL_STATUS_INSTALL_DIR/stow.sh"
    else
        add_missing_row "stow" "$stow_latest" "$TOOL_STATUS_INSTALL_DIR/stow.sh"
    fi

    tmux_latest="$LATEST_UNCHECKED"
    if command -v tmux >/dev/null 2>&1; then
        [ "$include_updates" -eq 1 ] && tmux_latest=$(get_github_latest https://github.com/tmux/tmux-builds tmux)
        tmux_current=$(tmux -V 2>/dev/null | awk '{print $2}')
        add_cmd_row "tmux" "tmux" "$tmux_current" "$tmux_latest" "$TOOL_STATUS_INSTALL_DIR/tmux.sh"
    else
        add_missing_row "tmux" "$tmux_latest" "$TOOL_STATUS_INSTALL_DIR/tmux.sh"
    fi
}

row_is_uninstallable() {
    local index="$1" command path nvm_dir

    [ "${PATHS[$index]}" != "not installed" ] || return 1

    command="${COMMANDS[$index]}"
    path="${PATHS[$index]}"

    case "$command" in
        code)
            [ "$path" = "$HOME/code" ] && [ -e "$HOME/code" ]
            ;;
        gh|nvim)
            [ -d "$TOOL_STATUS_LOCAL_STOW_DIR/$command" ] \
                && tool_status_path_mentions_prefix "$path" "$TOOL_STATUS_LOCAL_PREFIX"
            ;;
        nvm)
            nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"
            [ -d "$nvm_dir" ] && tool_status_path_mentions_prefix "$path" "$nvm_dir"
            ;;
        stow)
            [ -e "$TOOL_STATUS_LOCAL_BIN_DIR/stow" ] \
                && tool_status_path_mentions_prefix "$path" "$TOOL_STATUS_LOCAL_PREFIX"
            ;;
        tmux)
            [ -e "$TOOL_STATUS_LOCAL_BIN_DIR/tmux" ] \
                && tool_status_path_mentions_prefix "$path" "$TOOL_STATUS_LOCAL_PREFIX"
            ;;
        *)
            return 1
            ;;
    esac
}

row_is_actionable() {
    local index="$1"

    [ -n "${INSTALLERS[$index]}" ] || return 1
    [ "${PATHS[$index]}" = "not installed" ] && return 0
    latest_is_newer "${CURRENTS[$index]}" "${LATESTS[$index]}" && return 0
    [ "${CURRENTS[$index]}" = "unknown" ] \
        && [ "${LATESTS[$index]}" != "unknown" ] \
        && [ "${LATESTS[$index]}" != "$LATEST_UNCHECKED" ] \
        && return 0
    return 1
}

has_actionable_rows() {
    local i

    for i in "${!COMMANDS[@]}"; do
        row_is_actionable "$i" && return 0
    done

    return 1
}

first_actionable_row() {
    local i

    for i in "${!COMMANDS[@]}"; do
        if row_is_actionable "$i"; then
            printf '%s' "$i"
            return 0
        fi
    done

    printf '0'
}
