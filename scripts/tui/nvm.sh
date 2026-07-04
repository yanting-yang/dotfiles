#!/usr/bin/env bash

NVM_TUI_RED=$'\033[0;31m'
NVM_TUI_GREEN=$'\033[0;32m'
NVM_TUI_YELLOW=$'\033[0;33m'
NVM_TUI_CYAN=$'\033[0;36m'
NVM_TUI_BOLD=$'\033[1m'
NVM_TUI_DIM=$'\033[2m'
NVM_TUI_REV=$'\033[7m'
NVM_TUI_NC=$'\033[0m'

NVM_TUI_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
NVM_TUI_NVM_DIR="${NVM_DIR:-$HOME/.config/nvm}"
NVM_TUI_INSTALLED=()
NVM_TUI_REMOTE=()
NVM_TUI_LTS_VERSIONS=()
NVM_TUI_LTS_LABELS=()
NVM_TUI_VERSIONS=()
NVM_TUI_STATUSES=()
NVM_TUI_LTS=()
NVM_TUI_CURRENT="none"
NVM_TUI_REMOTE_LOADED=0
NVM_TUI_REMOTE_ERROR=""
NVM_TUI_SOURCED=0
[ "${#BASH_SOURCE[@]}" -gt 1 ] && NVM_TUI_SOURCED=1

nvm_tui_repeat_char() {
    local char="$1" count="$2"
    local output="" i

    for ((i = 0; i < count; i++)); do
        output+="$char"
    done

    printf '%s' "$output"
}

nvm_tui_truncate() {
    local value="$1" width="$2"

    if [ "$width" -le 3 ]; then
        printf '%.*s' "$width" "$value"
    elif [ "${#value}" -gt "$width" ]; then
        printf '%s...' "${value:0:$((width - 3))}"
    else
        printf '%s' "$value"
    fi
}

nvm_tui_cols() {
    local cols

    cols=$(tput cols 2>/dev/null || printf '100')
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=100
    [ "$cols" -ge 60 ] || cols=60
    printf '%s' "$cols"
}

nvm_tui_lines() {
    local lines

    lines=$(tput lines 2>/dev/null || printf '24')
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=24
    [ "$lines" -ge 12 ] || lines=12
    printf '%s' "$lines"
}

nvm_tui_supports_tui() {
    [ -t 0 ] \
        && [ -t 1 ] \
        && command -v tput >/dev/null 2>&1 \
        && [ "${TERM:-dumb}" != "dumb" ]
}

nvm_tui_is_sourced() {
    [ "$NVM_TUI_SOURCED" -eq 1 ]
}

nvm_tui_back_message() {
    if [ "${NVM_TUI_PARENT:-}" = "welcome" ]; then
        printf 'Back to welcome.'
    else
        printf 'Opening welcome.'
    fi
}

nvm_tui_load_nvm() {
    NVM_TUI_NVM_DIR="${NVM_DIR:-$HOME/.config/nvm}"

    if ! command -v nvm >/dev/null 2>&1; then
        [ -s "$NVM_TUI_NVM_DIR/nvm.sh" ] || return 1
        # shellcheck source=/dev/null
        source "$NVM_TUI_NVM_DIR/nvm.sh" --no-use
    fi

    command -v nvm >/dev/null 2>&1
}

nvm_tui_append_row() {
    NVM_TUI_VERSIONS+=("$1")
    NVM_TUI_STATUSES+=("$2")
    NVM_TUI_LTS+=("$(nvm_tui_lts_label_for "$1")")
}

nvm_tui_row_has_version() {
    local candidate="$1" version

    for version in "${NVM_TUI_VERSIONS[@]}"; do
        [ "$version" = "$candidate" ] && return 0
    done

    return 1
}

