#!/usr/bin/env bash

code_is_running() {
    local uid processes

    uid=$(id -u 2>/dev/null) || return 2
    command -v ps >/dev/null 2>&1 || return 2
    command -v awk >/dev/null 2>&1 || return 2

    processes=$(ps -u "$uid" -o comm= -o args= 2>/dev/null) || return 2
    awk -v home="$HOME" '
        function ends_with(value, suffix) {
            return substr(value, length(value) - length(suffix) + 1) == suffix
        }

        function has_home_code(value, path) {
            path = home "/code"
            return index(value, path " ") \
                || index(value, path "\t") \
                || ends_with(value, path)
        }

        $1 == "code" || $1 == "code-insiders" {
            found = 1
        }

        index($0, home "/.vscode/") \
            || index($0, home "/.vscode-server/") \
            || has_home_code($0) {
            found = 1
        }

        END {
            exit found ? 0 : 1
        }
    ' <<< "$processes"
}
