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
TUI_DIR="$DOTFILES_DIR/scripts/tui"
CODE_LIB="$DOTFILES_DIR/scripts/lib/code.sh"
NVM_TUI="$TUI_DIR/nvm.sh"
LATEST_UNCHECKED="unchecked"
WELCOME_CHECK_UPDATES=0

# shellcheck source=scripts/lib/code.sh
source "$CODE_LIB"

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
    [ "$include_updates" -eq 1 ] && code_latest=$(get_github_latest https://github.com/microsoft/vscode)
    if [ -x "$code_bin" ]; then
        code_current=$("$code_bin" --version 2>/dev/null | head -1 | awk '{print $2}')
        add_row "code" "$code_bin" "$code_current" "$code_latest" "$INSTALL_DIR/code.sh"
    else
        add_missing_row "code" "$code_latest" "$INSTALL_DIR/code.sh"
    fi

    gh_latest="$LATEST_UNCHECKED"
    [ "$include_updates" -eq 1 ] && gh_latest=$(get_github_latest https://github.com/cli/cli)
    if command -v gh >/dev/null 2>&1; then
        gh_current=$(gh --version 2>/dev/null | awk 'NR==1{print $3}')
        add_cmd_row "gh" "gh" "$gh_current" "$gh_latest" "$INSTALL_DIR/gh.sh"
    else
        add_missing_row "gh" "$gh_latest" "$INSTALL_DIR/gh.sh"
    fi

    nvim_latest="$LATEST_UNCHECKED"
    [ "$include_updates" -eq 1 ] && nvim_latest=$(get_github_latest https://github.com/neovim/neovim)
    if command -v nvim >/dev/null 2>&1; then
        nvim_current=$(NVIM_LOG_FILE="${NVIM_LOG_FILE:-/tmp/nvim-welcome.log}" nvim --version 2>/dev/null \
            | awk 'NR==1{print $2}' \
            | sed 's/^v//')
        add_cmd_row "nvim" "nvim" "$nvim_current" "$nvim_latest" "$INSTALL_DIR/nvim.sh"
    else
        add_missing_row "nvim" "$nvim_latest" "$INSTALL_DIR/nvim.sh"
    fi

    nvm_latest="$LATEST_UNCHECKED"
    [ "$include_updates" -eq 1 ] && nvm_latest=$(get_github_latest https://github.com/nvm-sh/nvm)
    nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"
    if [ -s "$nvm_dir/nvm.sh" ]; then
        # shellcheck source=/dev/null
        source "$nvm_dir/nvm.sh" --no-use
        nvm_current=$(nvm --version 2>/dev/null)
        add_row "nvm" "$nvm_dir/nvm.sh (shell function)" "$nvm_current" "$nvm_latest" "$INSTALL_DIR/nvm.sh"
    else
        add_missing_row "nvm" "$nvm_latest" "$INSTALL_DIR/nvm.sh"
    fi

    stow_latest="$LATEST_UNCHECKED"
    [ "$include_updates" -eq 1 ] && stow_latest=$(get_stow_latest)
    if command -v stow >/dev/null 2>&1; then
        stow_current=$(stow --version 2>/dev/null | grep -oE '[0-9.]+' | head -1)
        add_cmd_row "stow" "stow" "$stow_current" "$stow_latest" "$INSTALL_DIR/stow.sh"
    else
        add_missing_row "stow" "$stow_latest" "$INSTALL_DIR/stow.sh"
    fi

    tmux_latest="$LATEST_UNCHECKED"
    [ "$include_updates" -eq 1 ] && tmux_latest=$(get_github_latest https://github.com/tmux/tmux-builds)
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
        installed)
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

run_installer() {
    local index="$1" installer="${INSTALLERS[$1]}"
    local code_running_status rc

    if [ ! -f "$installer" ]; then
        printf "${RED}No installer found:${NC} %s\n" "$installer"
        return 1
    fi

    if [ "${COMMANDS[$index]}" = "code" ]; then
        if code_is_running; then
            printf "${YELLOW}code is running; skipping update.${NC}\n"
            return 0
        else
            code_running_status=$?
        fi

        if [ "$code_running_status" -eq 2 ]; then
            printf "${YELLOW}Could not check whether code is running; skipping update.${NC}\n"
            return 0
        fi
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

open_nvm_tui() {
    local rc=0

    tput clear 2>/dev/null || true
    if [ ! -f "$NVM_TUI" ]; then
        printf "${RED}No nvm TUI found:${NC} %s\n" "$NVM_TUI"
        pause_for_tui
        return 1
    fi

    # shellcheck source=/dev/null
    source "$NVM_TUI"
    NVM_TUI_PARENT="welcome"
    run_nvm_tui || rc=$?
    unset NVM_TUI_PARENT

    if [ "$rc" -ne 0 ]; then
        pause_for_tui
    fi

    tput clear 2>/dev/null || true
    printf '%sRefreshing status...%s\n' "$DIM" "$NC"
    WELCOME_CHECK_UPDATES=0
    load_rows 0
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
    printf "${DIM}j/k move  Enter install/update  / commands  r refresh local  q quit${NC}\n\n"

    printf "${BOLD}%-2s %-7s %-8s %-10s %-10s %-*s${NC}\n" \
        "" "command" "status" "current" "latest" "$path_width" "path"
    printf "${DIM}%-2s %-7s %-8s %-10s %-10s %-*s${NC}\n" \
        "" "-------" "------" "-------" "------" "$path_width" "$(repeat_char '-' "$path_width")"

    for i in "${!COMMANDS[@]}"; do
        render_tui_row "$i" "$selected" "$path_width"
    done

    echo
    if [ "$WELCOME_CHECK_UPDATES" -eq 0 ]; then
        printf "${DIM}Fast local status. Use /updates to check latest versions; /nvm for Node versions.${NC}\n"
    elif has_actionable_rows; then
        printf "${DIM}Update check view. q returns to local status; /quit exits welcome.${NC}\n"
    else
        printf "${GREEN}Update check view. All managed commands appear current. q returns to local status.${NC}\n"
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
    WELCOME_CHECK_UPDATES=0
    load_rows 0
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
    WELCOME_CHECK_UPDATES=0
    load_rows 0
}

show_slash_help() {
    tput clear 2>/dev/null || true
    printf "${BOLD}${CYAN}Slash commands${NC}\n\n"
    printf '  /nvm, /node       open Node version manager\n'
    printf '  /updates, /check  fetch latest versions for top-level tools\n'
    printf '  /local            return to fast local-only status\n'
    printf '  /install          install or update selected actionable row\n'
    printf '  /all              install or update all actionable rows\n'
    printf '  /help             show this help\n'
    printf '  /quit             quit welcome\n'
    pause_for_tui
}

prompt_slash_command() {
    local command

    SLASH_COMMAND=""
    printf '\n/%s' ''
    if ! IFS= read -r command; then
        printf '\n'
        return 1
    fi

    command="${command#/}"
    command="${command%%[[:space:]]*}"
    command="${command,,}"

    [ -n "$command" ] || command="help"
    SLASH_COMMAND="$command"
}

execute_slash_command() {
    local command="$1" selected="$2"

    case "$command" in
        nvm|node)
            open_nvm_tui || true
            SLASH_MESSAGE="${GREEN}Status refreshed.${NC}"
            ;;
        updates|check)
            tput clear 2>/dev/null || true
            printf '%sChecking latest versions...%s\n' "$DIM" "$NC"
            WELCOME_CHECK_UPDATES=1
            load_rows 1
            SLASH_MESSAGE="${GREEN}Latest versions loaded.${NC}"
            ;;
        local)
            WELCOME_CHECK_UPDATES=0
            load_rows 0
            SLASH_MESSAGE="${GREEN}Using local-only status.${NC}"
            ;;
        install|update)
            if row_is_actionable "$selected"; then
                install_selected_from_tui "$selected"
                SLASH_MESSAGE="${GREEN}Status refreshed.${NC}"
            else
                SLASH_MESSAGE="${YELLOW}${COMMANDS[$selected]} is not actionable. Run /updates to check remote versions.${NC}"
            fi
            ;;
        all)
            if has_actionable_rows; then
                install_all_from_tui
                SLASH_MESSAGE="${GREEN}Status refreshed.${NC}"
            else
                SLASH_MESSAGE="${GREEN}Nothing actionable. Run /updates to check remote versions.${NC}"
            fi
            ;;
        help|h|\?)
            show_slash_help
            SLASH_MESSAGE="${DIM}Use /nvm for Node versions or /updates for remote checks.${NC}"
            ;;
        q|quit|exit)
            WELCOME_TUI_QUIT=1
            ;;
        *)
            SLASH_MESSAGE="${YELLOW}Unknown command: /${command}. Try /help.${NC}"
            ;;
    esac
}

