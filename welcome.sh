#!/bin/bash

RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

COMMANDS=()
PATHS=()
CURRENTS=()
LATESTS=()

repeat_char() {
    local char="$1" count="$2"
    local output="" i

    for ((i = 0; i < count; i++)); do
        output+="$char"
    done

    printf '%s' "$output"
}

get_github_latest() {
    local latest
    latest=$(curl -Ls -o /dev/null -w '%{url_effective}' "$1/releases/latest" 2>/dev/null)
    latest="${latest##*/}"
    latest="${latest#v}"
    if [ "$latest" != "latest" ]; then
        printf '%s' "$latest"
    fi
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

add_row() {
    COMMANDS+=("$1")
    PATHS+=("$2")
    CURRENTS+=("${3:-unknown}")
    LATESTS+=("${4:-unknown}")
}

add_missing_row() {
    add_row "$1" "not installed" "unknown" "unknown"
}

add_cmd_row() {
    local label="$1" cmd="$2" current="$3" latest="$4"
    local path

    if path=$(get_cmd_path "$cmd"); then
        add_row "$label" "$path" "$current" "$latest"
    else
        add_missing_row "$label"
    fi
}

latest_is_newer() {
    local current="$1" latest="$2"
    [ -n "$latest" ] && [ "$latest" != "unknown" ] && [ "$current" != "unknown" ] && [ "$latest" != "$current" ]
}

print_table() {
    local command_width=7 path_width=4 current_width=7 latest_width=6
    local table_width hr title i

    for i in "${!COMMANDS[@]}"; do
        [ "${#COMMANDS[$i]}" -gt "$command_width" ] && command_width=${#COMMANDS[$i]}
        [ "${#PATHS[$i]}" -gt "$path_width" ] && path_width=${#PATHS[$i]}
        [ "${#CURRENTS[$i]}" -gt "$current_width" ] && current_width=${#CURRENTS[$i]}
        [ "${#LATESTS[$i]}" -gt "$latest_width" ] && latest_width=${#LATESTS[$i]}
    done

    table_width=$((command_width + path_width + current_width + latest_width + 6))
    hr=$(repeat_char '─' "$table_width")
    title="$(whoami)@$(hostname -s)  $(date '+%a %b %d %Y %H:%M')"

    printf "${BOLD}${CYAN}┌%s┐${NC}\n" "$hr"
    printf "${BOLD}${CYAN}│${NC}  %-*s${BOLD}${CYAN}│${NC}\n" "$((table_width - 2))" "$title"
    printf "${BOLD}${CYAN}└%s┘${NC}\n" "$hr"
    echo

    printf "${BOLD}%-*s  %-*s  %-*s  %-*s${NC}\n" \
        "$command_width" "command" \
        "$path_width" "path" \
        "$current_width" "current" \
        "$latest_width" "latest"
    printf "%-*s  %-*s  %-*s  %-*s\n" \
        "$command_width" "$(repeat_char '-' "$command_width")" \
        "$path_width" "$(repeat_char '-' "$path_width")" \
        "$current_width" "$(repeat_char '-' "$current_width")" \
        "$latest_width" "$(repeat_char '-' "$latest_width")"

    for i in "${!COMMANDS[@]}"; do
        printf "%-*s  " "$command_width" "${COMMANDS[$i]}"
        if [ "${PATHS[$i]}" = "not installed" ]; then
            printf "${RED}%-*s${NC}  " "$path_width" "${PATHS[$i]}"
        else
            printf "%-*s  " "$path_width" "${PATHS[$i]}"
        fi
        printf "%-*s  " "$current_width" "${CURRENTS[$i]}"
        if latest_is_newer "${CURRENTS[$i]}" "${LATESTS[$i]}"; then
            printf "${YELLOW}%-*s${NC}\n" "$latest_width" "${LATESTS[$i]}"
        else
            printf "%-*s\n" "$latest_width" "${LATESTS[$i]}"
        fi
    done

    printf "${BOLD}${CYAN}└%s┘${NC}\n" "$hr"
}

# code (installed directly to $HOME/code, not in PATH)
CODE_BIN="$HOME/code"
if [ -x "$CODE_BIN" ]; then
    CODE_CURRENT=$("$CODE_BIN" --version 2>/dev/null | head -1 | awk '{print $2}')
    CODE_LATEST=$(get_github_latest https://github.com/microsoft/vscode)
    add_row "code" "$CODE_BIN" "$CODE_CURRENT" "$CODE_LATEST"
else
    add_missing_row "code"
fi

# gh
if command -v gh >/dev/null 2>&1; then
    GH_CURRENT=$(gh --version 2>/dev/null | awk 'NR==1{print $3}')
    GH_LATEST=$(get_github_latest https://github.com/cli/cli)
    add_cmd_row "gh" "gh" "$GH_CURRENT" "$GH_LATEST"
else
    add_missing_row "gh"
fi

# nvim
if command -v nvim >/dev/null 2>&1; then
    NVIM_CURRENT=$(nvim --version 2>/dev/null | awk 'NR==1{print $2}' | sed 's/^v//')
    NVIM_LATEST=$(get_github_latest https://github.com/neovim/neovim)
    add_cmd_row "nvim" "nvim" "$NVIM_CURRENT" "$NVIM_LATEST"
else
    add_missing_row "nvim"
fi

# nvm (shell function, not a binary)
NVM_DIR="${NVM_DIR:-$HOME/.config/nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh" --no-use
    NVM_CURRENT=$(nvm --version 2>/dev/null)
    NVM_LATEST=$(cd "$NVM_DIR" && git describe --abbrev=0 --tags --match "v[0-9]*" \
        "$(git rev-list --tags --max-count=1)" 2>/dev/null | sed 's/^v//')
    add_row "nvm" "$NVM_DIR/nvm.sh (shell function)" "$NVM_CURRENT" "$NVM_LATEST"
else
    add_missing_row "nvm"
fi

# stow
if command -v stow >/dev/null 2>&1; then
    STOW_CURRENT=$(stow --version 2>/dev/null | grep -oP '[\d.]+' | head -1)
    STOW_LATEST=$(curl -s https://ftp.gnu.org/gnu/stow/ 2>/dev/null \
        | grep -oP 'stow-\K[\d.]+(?=\.tar\.gz)' | sort -V | tail -1)
    add_cmd_row "stow" "stow" "$STOW_CURRENT" "$STOW_LATEST"
else
    add_missing_row "stow"
fi

# tmux
if command -v tmux >/dev/null 2>&1; then
    TMUX_CURRENT=$(tmux -V 2>/dev/null | awk '{print $2}')
    TMUX_LATEST=$(get_github_latest https://github.com/tmux/tmux-builds)
    add_cmd_row "tmux" "tmux" "$TMUX_CURRENT" "$TMUX_LATEST"
else
    add_missing_row "tmux"
fi

print_table
