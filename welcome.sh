#!/usr/bin/env bash

WELCOME_DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WELCOME_APP="$WELCOME_DOTFILES_DIR/scripts/tui/welcome/cli.mjs"
WELCOME_LIB_DIR="$WELCOME_DOTFILES_DIR/scripts/lib"
WELCOME_NODE_MODULES="$WELCOME_DOTFILES_DIR/node_modules"

# shellcheck source=scripts/lib/code.sh
source "$WELCOME_LIB_DIR/code.sh"
# shellcheck source=scripts/lib/tool_status.sh
source "$WELCOME_LIB_DIR/tool_status.sh"

welcome_is_sourced() {
    [ "${#BASH_SOURCE[@]}" -gt 1 ]
}

welcome_require_runtime() {
    local node_major

    if ! command -v node >/dev/null 2>&1; then
        printf 'Welcome requires Node >=22. Run npm install in %s after Node is available.\n' "$WELCOME_DOTFILES_DIR"
        return 1
    fi

    node_major=$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || printf '0')
    if [ "$node_major" -lt 22 ]; then
        printf 'Welcome requires Node >=22; current node is %s.\n' "$(node --version 2>/dev/null || printf unknown)"
        return 1
    fi

    if [ ! -d "$WELCOME_NODE_MODULES/ink" ] || [ ! -d "$WELCOME_NODE_MODULES/react" ]; then
        printf 'Welcome dependencies are missing. Run npm install in %s.\n' "$WELCOME_DOTFILES_DIR"
        return 1
    fi

    if [ ! -f "$WELCOME_APP" ]; then
        printf 'Welcome app is missing: %s\n' "$WELCOME_APP"
        return 1
    fi
}

welcome_action_value() {
    local key="$1" file="$2"

    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file" 2>/dev/null
}

welcome_valid_token() {
    [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]]
}

welcome_valid_nvm_version() {
    [[ "$1" =~ ^[A-Za-z0-9._/+*-]+$ ]]
}

welcome_run_installer_by_index() {
    local index="$1" installer="${INSTALLERS[$1]}"
    local code_running_status rc command_name

    command_name="${COMMANDS[$index]}"
    if [ ! -f "$installer" ]; then
        printf 'No installer found: %s\n' "$installer"
        return 1
    fi

    if [ "$command_name" = "code" ]; then
        if code_is_running; then
            printf 'code is running; skipping update.\n'
            return 0
        else
            code_running_status=$?
        fi

        if [ "$code_running_status" -eq 2 ]; then
            printf 'Could not check whether code is running; skipping update.\n'
            return 0
        fi
    fi

    printf 'Installing latest %s...\n' "$command_name"
    if bash "$installer"; then
        rc=0
    else
        rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        hash -r 2>/dev/null || true
        printf 'Installed latest %s.\n' "$command_name"
    else
        printf 'Failed to install %s (exit %s).\n' "$command_name" "$rc"
    fi

    return "$rc"
}

welcome_run_tool_installer() {
    local command_name="$1" include_updates="${2:-0}" i

    welcome_valid_token "$command_name" || {
        printf 'Invalid command name: %s\n' "$command_name"
        return 2
    }

    load_rows "$include_updates"
    for i in "${!COMMANDS[@]}"; do
        if [ "${COMMANDS[$i]}" = "$command_name" ]; then
            if row_is_actionable "$i"; then
                welcome_run_installer_by_index "$i"
                return $?
            fi
            printf '%s is not actionable right now.\n' "$command_name"
            return 0
        fi
    done

    printf 'Unknown managed command: %s\n' "$command_name"
    return 1
}

welcome_run_all_installers() {
    local include_updates="${1:-0}" i ran=0 rc=0

    load_rows "$include_updates"
    for i in "${!COMMANDS[@]}"; do
        if row_is_actionable "$i"; then
            welcome_run_installer_by_index "$i" || rc=$?
            ran=1
        fi
    done

    if [ "$ran" -eq 0 ]; then
        printf 'Nothing to install.\n'
    fi

    return "$rc"
}

welcome_load_nvm() {
    local nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"

    if ! command -v nvm >/dev/null 2>&1; then
        [ -s "$nvm_dir/nvm.sh" ] || {
            printf 'nvm is not installed. Install it with %s/scripts/install/nvm.sh\n' "$WELCOME_DOTFILES_DIR"
            return 1
        }
        # shellcheck source=/dev/null
        source "$nvm_dir/nvm.sh" --no-use
    fi

    command -v nvm >/dev/null 2>&1
}

