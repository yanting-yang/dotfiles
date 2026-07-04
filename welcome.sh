#!/usr/bin/env bash

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
REV=$'\033[7m'
NC=$'\033[0m'

DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INSTALL_DIR="$DOTFILES_DIR/scripts/install"

COMMANDS=()
PATHS=()
CURRENTS=()
LATESTS=()
INSTALLERS=()
STATUSES=()

repeat_char() {
    local char="$1" count="$2"
    local output="" i

    for ((i = 0; i < count; i++)); do
        output+="$char"
    done

    printf '%s' "$output"
}

truncate_to_width() {
    local value="$1" width="$2"

    if [ "$width" -le 3 ]; then
        printf '%.*s' "$width" "$value"
    elif [ "${#value}" -gt "$width" ]; then
        printf '%s...' "${value:0:$((width - 3))}"
    else
        printf '%s' "$value"
    fi
}

terminal_cols() {
    local cols

    cols=$(tput cols 2>/dev/null || printf '100')
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=100
    [ "$cols" -ge 60 ] || cols=60
    printf '%s' "$cols"
}

supports_tui() {
    [ -t 0 ] \
        && [ -t 1 ] \
        && command -v tput >/dev/null 2>&1 \
        && [ "${TERM:-dumb}" != "dumb" ]
}

get_github_latest() {
    local latest

    command -v curl >/dev/null 2>&1 || return 0
    latest=$(curl -Ls -o /dev/null -w '%{url_effective}' "$1/releases/latest" 2>/dev/null) || return 0
    latest="${latest##*/}"
    latest="${latest#v}"

    if [ -n "$latest" ] && [ "$latest" != "latest" ]; then
        printf '%s' "$latest"
    fi
}

get_stow_latest() {
    command -v curl >/dev/null 2>&1 || return 0
    curl -Ls https://ftp.gnu.org/gnu/stow/ 2>/dev/null \
        | sed -n 's/.*stow-\([0-9][0-9.]*\)\.tar\.gz.*/\1/p' \
        | sort -V \
        | tail -1
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
        && [ "$latest" != "unknown" ] \
        && [ "$current" != "unknown" ] \
        && [ "$latest" != "$current" ]
}

