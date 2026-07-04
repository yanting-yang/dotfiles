#!/usr/bin/env bash

TUI_RED=$'\033[0;31m'
TUI_GREEN=$'\033[0;32m'
TUI_YELLOW=$'\033[0;33m'
TUI_CYAN=$'\033[0;36m'
TUI_BOLD=$'\033[1m'
TUI_DIM=$'\033[2m'
TUI_REV=$'\033[7m'
TUI_NC=$'\033[0m'

tui_repeat_char() {
    local char="$1" count="$2"
    local output="" i

    for ((i = 0; i < count; i++)); do
        output+="$char"
    done

    printf '%s' "$output"
}

tui_truncate() {
    local value="$1" width="$2"

    if [ "$width" -le 3 ]; then
        printf '%.*s' "$width" "$value"
    elif [ "${#value}" -gt "$width" ]; then
        printf '%s...' "${value:0:$((width - 3))}"
    else
        printf '%s' "$value"
    fi
}

tui_cols() {
    local min="${1:-60}" fallback="${2:-100}"
    local cols

    cols=$(tput cols 2>/dev/null || printf '%s' "$fallback")
    [[ "$cols" =~ ^[0-9]+$ ]] || cols="$fallback"
    [ "$cols" -ge "$min" ] || cols="$min"
    printf '%s' "$cols"
}

tui_lines() {
    local min="${1:-12}" fallback="${2:-24}"
    local lines

    lines=$(tput lines 2>/dev/null || printf '%s' "$fallback")
    [[ "$lines" =~ ^[0-9]+$ ]] || lines="$fallback"
    [ "$lines" -ge "$min" ] || lines="$min"
    printf '%s' "$lines"
}

tui_supports() {
    [ -t 0 ] \
        && [ -t 1 ] \
        && command -v tput >/dev/null 2>&1 \
        && [ "${TERM:-dumb}" != "dumb" ]
}

tui_clear() {
    tput clear 2>/dev/null || true
}

tui_read_key() {
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

tui_pause() {
    local target="${1:-screen}"

    printf '\nPress any key to return to %s.' "$target"
    tui_read_key >/dev/null 2>&1 || true
}