welcome_run_nvm_action() {
    local action="$1" version="$2"

    welcome_valid_nvm_version "$version" || {
        printf 'Invalid Node version: %s\n' "$version"
        return 2
    }

    welcome_load_nvm || return 1

    case "$action" in
        nvm_use)
            printf 'Using Node %s...\n' "$version"
            nvm use "$version"
            ;;
        nvm_install_use)
            printf 'Installing Node %s...\n' "$version"
            nvm install "$version" || return $?
            printf 'Using Node %s...\n' "$version"
            nvm use "$version"
            ;;
        nvm_uninstall)
            printf 'Uninstalling Node %s...\n' "$version"
            nvm uninstall "$version"
            ;;
        *)
            printf 'Unknown nvm action: %s\n' "$action"
            return 2
            ;;
    esac
}

welcome_record_result() {
    local result_file="$1" title="$2" rc="$3" output="$4"

    {
        printf '%s\n' "$title"
        if [ -n "$output" ]; then
            printf '%s\n' "$output"
        fi
        if [ "$rc" -eq 0 ]; then
            printf 'Action completed.\n'
        else
            printf 'Action failed with exit %s.\n' "$rc"
        fi
    } >"$result_file"
}

welcome_execute_action_file() {
    local action_file="$1" result_file="$2"
    local action command_name version include_updates output rc

    action=$(welcome_action_value ACTION "$action_file")
    include_updates=$(welcome_action_value INCLUDE_UPDATES "$action_file")
    [ "$include_updates" = "1" ] || include_updates=0

    case "$action" in
        install_tool)
            command_name=$(welcome_action_value COMMAND "$action_file")
            output=$(welcome_run_tool_installer "$command_name" "$include_updates" 2>&1)
            rc=$?
            welcome_record_result "$result_file" "Tool action: $command_name" "$rc" "$output"
            return 0
            ;;
        install_all)
            output=$(welcome_run_all_installers "$include_updates" 2>&1)
            rc=$?
            welcome_record_result "$result_file" "Tool action: all" "$rc" "$output"
            return 0
            ;;
        nvm_use|nvm_install_use|nvm_uninstall)
            version=$(welcome_action_value VERSION "$action_file")
            output=$(welcome_run_nvm_action "$action" "$version" 2>&1)
            rc=$?
            welcome_record_result "$result_file" "Node action: $version" "$rc" "$output"
            return 0
            ;;
        quit|"")
            return 1
            ;;
        *)
            welcome_record_result "$result_file" "Unknown action" 2 "Unknown action: $action"
            return 0
            ;;
    esac
}

welcome_main() {
    local session_dir action_file result_file
    local view="tools" include_updates=0 nvm_remote=0
    local action next_view next_updates next_nvm_remote
    local rc=0

    welcome_require_runtime || return 0

    session_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-welcome.XXXXXX") || return 1
    action_file="$session_dir/action.env"
    result_file="$session_dir/result.txt"

    while true; do
        rm -f "$action_file"
        WELCOME_ACTION_FILE="$action_file" \
            WELCOME_RESULT_FILE="$result_file" \
            WELCOME_INITIAL_VIEW="$view" \
            WELCOME_INCLUDE_UPDATES="$include_updates" \
            WELCOME_NVM_REMOTE="$nvm_remote" \
            WELCOME_DOTFILES_DIR="$WELCOME_DOTFILES_DIR" \
            node "$WELCOME_APP" || rc=$?

        [ -f "$action_file" ] || break

        action=$(welcome_action_value ACTION "$action_file")
        [ "$action" != "quit" ] || break

        next_view=$(welcome_action_value VIEW "$action_file")
        next_updates=$(welcome_action_value INCLUDE_UPDATES "$action_file")
        next_nvm_remote=$(welcome_action_value NVM_REMOTE "$action_file")

        welcome_execute_action_file "$action_file" "$result_file" || break

        case "$action" in
            install_tool|install_all)
                view="tools"
                include_updates=0
                nvm_remote=0
                ;;
            nvm_use|nvm_install_use|nvm_uninstall)
                view="nvm"
                include_updates=0
                nvm_remote=0
                ;;
            *)
                [ "$next_view" = "nvm" ] && view="nvm" || view="tools"
                [ "$next_updates" = "1" ] && include_updates=1 || include_updates=0
                [ "$next_nvm_remote" = "1" ] && nvm_remote=1 || nvm_remote=0
                ;;
        esac
    done

    rm -rf "$session_dir"
    return "$rc"
}

if ! welcome_is_sourced; then
    welcome_rc=0
    if [ "${WELCOME_SH_NO_AUTO_RUN:-0}" != "1" ]; then
        welcome_main "$@" || welcome_rc=$?
    fi
    exit "$welcome_rc"
elif [ "${WELCOME_SH_NO_AUTO_RUN:-0}" != "1" ]; then
    welcome_main "$@"
    return $?
fi
