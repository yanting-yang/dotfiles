#!/usr/bin/env bash

set -u

STATUS_DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

# shellcheck source=scripts/lib/tool_status.sh
source "$STATUS_DOTFILES_DIR/scripts/lib/tool_status.sh"

json_escape() {
    local value="${1-}"

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

json_string() {
    printf '"'
    json_escape "$1"
    printf '"'
}

json_bool() {
    if [ "${1:-0}" = "1" ]; then
        printf 'true'
    else
        printf 'false'
    fi
}

print_tool_rows() {
    local include_updates="$1" i

    load_rows "$include_updates"

    printf '{'
    printf '"kind":"tools",'
    printf '"includeUpdates":'
    json_bool "$include_updates"
    printf ',"rows":['

    for i in "${!COMMANDS[@]}"; do
        [ "$i" -eq 0 ] || printf ','
        printf '{'
        printf '"id":'
        json_string "${COMMANDS[$i]}"
        printf ',"command":'
        json_string "${COMMANDS[$i]}"
        printf ',"path":'
        json_string "${PATHS[$i]}"
        printf ',"current":'
        json_string "${CURRENTS[$i]}"
        printf ',"latest":'
        json_string "${LATESTS[$i]}"
        printf ',"status":'
        json_string "${STATUSES[$i]}"
        printf ',"installer":'
        json_string "${INSTALLERS[$i]}"
        printf ',"actionable":'
        if row_is_actionable "$i"; then
            printf 'true'
        else
            printf 'false'
        fi
        printf ',"uninstallable":'
        if row_is_uninstallable "$i"; then
            printf 'true'
        else
            printf 'false'
        fi
        printf '}'
    done

    printf ']}'
    printf '\n'
}

print_nvm_rows() {
    local include_remote="$1" i
    local nvm_tui="$STATUS_DOTFILES_DIR/scripts/tui/nvm.sh"

    if [ ! -f "$nvm_tui" ]; then
        printf '{"kind":"nvm","ok":false,"error":'
        json_string "No nvm TUI found: $nvm_tui"
        printf ',"remoteLoaded":false,"current":"none","rows":[]}\n'
        return 0
    fi

    # shellcheck source=scripts/tui/nvm.sh
    source "$nvm_tui"

    if ! nvm_tui_load_nvm; then
        printf '{"kind":"nvm","ok":false,"error":'
        json_string "nvm is not installed"
        printf ',"remoteLoaded":false,"current":"none","rows":[]}\n'
        return 0
    fi

    nvm_tui_clear_remote_versions
    nvm_tui_refresh_versions "$include_remote"

    printf '{'
    printf '"kind":"nvm","ok":true,'
    printf '"error":'
    json_string "$NVM_TUI_REMOTE_ERROR"
    printf ',"remoteLoaded":'
    json_bool "$NVM_TUI_REMOTE_LOADED"
    printf ',"current":'
    json_string "$NVM_TUI_CURRENT"
    printf ',"rows":['

    for i in "${!NVM_TUI_VERSIONS[@]}"; do
        [ "$i" -eq 0 ] || printf ','
        printf '{'
        printf '"version":'
        json_string "${NVM_TUI_VERSIONS[$i]}"
        printf ',"status":'
        json_string "${NVM_TUI_STATUSES[$i]}"
        printf ',"lts":'
        json_string "${NVM_TUI_LTS[$i]}"
        printf ',"path":'
        json_string "$(nvm_tui_version_path "${NVM_TUI_VERSIONS[$i]}" "${NVM_TUI_STATUSES[$i]}")"
        printf ',"current":'
        if [ "${NVM_TUI_VERSIONS[$i]}" = "$NVM_TUI_CURRENT" ]; then
            printf 'true'
        else
            printf 'false'
        fi
        printf '}'
    done

    printf ']}'
    printf '\n'
}

usage() {
    printf 'Usage: %s tools [--updates] | nvm [--remote]\n' "${0##*/}" >&2
}

main() {
    local kind="${1:-}" include=0

    case "$kind" in
        tools)
            [ "${2:-}" = "--updates" ] && include=1
            print_tool_rows "$include"
            ;;
        nvm)
            [ "${2:-}" = "--remote" ] && include=1
            print_nvm_rows "$include"
            ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
