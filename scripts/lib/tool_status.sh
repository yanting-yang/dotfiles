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
    local url="$1" cache_key="${2:-github}" latest release_url

    if tool_status_cache_read "$cache_key"; then
        return 0
    fi
    command -v curl >/dev/null 2>&1 || return 0

    # GitHub's first redirect identifies the latest full release; avoid
    # following it and downloading the release page.
    release_url=$(curl -fsSI -o /dev/null -w '%{redirect_url}' "$url/releases/latest" 2>/dev/null) \
        || release_url=""
    case "$release_url" in
        */releases/tag/*) ;;
        *)
            release_url=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "$url/releases/latest" 2>/dev/null) \
                || return 0
            ;;
    esac
    case "$release_url" in
        */releases/tag/*) latest="${release_url##*/}" ;;
        *) return 0 ;;
    esac
    latest="${latest#v}"

    if [ -n "$latest" ]; then
        tool_status_cache_write "$cache_key" "$latest"
        printf '%s' "$latest"
    fi
}

get_stow_latest() {
    local latest refs

    if tool_status_cache_read stow; then
        return 0
    fi

    latest=""
    if command -v curl >/dev/null 2>&1; then
        # Stow has tags but no GitHub releases. The matching-refs endpoint is
        # quicker than Git's ref advertisement; git remains the rate-limit fallback.
        refs=$(curl -fsSL \
            -H 'Accept: application/vnd.github+json' \
            https://api.github.com/repos/aspiers/stow/git/matching-refs/tags/v \
            2>/dev/null) || refs=""
        if [ -n "$refs" ]; then
            latest=$(printf '%s\n' "$refs" \
                | grep -oE '"ref"[[:space:]]*:[[:space:]]*"refs/tags/v[0-9.]+"' \
                | sed 's|.*refs/tags/\([^"]*\)"|\1|' \
                | grep -E '^v[0-9]+(\.[0-9]+)+$' \
                | sort -V \
                | tail -1) || latest=""
            latest="${latest#v}"
        fi
    fi

    if [ -z "$latest" ] && command -v git >/dev/null 2>&1; then
        latest=$(git ls-remote --tags --refs https://github.com/aspiers/stow.git 'v*' 2>/dev/null \
            | sed -n 's|.*refs/tags/v\([0-9][0-9.]*\)$|\1|p' \
            | sort -V \
            | tail -1) || latest=""
    fi

    if [ -n "$latest" ]; then
        tool_status_cache_write stow "$latest"
        printf '%s' "$latest"
    fi
}