nvm_tui_load_installed_versions() {
    local version

    NVM_TUI_INSTALLED=()
    NVM_TUI_CURRENT=$(nvm current 2>/dev/null || printf 'none')
    [ -n "$NVM_TUI_CURRENT" ] || NVM_TUI_CURRENT="none"

    while IFS= read -r version; do
        [ -n "$version" ] && NVM_TUI_INSTALLED+=("$version")
    done < <(
        nvm ls --no-colors 2>/dev/null \
            | sed -n 's/^[[:space:]]*[-*=>]*[[:space:]]*\(v[0-9][^[:space:]]*\).*/\1/p' \
            | awk '!seen[$0]++'
    )
}

nvm_tui_load_remote_versions() {
    local version

    NVM_TUI_REMOTE=()
    NVM_TUI_LTS_VERSIONS=()
    NVM_TUI_LTS_LABELS=()
    NVM_TUI_REMOTE_ERROR=""

    while IFS= read -r version; do
        [ -n "$version" ] && NVM_TUI_REMOTE+=("$version")
    done < <(
        nvm ls-remote 2>/dev/null \
            | sed -n 's/^[[:space:]]*\(v[0-9][^[:space:]]*\).*/\1/p' \
            | awk '!seen[$0]++ { versions[++count] = $0 } END { for (i = count; i >= 1; i--) print versions[i] }'
    )

    if [ "${#NVM_TUI_REMOTE[@]}" -eq 0 ]; then
        NVM_TUI_REMOTE_ERROR="Could not load remote versions from nvm ls-remote."
        NVM_TUI_REMOTE_LOADED=0
        return 1
    fi

    while IFS=$'\t' read -r version lts_label; do
        [ -n "$version" ] || continue
        [ -n "$lts_label" ] || lts_label="yes"
        NVM_TUI_LTS_VERSIONS+=("$version")
        NVM_TUI_LTS_LABELS+=("$lts_label")
    done < <(
        nvm ls-remote --lts 2>/dev/null \
            | awk '
                /^[[:space:]]*v[0-9]/ {
                    version = $1
                    label = "yes"
                    if (match($0, /\((Latest )?LTS: [^)]+\)/)) {
                        label = substr($0, RSTART, RLENGTH)
                        sub(/^\((Latest )?LTS: /, "", label)
                        sub(/\)$/, "", label)
                    }
                    print version "\t" label
                }
            '
    )

    NVM_TUI_REMOTE_LOADED=1
}

nvm_tui_lts_label_for() {
    local version="$1" i

    for i in "${!NVM_TUI_LTS_VERSIONS[@]}"; do
        if [ "${NVM_TUI_LTS_VERSIONS[$i]}" = "$version" ]; then
            printf '%s' "${NVM_TUI_LTS_LABELS[$i]}"
            return 0
        fi
    done

    printf '-'
}

nvm_tui_build_rows() {
    local version status

    NVM_TUI_VERSIONS=()
    NVM_TUI_STATUSES=()
    NVM_TUI_LTS=()

    for version in "${NVM_TUI_INSTALLED[@]}"; do
        if [ "$version" = "$NVM_TUI_CURRENT" ]; then
            status="active"
        else
            status="installed"
        fi
        nvm_tui_append_row "$version" "$status"
    done

    for version in "${NVM_TUI_REMOTE[@]}"; do
        if ! nvm_tui_row_has_version "$version"; then
            nvm_tui_append_row "$version" "available"
        fi
    done
}

nvm_tui_refresh_versions() {
    local include_remote="${1:-0}"

    nvm_tui_load_installed_versions
    if [ "$include_remote" -eq 1 ]; then
        nvm_tui_load_remote_versions || true
    fi
    nvm_tui_build_rows
}

nvm_tui_version_path() {
    local version="$1" status="$2"

    if [ "$status" = "available" ]; then
        printf 'remote'
    else
        printf '%s/versions/node/%s/bin/node' "$NVM_TUI_NVM_DIR" "$version"
    fi
}

nvm_tui_first_selected() {
    local i

    for i in "${!NVM_TUI_VERSIONS[@]}"; do
        if [ "${NVM_TUI_VERSIONS[$i]}" = "$NVM_TUI_CURRENT" ]; then
            printf '%s' "$i"
            return 0
        fi
    done

    printf '0'
}

