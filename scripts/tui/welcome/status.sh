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

print_tool_row_json() {
    local i="$1"

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
        print_tool_row_json "$i"
    done

    printf ']}'
    printf '\n'
}

print_tool_row_event() {
    local i="$1"

    printf '{"kind":"tool-row","row":'
    print_tool_row_json "$i"
    printf '}\n'
}

print_tool_rows_stream() {
    (
        set -e
        load_rows 1 print_tool_row_event
        printf '{"kind":"tools-complete","includeUpdates":true}\n'
    )
}

usage() {
    printf 'Usage: %s tools [--local|--updates [--stream]]\n' "${0##*/}" >&2
}

main() {
    local kind="${1:-}" include=0

    case "$kind" in
        tools)
            if [ "${2:-}" = "--updates" ] && [ "${3:-}" = "--stream" ]; then
                print_tool_rows_stream
            else
                [ "${2:-}" = "--updates" ] && include=1
                print_tool_rows "$include"
            fi
            ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