get_nvm_node_latest() {
    local major="$1" cache_key="node-$1" index latest manifest mirror

    if tool_status_cache_read "$cache_key"; then
        return 0
    fi
    [[ "$major" =~ ^[1-9][0-9]*$ ]] || return 0
    command -v nvm >/dev/null 2>&1 || return 0

    latest=""
    if command -v nvm_get_mirror >/dev/null 2>&1 \
        && command -v nvm_download >/dev/null 2>&1; then
        mirror=$(nvm_get_mirror node std 2>/dev/null) || mirror=""
        mirror="${mirror%/}"
        if [ -n "$mirror" ]; then
            # The small per-major checksum prefix contains the release version
            # and avoids nvm parsing the complete catalog and refreshing aliases.
            manifest=$(nvm_download -L -s \
                --header 'Range: bytes=0-255' \
                "$mirror/latest-v${major}.x/SHASUMS256.txt" \
                -o - 2>/dev/null) || manifest=""
            if [[ "$manifest" =~ ^[[:xdigit:]]{64}[[:space:]]+node-v(${major}\.[0-9]+\.[0-9]+)- ]]; then
                latest="${BASH_REMATCH[1]}"
            fi

            if [ -z "$latest" ]; then
                index=$(nvm_download -L -s "$mirror/index.tab" -o - 2>/dev/null) || index=""
                latest=$(printf '%s\n' "$index" \
                    | awk -v prefix="v${major}." '
                        NR > 1 && index($1, prefix) == 1 && $1 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ {
                            sub(/^v/, "", $1)
                            print $1
                        }
                    ' \
                    | sort -V \
                    | tail -1) || latest=""
            fi
        fi
    fi

    if ! [[ "$latest" =~ ^${major}\.[0-9]+\.[0-9]+$ ]]; then
        latest=$(NVM_VERSION_ONLY=1 nvm version-remote "$major" 2>/dev/null) || return 0
        latest="${latest#v}"
    fi
    [[ "$latest" =~ ^${major}\.[0-9]+\.[0-9]+$ ]] || return 0

    tool_status_cache_write "$cache_key" "$latest"
    printf '%s' "$latest"
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

maple_font_dir() {
    printf '%s/.local/share/fonts/maple' "$HOME"
}

maple_font_installed() {
    local dir="$1"

    [ -d "$dir" ] || return 1
    find "$dir" -maxdepth 1 -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit 2>/dev/null \
        | grep -q .
}

maple_font_version() {
    local marker="$1/.maple-version" version

    if [ -s "$marker" ]; then
        IFS= read -r version <"$marker" 2>/dev/null || version=""
        if [ -n "$version" ]; then
            printf '%s' "$version"
            return 0
        fi
    fi

    printf 'unknown'
}

catppuccin_tmux_dir() {
    printf '%s/.config/tmux/plugins/catppuccin/tmux' "$HOME"
}

catppuccin_tmux_installed() {
    [ -e "$1/catppuccin.tmux" ]
}

catppuccin_tmux_version() {
    local dir="$1" tag

    command -v git >/dev/null 2>&1 || { printf 'unknown'; return 0; }
    tag=$(git -C "$dir" tag --points-at HEAD 2>/dev/null \
        | grep -E '^v[0-9]' \
        | sort -V \
        | tail -1)
    tag="${tag#v}"

    if [ -n "$tag" ]; then
        printf '%s' "$tag"
    else
        printf 'unknown'
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

node_version_is_valid() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

node_version_is_newer() {
    local current="$1" latest="$2"
    local current_major current_minor current_patch
    local latest_major latest_minor latest_patch

    node_version_is_valid "$current" || return 1
    node_version_is_valid "$latest" || return 1
    IFS=. read -r current_major current_minor current_patch <<<"$current"
    IFS=. read -r latest_major latest_minor latest_patch <<<"$latest"

    ((10#$latest_major > 10#$current_major)) && return 0
    ((10#$latest_major < 10#$current_major)) && return 1
    ((10#$latest_minor > 10#$current_minor)) && return 0
    ((10#$latest_minor < 10#$current_minor)) && return 1
    ((10#$latest_patch > 10#$current_patch))
}

row_status() {
    local path="$1" current="$2" latest="$3" command="${4:-}"

    if [ "$path" = "not installed" ]; then
        printf 'missing'
    elif [ "$latest" = "$LATEST_UNCHECKED" ]; then
        printf 'installed'
    elif [ "$command" = "node" ]; then
        if node_version_is_newer "$current" "$latest"; then
            printf 'update'
        elif node_version_is_valid "$current" && node_version_is_valid "$latest"; then
            printf 'current'
        else
            printf 'check'
        fi
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
    local index status

    [ -n "$current" ] || current="unknown"
    [ -n "$latest" ] || latest="unknown"
    status=$(row_status "$path" "$current" "$latest" "$command")

    COMMANDS+=("$command")
    PATHS+=("$path")
    CURRENTS+=("$current")
    LATESTS+=("$latest")
    INSTALLERS+=("$installer")
    STATUSES+=("$status")

    if [ -n "${TOOL_STATUS_ROW_CALLBACK:-}" ]; then
        index=$((${#COMMANDS[@]} - 1))
        "$TOOL_STATUS_ROW_CALLBACK" "$index"
    fi
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
    local TOOL_STATUS_ROW_CALLBACK="${2:-}"
    local code_latest code_current
    local gh_latest gh_current
    local node_latest node_current node_major
    local nvim_latest nvim_current
    local nvm_latest nvm_current nvm_dir nvm_available=0
    local stow_latest stow_current
    local tmux_latest tmux_current
    local kitty_latest kitty_current
    local maple_latest maple_current maple_dir
    local catppuccin_latest catppuccin_current catppuccin_dir
    local code_bin="$HOME/code"

    clear_rows

    nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"
    if command -v nvm >/dev/null 2>&1; then
        nvm_available=1
    elif [ -s "$nvm_dir/nvm.sh" ]; then
        # shellcheck source=/dev/null
        source "$nvm_dir/nvm.sh" --no-use
        command -v nvm >/dev/null 2>&1 && nvm_available=1
    fi

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
    if [ -s "$nvm_dir/nvm.sh" ]; then
        [ "$include_updates" -eq 1 ] && nvm_latest=$(get_github_latest https://github.com/nvm-sh/nvm nvm)
        if [ "$nvm_available" -eq 1 ]; then
            nvm_current=$(nvm --version 2>/dev/null)
        else
            nvm_current="unknown"
        fi
        add_row "nvm" "$nvm_dir/nvm.sh (shell function)" "$nvm_current" "$nvm_latest" "$TOOL_STATUS_INSTALL_DIR/nvm.sh"
    else
        add_missing_row "nvm" "$nvm_latest" "$TOOL_STATUS_INSTALL_DIR/nvm.sh"
    fi

    # Rendered as a child of nvm in the welcome table.
    node_latest="$LATEST_UNCHECKED"
    if command -v node >/dev/null 2>&1; then
        node_current=$(node --version 2>/dev/null)
        node_current="${node_current#v}"
        [[ "$node_current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || node_current="unknown"
        if [ "$include_updates" -eq 1 ]; then
            node_major="${node_current%%.*}"
            node_latest=""
            if [ "$nvm_available" -eq 1 ]; then
                node_latest=$(get_nvm_node_latest "$node_major")
            fi
            [ -n "$node_latest" ] || node_latest="unknown"
        fi
        add_cmd_row "node" "node" "$node_current" "$node_latest" ""
    else
        add_missing_row "node" "$node_latest"
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

    # Rendered as a child of tmux in the welcome table.
    catppuccin_latest="$LATEST_UNCHECKED"
    catppuccin_dir=$(catppuccin_tmux_dir)
    if catppuccin_tmux_installed "$catppuccin_dir"; then
        [ "$include_updates" -eq 1 ] && catppuccin_latest=$(get_github_latest https://github.com/catppuccin/tmux catppuccin-tmux)
        catppuccin_current=$(catppuccin_tmux_version "$catppuccin_dir")
        add_row "cat-tmux" "$catppuccin_dir" "$catppuccin_current" "$catppuccin_latest" "$TOOL_STATUS_INSTALL_DIR/catppuccin-tmux.sh"
    else
        add_missing_row "cat-tmux" "$catppuccin_latest" "$TOOL_STATUS_INSTALL_DIR/catppuccin-tmux.sh"
    fi

    kitty_latest="$LATEST_UNCHECKED"
    if command -v kitty >/dev/null 2>&1; then
        [ "$include_updates" -eq 1 ] && kitty_latest=$(get_github_latest https://github.com/kovidgoyal/kitty kitty)
        kitty_current=$(kitty --version 2>/dev/null | awk 'NR==1{print $2}')
        add_cmd_row "kitty" "kitty" "$kitty_current" "$kitty_latest" "$TOOL_STATUS_INSTALL_DIR/kitty.sh"
    else
        add_missing_row "kitty" "$kitty_latest" "$TOOL_STATUS_INSTALL_DIR/kitty.sh"
    fi

    maple_latest="$LATEST_UNCHECKED"
    maple_dir=$(maple_font_dir)
    if maple_font_installed "$maple_dir"; then
        [ "$include_updates" -eq 1 ] && maple_latest=$(get_github_latest https://github.com/subframe7536/maple-font maple)
        maple_current=$(maple_font_version "$maple_dir")
        add_row "maple" "$maple_dir" "$maple_current" "$maple_latest" "$TOOL_STATUS_INSTALL_DIR/maple-font.sh"
    else
        add_missing_row "maple" "$maple_latest" "$TOOL_STATUS_INSTALL_DIR/maple-font.sh"
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
        gh|nvim|kitty)
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
        maple)
            [ -d "$(maple_font_dir)" ]
            ;;
        *)
            return 1
            ;;
    esac
}

row_is_actionable() {
    local index="$1"

    if [ "${COMMANDS[$index]}" = "node" ]; then
        [ "${PATHS[$index]}" != "not installed" ] || return 1
        node_version_is_newer "${CURRENTS[$index]}" "${LATESTS[$index]}"
        return
    fi

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