nvm_tui_read_key() {
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

nvm_tui_pause() {
    printf '\n%s' "Press any key to return to nvm."
    nvm_tui_read_key >/dev/null 2>&1 || true
}

nvm_tui_print_status() {
    local width="$1" status="$2"

    case "$status" in
        active)
            printf "${NVM_TUI_GREEN}%-*s${NVM_TUI_NC}" "$width" "$status"
            ;;
        available)
            printf "${NVM_TUI_CYAN}%-*s${NVM_TUI_NC}" "$width" "$status"
            ;;
        *)
            printf '%-*s' "$width" "$status"
            ;;
    esac
}

nvm_tui_print_lts() {
    local width="$1" lts="$2"

    if [ "$lts" = "-" ]; then
        printf '%-*s' "$width" "$lts"
    else
        printf "${NVM_TUI_YELLOW}%-*s${NVM_TUI_NC}" "$width" "$lts"
    fi
}

nvm_tui_render_row() {
    local index="$1" selected="$2" path_width="$3"
    local marker=' ' version status lts path

    version="${NVM_TUI_VERSIONS[$index]}"
    status="${NVM_TUI_STATUSES[$index]}"
    lts="${NVM_TUI_LTS[$index]}"
    path=$(nvm_tui_truncate "$(nvm_tui_version_path "$version" "$status")" "$path_width")
    [ "$index" -eq "$selected" ] && marker='>'

    if [ "$index" -eq "$selected" ]; then
        printf "${NVM_TUI_REV}%s %-14s %-10s %-12s %-*s${NVM_TUI_NC}\n" \
            "$marker" "$version" "$status" "$lts" "$path_width" "$path"
        return 0
    fi

    printf '%s %-14s ' "$marker" "$version"
    nvm_tui_print_status 10 "$status"
    printf ' '
    nvm_tui_print_lts 12 "$lts"
    printf ' %-*s\n' "$path_width" "$path"
}

nvm_tui_render() {
    local selected="$1" message="${2:-}"
    local cols lines path_width rule visible_rows row_count start end i

    cols=$(nvm_tui_cols)
    lines=$(nvm_tui_lines)
    path_width=$((cols - 44))
    [ "$path_width" -ge 16 ] || path_width=16
    [ "$path_width" -le 100 ] || path_width=100
    visible_rows=$((lines - 11))
    [ "$visible_rows" -ge 4 ] || visible_rows=4
    rule=$(nvm_tui_repeat_char '─' "$cols")
    row_count="${#NVM_TUI_VERSIONS[@]}"

    if [ "$row_count" -le "$visible_rows" ]; then
        start=0
        end=$((row_count - 1))
    else
        start=$((selected - visible_rows / 2))
        [ "$start" -ge 0 ] || start=0
        [ "$start" -le "$((row_count - visible_rows))" ] || start=$((row_count - visible_rows))
        end=$((start + visible_rows - 1))
    fi

    tput clear 2>/dev/null || true
    printf "${NVM_TUI_BOLD}${NVM_TUI_CYAN}nvm Node versions${NVM_TUI_NC}  current: %s\n" "$NVM_TUI_CURRENT"
    printf "${NVM_TUI_DIM}%s${NVM_TUI_NC}\n" "$rule"
    printf "${NVM_TUI_DIM}j/k move  Enter use/install  i install prompt  d uninstall  r refresh remote  q back${NVM_TUI_NC}\n\n"

    if [ "$row_count" -eq 0 ]; then
        printf "${NVM_TUI_YELLOW}No Node versions were found.${NVM_TUI_NC}\n"
        printf "${NVM_TUI_DIM}Press r to retry nvm ls-remote, or i to install a version such as lts/*.${NVM_TUI_NC}\n"
    else
        printf "${NVM_TUI_BOLD}%-2s %-14s %-10s %-12s %-*s${NVM_TUI_NC}\n" \
            "" "version" "status" "lts" "$path_width" "path"
        printf "${NVM_TUI_DIM}%-2s %-14s %-10s %-12s %-*s${NVM_TUI_NC}\n" \
            "" "-------" "------" "---" "$path_width" "$(nvm_tui_repeat_char '-' "$path_width")"

        for ((i = start; i <= end; i++)); do
            nvm_tui_render_row "$i" "$selected" "$path_width"
        done

        if [ "$row_count" -gt "$visible_rows" ]; then
            printf "${NVM_TUI_DIM}showing %s-%s of %s${NVM_TUI_NC}\n" "$((start + 1))" "$((end + 1))" "$row_count"
        fi
    fi

    if [ "$NVM_TUI_REMOTE_LOADED" -eq 1 ]; then
        printf "${NVM_TUI_DIM}remote versions loaded from nvm ls-remote${NVM_TUI_NC}\n"
    elif [ -n "$NVM_TUI_REMOTE_ERROR" ]; then
        printf "${NVM_TUI_YELLOW}%s${NVM_TUI_NC}\n" "$NVM_TUI_REMOTE_ERROR"
    fi

    if [ -n "$message" ]; then
        printf '\n%s\n' "$message"
    fi
}