run_tui() {
    local selected key message row_count
    local command

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
        SLASH_MESSAGE=""
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
            u|U)
                if row_is_actionable "$selected"; then
                    install_selected_from_tui "$selected"
                    selected=$(first_actionable_row)
                    message="${GREEN}Status refreshed.${NC}"
                else
                    message="${YELLOW}${COMMANDS[$selected]} has no update action right now. Run /updates first.${NC}"
                fi
                ;;
            a|A)
                if has_actionable_rows; then
                    install_all_from_tui
                    selected=$(first_actionable_row)
                    message="${GREEN}Status refreshed.${NC}"
                else
                    message="${GREEN}Nothing actionable. Run /updates to check remote versions.${NC}"
                fi
                ;;
            /)
                prompt_slash_command || true
                command="$SLASH_COMMAND"
                execute_slash_command "$command" "$selected"
                if [ "${WELCOME_TUI_QUIT:-0}" -eq 1 ]; then
                    render_tui "$selected" "${DIM}Skipped installs.${NC}"
                    printf '\n'
                    return 0
                fi
                selected=$(first_actionable_row)
                message="$SLASH_MESSAGE"
                ;;
            r|R)
                tput clear 2>/dev/null || true
                printf '%sRefreshing local status...%s\n' "$DIM" "$NC"
                WELCOME_CHECK_UPDATES=0
                load_rows 0
                selected=$(first_actionable_row)
                message="${GREEN}Local status refreshed.${NC}"
                ;;
            q|Q|escape)
                if [ "$WELCOME_CHECK_UPDATES" -eq 1 ]; then
                    WELCOME_CHECK_UPDATES=0
                    load_rows 0
                    selected=$(first_actionable_row)
                    message="${DIM}Back to local welcome.${NC}"
                else
                    render_tui "$selected" "${DIM}Skipped installs.${NC}"
                    printf '\n'
                    return 0
                fi
                ;;
        esac
    done
}

load_rows 0
if supports_tui; then
    run_tui
else
    print_table
fi