row_status() {
    local path="$1" current="$2" latest="$3"

    if [ "$path" = "not installed" ]; then
        printf 'missing'
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

load_rows() {
    local code_latest code_current
    local gh_latest gh_current
    local nvim_latest nvim_current
    local nvm_latest nvm_current nvm_dir
    local stow_latest stow_current
    local tmux_latest tmux_current
    local code_bin="$HOME/code"

    clear_rows

    code_latest=$(get_github_latest https://github.com/microsoft/vscode)
    if [ -x "$code_bin" ]; then
        code_current=$("$code_bin" --version 2>/dev/null | head -1 | awk '{print $2}')
        add_row "code" "$code_bin" "$code_current" "$code_latest" "$INSTALL_DIR/code.sh"
    else
        add_missing_row "code" "$code_latest" "$INSTALL_DIR/code.sh"
    fi

    gh_latest=$(get_github_latest https://github.com/cli/cli)
    if command -v gh >/dev/null 2>&1; then
        gh_current=$(gh --version 2>/dev/null | awk 'NR==1{print $3}')
        add_cmd_row "gh" "gh" "$gh_current" "$gh_latest" "$INSTALL_DIR/gh.sh"
    else
        add_missing_row "gh" "$gh_latest" "$INSTALL_DIR/gh.sh"
    fi

    nvim_latest=$(get_github_latest https://github.com/neovim/neovim)
    if command -v nvim >/dev/null 2>&1; then
        nvim_current=$(NVIM_LOG_FILE="${NVIM_LOG_FILE:-/tmp/nvim-welcome.log}" nvim --version 2>/dev/null \
            | awk 'NR==1{print $2}' \
            | sed 's/^v//')
        add_cmd_row "nvim" "nvim" "$nvim_current" "$nvim_latest" "$INSTALL_DIR/nvim.sh"
    else
        add_missing_row "nvim" "$nvim_latest" "$INSTALL_DIR/nvim.sh"
    fi

    nvm_latest=$(get_github_latest https://github.com/nvm-sh/nvm)
    nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"
    if [ -s "$nvm_dir/nvm.sh" ]; then
        # shellcheck source=/dev/null
        source "$nvm_dir/nvm.sh" --no-use
        nvm_current=$(nvm --version 2>/dev/null)
        add_row "nvm" "$nvm_dir/nvm.sh (shell function)" "$nvm_current" "$nvm_latest" "$INSTALL_DIR/nvm.sh"
    else
        add_missing_row "nvm" "$nvm_latest" "$INSTALL_DIR/nvm.sh"
    fi

    stow_latest=$(get_stow_latest)
    if command -v stow >/dev/null 2>&1; then
        stow_current=$(stow --version 2>/dev/null | grep -oE '[0-9.]+' | head -1)
        add_cmd_row "stow" "stow" "$stow_current" "$stow_latest" "$INSTALL_DIR/stow.sh"
    else
        add_missing_row "stow" "$stow_latest" "$INSTALL_DIR/stow.sh"
    fi

    tmux_latest=$(get_github_latest https://github.com/tmux/tmux-builds)
    if command -v tmux >/dev/null 2>&1; then
        tmux_current=$(tmux -V 2>/dev/null | awk '{print $2}')
        add_cmd_row "tmux" "tmux" "$tmux_current" "$tmux_latest" "$INSTALL_DIR/tmux.sh"
    else
        add_missing_row "tmux" "$tmux_latest" "$INSTALL_DIR/tmux.sh"
    fi
}

print_status() {
    local width="$1" status="$2"

    case "$status" in
        missing)
            printf "${RED}%-*s${NC}" "$width" "$status"
            ;;
        update|check)
            printf "${YELLOW}%-*s${NC}" "$width" "$status"
            ;;
        current)
            printf "${GREEN}%-*s${NC}" "$width" "$status"
            ;;
        *)
            printf "%-*s" "$width" "$status"
            ;;
    esac
}

print_table() {
    local command_width=7 path_width=4 current_width=7 latest_width=6 status_width=6
    local table_width hr title i

    for i in "${!COMMANDS[@]}"; do
        [ "${#COMMANDS[$i]}" -gt "$command_width" ] && command_width=${#COMMANDS[$i]}
        [ "${#PATHS[$i]}" -gt "$path_width" ] && path_width=${#PATHS[$i]}
        [ "${#CURRENTS[$i]}" -gt "$current_width" ] && current_width=${#CURRENTS[$i]}
        [ "${#LATESTS[$i]}" -gt "$latest_width" ] && latest_width=${#LATESTS[$i]}
        [ "${#STATUSES[$i]}" -gt "$status_width" ] && status_width=${#STATUSES[$i]}
    done

    table_width=$((command_width + path_width + current_width + latest_width + status_width + 8))
    hr=$(repeat_char '─' "$table_width")
    title="$(whoami)@$(hostname -s)  $(date '+%a %b %d %Y %H:%M')"

    printf "${BOLD}${CYAN}┌%s┐${NC}\n" "$hr"
    printf "${BOLD}${CYAN}│${NC}  %-*s${BOLD}${CYAN}│${NC}\n" "$((table_width - 2))" "$title"
    printf "${BOLD}${CYAN}└%s┘${NC}\n" "$hr"
    echo

    printf "${BOLD}%-*s  %-*s  %-*s  %-*s  %-*s${NC}\n" \
        "$command_width" "command" \
        "$path_width" "path" \
        "$current_width" "current" \
        "$latest_width" "latest" \
        "$status_width" "status"
    printf "%-*s  %-*s  %-*s  %-*s  %-*s\n" \
        "$command_width" "$(repeat_char '-' "$command_width")" \
        "$path_width" "$(repeat_char '-' "$path_width")" \
        "$current_width" "$(repeat_char '-' "$current_width")" \
        "$latest_width" "$(repeat_char '-' "$latest_width")" \
        "$status_width" "$(repeat_char '-' "$status_width")"

    for i in "${!COMMANDS[@]}"; do
        printf "%-*s  " "$command_width" "${COMMANDS[$i]}"
        if [ "${PATHS[$i]}" = "not installed" ]; then
            printf "${RED}%-*s${NC}  " "$path_width" "${PATHS[$i]}"
        else
            printf "%-*s  " "$path_width" "${PATHS[$i]}"
        fi
        printf "%-*s  " "$current_width" "${CURRENTS[$i]}"
        if latest_is_newer "${CURRENTS[$i]}" "${LATESTS[$i]}"; then
            printf "${YELLOW}%-*s${NC}  " "$latest_width" "${LATESTS[$i]}"
        else
            printf "%-*s  " "$latest_width" "${LATESTS[$i]}"
        fi
        print_status "$status_width" "${STATUSES[$i]}"
        printf '\n'
    done

    printf "${BOLD}${CYAN}└%s┘${NC}\n" "$hr"
}

row_is_actionable() {
    local index="$1"

    [ -n "${INSTALLERS[$index]}" ] || return 1
    [ "${PATHS[$index]}" = "not installed" ] && return 0
    latest_is_newer "${CURRENTS[$index]}" "${LATESTS[$index]}" && return 0
    [ "${CURRENTS[$index]}" = "unknown" ] && [ "${LATESTS[$index]}" != "unknown" ] && return 0
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

run_installer() {
    local index="$1" installer="${INSTALLERS[$1]}"
    local rc

    if [ ! -f "$installer" ]; then
        printf "${RED}No installer found:${NC} %s\n" "$installer"
        return 1
    fi

    printf '\n%sInstalling latest %s...%s\n' "$BOLD" "${COMMANDS[$index]}" "$NC"
    if bash "$installer"; then
        rc=0
    else
        rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        hash -r 2>/dev/null || true
        printf "${GREEN}Installed latest %s.${NC}\n" "${COMMANDS[$index]}"
    else
        printf "${RED}Failed to install %s (exit %s).${NC}\n" "${COMMANDS[$index]}" "$rc"
    fi

    return "$rc"
}

render_tui_row() {
    local index="$1" selected="$2" path_width="$3"
    local marker=' ' path status

    path=$(truncate_to_width "${PATHS[$index]}" "$path_width")
    status="${STATUSES[$index]}"
    [ "$index" -eq "$selected" ] && marker='>'

    if [ "$index" -eq "$selected" ]; then
        printf "${REV}%s %-7s %-8s %-10s %-10s %-*s${NC}\n" \
            "$marker" \
            "${COMMANDS[$index]}" \
            "$status" \
            "${CURRENTS[$index]}" \
            "${LATESTS[$index]}" \
            "$path_width" "$path"
        return 0
    fi

    printf '%s %-7s ' "$marker" "${COMMANDS[$index]}"
    print_status 8 "$status"
    printf ' %-10s %-10s %-*s\n' \
        "${CURRENTS[$index]}" \
        "${LATESTS[$index]}" \
        "$path_width" "$path"
}

render_tui() {
    local selected="$1" message="${2:-}"
    local cols path_width rule title i

    cols=$(terminal_cols)
    path_width=$((cols - 44))
    [ "$path_width" -ge 24 ] || path_width=24
    [ "$path_width" -le 100 ] || path_width=100
    rule=$(repeat_char '─' "$cols")
    title="$(whoami)@$(hostname -s)  $(date '+%a %b %d %Y %H:%M')"

    tput clear 2>/dev/null || true
    printf "${BOLD}${CYAN}Welcome${NC}  %s\n" "$title"
    printf "${DIM}%s${NC}\n" "$rule"
    printf "${DIM}Up/Down or j/k select  Enter install selected  a install all  r refresh  q quit${NC}\n\n"

    printf "${BOLD}%-2s %-7s %-8s %-10s %-10s %-*s${NC}\n" \
        "" "command" "status" "current" "latest" "$path_width" "path"
    printf "${DIM}%-2s %-7s %-8s %-10s %-10s %-*s${NC}\n" \
        "" "-------" "------" "-------" "------" "$path_width" "$(repeat_char '-' "$path_width")"

    for i in "${!COMMANDS[@]}"; do
        render_tui_row "$i" "$selected" "$path_width"
    done

    echo
    if has_actionable_rows; then
        printf "${DIM}Installable rows are missing tools, newer releases, or known latest versions with unknown local versions.${NC}\n"
    else
        printf "${GREEN}All managed commands appear current.${NC}\n"
    fi

    if [ -n "$message" ]; then
        printf '%s\n' "$message"
    fi
}

read_tui_key() {
    local key rest

    if ! IFS= read -rsn1 key; then
        return 1
    fi

    if [ "$key" = $'\033' ]; then
        if IFS= read -rsn2 -t 0.05 rest; then
            case "$rest" in
                '[A')
                    printf 'up'
                    ;;
                '[B')
                    printf 'down'
                    ;;
                *)
                    printf 'escape'
                    ;;
            esac
        else
            printf 'escape'
        fi
    elif [ "$key" = $'\r' ] || [ "$key" = $'\n' ] || [ -z "$key" ]; then
        printf 'enter'
    else
        printf '%s' "$key"
    fi
}

pause_for_tui() {
    printf '\n%s' "Press any key to return to welcome."
    read_tui_key >/dev/null 2>&1 || true
}

install_selected_from_tui() {
    local selected="$1"

    tput clear 2>/dev/null || true
    run_installer "$selected" || true
    pause_for_tui
    tput clear 2>/dev/null || true
    printf '%sRefreshing status...%s\n' "$DIM" "$NC"
    load_rows
}

install_all_from_tui() {
    local i ran=0

    tput clear 2>/dev/null || true
    for i in "${!COMMANDS[@]}"; do
        if row_is_actionable "$i"; then
            run_installer "$i" || true
            ran=1
        fi
    done

    if [ "$ran" -eq 0 ]; then
        printf "${GREEN}Nothing to install.${NC}\n"
    fi

    pause_for_tui
    tput clear 2>/dev/null || true
    printf '%sRefreshing status...%s\n' "$DIM" "$NC"
    load_rows
}

run_tui() {
    local selected key message row_count

    [ "${#COMMANDS[@]}" -gt 0 ] || return 0

    selected=$(first_actionable_row)
    message=""

    while true; do
        row_count="${#COMMANDS[@]}"
        if [ "$selected" -ge "$row_count" ]; then
            selected=$((row_count - 1))
        fi

        render_tui "$selected" "$message"
        if ! key=$(read_tui_key); then
            break
        fi

        message=""
        case "$key" in
            up|k|K)
                selected=$(((selected + row_count - 1) % row_count))
                ;;
            down|j|J)
                selected=$(((selected + 1) % row_count))
                ;;
            enter)
                if row_is_actionable "$selected"; then
                    install_selected_from_tui "$selected"
                    selected=$(first_actionable_row)
                    message="${GREEN}Status refreshed.${NC}"
                else
                    message="${YELLOW}${COMMANDS[$selected]} has no install action right now.${NC}"
                fi
                ;;
            a|A)
                if has_actionable_rows; then
                    install_all_from_tui
                    selected=$(first_actionable_row)
                    message="${GREEN}Status refreshed.${NC}"
                else
                    message="${GREEN}Nothing to install.${NC}"
                fi
                ;;
            r|R)
                tput clear 2>/dev/null || true
                printf '%sRefreshing status...%s\n' "$DIM" "$NC"
                load_rows
                selected=$(first_actionable_row)
                message="${GREEN}Status refreshed.${NC}"
                ;;
            q|Q|escape)
                render_tui "$selected" "${DIM}Skipped installs.${NC}"
                printf '\n'
                return 0
                ;;
        esac
    done
}

load_rows
if supports_tui; then
    run_tui
else
    print_table
fi