nvm_tui_install_version() {
    local version="$1"

    printf '\n%sInstalling %s...%s\n' "$NVM_TUI_BOLD" "$version" "$NVM_TUI_NC"
    nvm install "$version"
    printf '\n%sUsing Node %s...%s\n' "$NVM_TUI_BOLD" "$version" "$NVM_TUI_NC"
    nvm use "$version"
}

nvm_tui_install_prompt() {
    local version

    tput clear 2>/dev/null || true
    printf "${NVM_TUI_BOLD}Install Node version${NVM_TUI_NC}\n"
    printf "${NVM_TUI_DIM}Examples: lts/*, node, 22, 22.12.0${NVM_TUI_NC}\n\n"
    printf 'Version to install [lts/*]: '

    if ! IFS= read -r version; then
        return 1
    fi

    [ -n "$version" ] || version="lts/*"
    nvm_tui_install_version "$version"
}

nvm_tui_use_selected() {
    local selected="$1" version status

    [ "${#NVM_TUI_VERSIONS[@]}" -gt 0 ] || return 1
    version="${NVM_TUI_VERSIONS[$selected]}"
    status="${NVM_TUI_STATUSES[$selected]}"

    tput clear 2>/dev/null || true
    if [ "$status" = "available" ]; then
        nvm_tui_install_version "$version"
    else
        printf "${NVM_TUI_BOLD}Using Node %s...${NVM_TUI_NC}\n\n" "$version"
        nvm use "$version"
    fi

    if ! nvm_tui_is_sourced; then
        printf "\n${NVM_TUI_YELLOW}Note:${NVM_TUI_NC} this use action only affects this child shell."
        printf '\nSource this script or open it from the welcome TUI to persist it.\n'
    fi
}

nvm_tui_uninstall_selected() {
    local selected="$1" version status answer

    [ "${#NVM_TUI_VERSIONS[@]}" -gt 0 ] || return 1
    version="${NVM_TUI_VERSIONS[$selected]}"
    status="${NVM_TUI_STATUSES[$selected]}"

    if [ "$status" = "available" ]; then
        printf "${NVM_TUI_YELLOW}%s is not installed.${NVM_TUI_NC}\n" "$version"
        return 1
    fi

    tput clear 2>/dev/null || true
    printf "${NVM_TUI_BOLD}Uninstall Node %s?${NVM_TUI_NC} [y/N] " "$version"
    if ! IFS= read -r answer; then
        return 1
    fi

    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            printf '\n%sUninstalling %s...%s\n' "$NVM_TUI_BOLD" "$version" "$NVM_TUI_NC"
            nvm uninstall "$version"
            ;;
        *)
            printf '\nSkipped uninstall.\n'
            ;;
    esac
}

