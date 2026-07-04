#!/usr/bin/env bash

DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR="$DOTFILES_DIR/scripts/lib"
TUI_DIR="$DOTFILES_DIR/scripts/tui"
NVM_TUI="$TUI_DIR/nvm.sh"
WELCOME_CHECK_UPDATES=0

# shellcheck source=scripts/lib/tui.sh
source "$LIB_DIR/tui.sh"
# shellcheck source=scripts/lib/code.sh
source "$LIB_DIR/code.sh"
# shellcheck source=scripts/lib/tool_status.sh
source "$LIB_DIR/tool_status.sh"

RED="$TUI_RED"
GREEN="$TUI_GREEN"
YELLOW="$TUI_YELLOW"
CYAN="$TUI_CYAN"
BOLD="$TUI_BOLD"
DIM="$TUI_DIM"
REV="$TUI_REV"
NC="$TUI_NC"

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
    hr=$(tui_repeat_char '─' "$table_width")
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
        "$command_width" "$(tui_repeat_char '-' "$command_width")" \
        "$path_width" "$(tui_repeat_char '-' "$path_width")" \
        "$current_width" "$(tui_repeat_char '-' "$current_width")" \
        "$latest_width" "$(tui_repeat_char '-' "$latest_width")" \
        "$status_width" "$(tui_repeat_char '-' "$status_width")"

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

    tui_clear
    if [ ! -f "$NVM_TUI" ]; then
        printf "${RED}No nvm TUI found:${NC} %s\n" "$NVM_TUI"
        tui_pause welcome
        return 1
    fi

    # shellcheck source=/dev/null
    source "$NVM_TUI"
    NVM_TUI_PARENT="welcome"
    run_nvm_tui || rc=$?
    unset NVM_TUI_PARENT

    if [ "$rc" -ne 0 ]; then
        tui_pause welcome
    fi

    tui_clear
    printf '%sRefreshing status...%s\n' "$DIM" "$NC"
    WELCOME_CHECK_UPDATES=0
    load_rows 0
    return "$rc"
}

render_tui_row() {
    local index="$1" selected="$2" path_width="$3"
    local marker=' ' path status

    path=$(tui_truncate "${PATHS[$index]}" "$path_width")
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
    local cols path_width rule title quit_hint i

    cols=$(tui_cols)
    path_width=$((cols - 44))
    [ "$path_width" -ge 24 ] || path_width=24
    [ "$path_width" -le 100 ] || path_width=100
    rule=$(tui_repeat_char '─' "$cols")
    title="$(whoami)@$(hostname -s)  $(date '+%a %b %d %Y %H:%M')"
    quit_hint="q quit"
    [ "$WELCOME_CHECK_UPDATES" -eq 1 ] && quit_hint="q back"

    tui_clear
    printf "${BOLD}${CYAN}Welcome${NC}  %s\n" "$title"
    printf "${DIM}%s${NC}\n" "$rule"
    printf "${DIM}j/k move  Enter install/update  / commands  r refresh local  %s${NC}\n\n" "$quit_hint"

    printf "${BOLD}%-2s %-7s %-8s %-10s %-10s %-*s${NC}\n" \
        "" "command" "status" "current" "latest" "$path_width" "path"
    printf "${DIM}%-2s %-7s %-8s %-10s %-10s %-*s${NC}\n" \
        "" "-------" "------" "-------" "------" "$path_width" "$(tui_repeat_char '-' "$path_width")"

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

install_selected_from_tui() {
    local selected="$1"

    tui_clear
    run_installer "$selected" || true
    tui_pause welcome
    tui_clear
    printf '%sRefreshing status...%s\n' "$DIM" "$NC"
    WELCOME_CHECK_UPDATES=0
    load_rows 0
}

install_all_from_tui() {
    local i ran=0

    tui_clear
    for i in "${!COMMANDS[@]}"; do
        if row_is_actionable "$i"; then
            run_installer "$i" || true
            ran=1
        fi
    done

    if [ "$ran" -eq 0 ]; then
        printf "${GREEN}Nothing to install.${NC}\n"
    fi

    tui_pause welcome
    tui_clear
    printf '%sRefreshing status...%s\n' "$DIM" "$NC"
    WELCOME_CHECK_UPDATES=0
    load_rows 0
}

show_slash_help() {
    tui_clear
    printf "${BOLD}${CYAN}Slash commands${NC}\n\n"
    printf '  /nvm, /node       open Node version manager\n'
    printf '  /updates, /check  fetch latest versions for top-level tools\n'
    printf '  /local            return to fast local-only status\n'
    printf '  /install          install or update selected actionable row\n'
    printf '  /all              install or update all actionable rows\n'
    printf '  /help             show this help\n'
    printf '  /quit             quit welcome\n'
    tui_pause welcome
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
            tui_clear
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
        if ! key=$(tui_read_key); then
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
                tui_clear
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
if tui_supports; then
    run_tui
else
    print_table
fi