run_nvm_tui() {
    local selected key message row_count

    if ! nvm_tui_load_nvm; then
        printf "${NVM_TUI_RED}nvm is not installed.${NVM_TUI_NC}\n"
        printf 'Install nvm first with %s\n' "$NVM_TUI_DIR/scripts/install/nvm.sh"
        return 1
    fi

    nvm_tui_refresh_versions 1

    if ! nvm_tui_supports_tui; then
        printf 'current: %s\n' "$NVM_TUI_CURRENT"
        printf '%-14s %-10s %-12s\n' "version" "status" "lts"
        for selected in "${!NVM_TUI_VERSIONS[@]}"; do
            printf '%-14s %-10s %-12s\n' \
                "${NVM_TUI_VERSIONS[$selected]}" \
                "${NVM_TUI_STATUSES[$selected]}" \
                "${NVM_TUI_LTS[$selected]}"
        done
        return 0
    fi

    selected=$(nvm_tui_first_selected)
    message=""

    while true; do
        row_count="${#NVM_TUI_VERSIONS[@]}"
        if [ "$row_count" -eq 0 ]; then
            selected=0
        elif [ "$selected" -ge "$row_count" ]; then
            selected=$((row_count - 1))
        fi

        nvm_tui_render "$selected" "$message"
        if ! key=$(nvm_tui_read_key); then
            break
        fi

        message=""
        case "$key" in
            up|k|K)
                [ "$row_count" -gt 0 ] && selected=$(((selected + row_count - 1) % row_count))
                ;;
            down|j|J)
                [ "$row_count" -gt 0 ] && selected=$(((selected + 1) % row_count))
                ;;
            enter)
                if [ "$row_count" -gt 0 ]; then
                    nvm_tui_use_selected "$selected" || true
                    nvm_tui_pause
                    nvm_tui_refresh_versions 0
                    selected=$(nvm_tui_first_selected)
                    message="${NVM_TUI_GREEN}Selected Node ${NVM_TUI_CURRENT}.${NVM_TUI_NC}"
                else
                    message="${NVM_TUI_YELLOW}No versions to use or install. Press r to retry remote lookup.${NVM_TUI_NC}"
                fi
                ;;
            i|I)
                nvm_tui_install_prompt || true
                nvm_tui_pause
                nvm_tui_refresh_versions 0
                selected=$(nvm_tui_first_selected)
                message="${NVM_TUI_GREEN}Versions refreshed.${NVM_TUI_NC}"
                ;;
            d|D|x|X)
                if [ "$row_count" -gt 0 ]; then
                    nvm_tui_uninstall_selected "$selected" || true
                    nvm_tui_pause
                    nvm_tui_refresh_versions 0
                    selected=$(nvm_tui_first_selected)
                    message="${NVM_TUI_GREEN}Versions refreshed.${NVM_TUI_NC}"
                else
                    message="${NVM_TUI_YELLOW}No installed versions to uninstall.${NVM_TUI_NC}"
                fi
                ;;
            r|R)
                tput clear 2>/dev/null || true
                printf '%sLoading nvm ls-remote...%s\n' "$NVM_TUI_DIM" "$NVM_TUI_NC"
                nvm_tui_refresh_versions 1
                selected=$(nvm_tui_first_selected)
                message="${NVM_TUI_GREEN}Versions refreshed.${NVM_TUI_NC}"
                ;;
            q|Q|escape)
                nvm_tui_render "$selected" "${NVM_TUI_DIM}$(nvm_tui_back_message)${NVM_TUI_NC}"
                printf '\n'
                return 0
                ;;
        esac
    done
}

if ! nvm_tui_is_sourced; then
    run_nvm_tui
    nvm_tui_rc=$?

    if [ "$nvm_tui_rc" -eq 0 ] && nvm_tui_supports_tui && [ -f "$NVM_TUI_DIR/welcome.sh" ]; then
        # shellcheck source=/dev/null
        source "$NVM_TUI_DIR/welcome.sh"
    fi

    exit "$nvm_tui_rc"
fi
