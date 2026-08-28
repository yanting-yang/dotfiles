#!/usr/bin/env bash

WELCOME_DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WELCOME_APP="$WELCOME_DOTFILES_DIR/scripts/tui/welcome/cli.mjs"
WELCOME_LIB_DIR="$WELCOME_DOTFILES_DIR/scripts/lib"
WELCOME_NODE_MODULES="$WELCOME_DOTFILES_DIR/node_modules"
WELCOME_LOCAL_PREFIX="${LOCAL_PREFIX:-$HOME/.local}"
WELCOME_LOCAL_BIN_DIR="$WELCOME_LOCAL_PREFIX/bin"
WELCOME_LOCAL_STOW_DIR="$WELCOME_LOCAL_PREFIX/stow"

# shellcheck source=scripts/lib/code.sh
source "$WELCOME_LIB_DIR/code.sh"
# shellcheck source=scripts/lib/tool_status.sh
source "$WELCOME_LIB_DIR/tool_status.sh"
# shellcheck source=scripts/lib/node.sh
source "$WELCOME_LIB_DIR/node.sh"

welcome_is_sourced() {
    [ "${BASH_SOURCE[0]}" != "$0" ]
}

welcome_require_runtime() {
    local node_major required_node_major

    if ! required_node_major=$(node_major_from_file "$WELCOME_DOTFILES_DIR/.nvmrc"); then
        printf 'Welcome requires one numeric Node major in %s.\n' "$WELCOME_DOTFILES_DIR/.nvmrc"
        return 1
    fi

    welcome_load_nvm || return 1
    if ! nvm use --silent "$required_node_major"; then
        printf 'Welcome requires Node %s.x through nvm. Install it with `nvm install %s`.\n' \
            "$required_node_major" "$required_node_major"
        return 1
    fi
    hash -r 2>/dev/null || true

    if ! command -v node >/dev/null 2>&1; then
        printf 'Welcome requires Node %s.x. Run npm install in %s after Node is available.\n' "$required_node_major" "$WELCOME_DOTFILES_DIR"
        return 1
    fi

    node_major=$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || printf '0')
    if [ "$node_major" -ne "$required_node_major" ]; then
        printf 'Welcome requires Node %s.x; current node is %s.\n' "$required_node_major" "$(node --version 2>/dev/null || printf unknown)"
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

welcome_valid_node_version() {
    [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

welcome_activate_texlive() {
    local texlive_root="${TEXLIVE_ROOT:-$HOME/texlive}" texlive_bin

    for texlive_bin in "$texlive_root"/current/bin/*; do
        [ -x "$texlive_bin/latex" ] || continue
        case ":$PATH:" in
            *":$texlive_bin:"*) ;;
            *) PATH="$texlive_bin:$PATH" ;;
        esac
        export PATH
        hash -r 2>/dev/null || true
        return 0
    done

    return 1
}

welcome_run_installer_by_index() {
    local index="$1" installer="${INSTALLERS[$1]}"
    local code_running_status rc command_name

    command_name="${COMMANDS[$index]}"
    if [ "$command_name" = "node" ]; then
        welcome_update_node "${CURRENTS[$index]}" "${LATESTS[$index]}"
        return $?
    fi

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
    if [ "$command_name" = "latex" ]; then
        if TEXLIVE_ROOT="${TEXLIVE_ROOT:-$HOME/texlive}" \
            TEXLIVE_SCHEME="${TEXLIVE_SCHEME:-scheme-full}" \
            bash "$installer"; then
            rc=0
        else
            rc=$?
        fi
    elif bash "$installer"; then
        rc=0
    else
        rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        if [ "$command_name" = "latex" ] && ! welcome_activate_texlive; then
            printf 'TeX Live was installed, but its binary directory could not be added to PATH.\n'
        fi
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

welcome_remove_managed_dir() {
    local target="$1"

    case "$target" in
        ""|"/"|"$HOME"|"$WELCOME_DOTFILES_DIR")
            printf 'Refusing to remove unsafe directory: %s\n' "$target"
            return 1
            ;;
    esac

    rm -rf -- "$target"
}

welcome_uninstall_code() {
    local code_running_status=0

    if code_is_running; then
        printf 'code is running; skipping uninstall.\n'
        return 0
    else
        code_running_status=$?
    fi

    if [ "$code_running_status" -eq 2 ]; then
        printf 'Could not check whether code is running; skipping uninstall.\n'
        return 0
    fi

    if [ ! -e "$HOME/code" ] && [ ! -L "$HOME/code" ]; then
        printf 'code is not installed at %s.\n' "$HOME/code"
        return 0
    fi

    rm -f -- "$HOME/code"
    hash -r 2>/dev/null || true
    printf 'Uninstalled code from %s.\n' "$HOME/code"
}

welcome_uninstall_stow_package() {
    local package="$1" package_dir="$WELCOME_LOCAL_STOW_DIR/$1"

    if [ ! -d "$package_dir" ]; then
        printf '%s is not installed as a managed stow package.\n' "$package"
        return 1
    fi

    if ! command -v stow >/dev/null 2>&1; then
        printf 'stow is required to uninstall managed package %s.\n' "$package"
        return 1
    fi

    stow -d "$WELCOME_LOCAL_STOW_DIR" -D "$package" || return $?
    welcome_remove_managed_dir "$package_dir" || return $?
    hash -r 2>/dev/null || true
    printf 'Uninstalled %s from %s.\n' "$package" "$package_dir"
}

welcome_uninstall_nvm() {
    local nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"

    if [ ! -d "$nvm_dir" ]; then
        printf 'nvm is not installed at %s.\n' "$nvm_dir"
        return 0
    fi

    welcome_remove_managed_dir "$nvm_dir" || return $?
    hash -r 2>/dev/null || true
    printf 'Uninstalled nvm from %s.\n' "$nvm_dir"
}

welcome_uninstall_stow() {
    local removed=0

    if [ -e "$WELCOME_LOCAL_BIN_DIR/stow" ] || [ -L "$WELCOME_LOCAL_BIN_DIR/stow" ]; then
        rm -f -- "$WELCOME_LOCAL_BIN_DIR/stow"
        removed=1
    fi
    if [ -e "$WELCOME_LOCAL_BIN_DIR/chkstow" ] || [ -L "$WELCOME_LOCAL_BIN_DIR/chkstow" ]; then
        rm -f -- "$WELCOME_LOCAL_BIN_DIR/chkstow"
        removed=1
    fi

    rm -f -- "$WELCOME_LOCAL_PREFIX/share/perl5/Stow.pm"
    welcome_remove_managed_dir "$WELCOME_LOCAL_PREFIX/share/perl5/Stow" 2>/dev/null || true
    rm -f -- "$WELCOME_LOCAL_PREFIX/share/man/man8/stow.8"
    rm -f -- "$WELCOME_LOCAL_PREFIX/share/man/man8/chkstow.8"
    rm -f -- "$WELCOME_LOCAL_PREFIX/share/info/stow.info"

    hash -r 2>/dev/null || true
    if [ "$removed" -eq 1 ]; then
        printf 'Uninstalled stow from %s.\n' "$WELCOME_LOCAL_PREFIX"
    else
        printf 'stow is not installed at %s.\n' "$WELCOME_LOCAL_BIN_DIR"
    fi
}

welcome_uninstall_tmux() {
    if [ ! -e "$WELCOME_LOCAL_BIN_DIR/tmux" ] && [ ! -L "$WELCOME_LOCAL_BIN_DIR/tmux" ]; then
        printf 'tmux is not installed at %s.\n' "$WELCOME_LOCAL_BIN_DIR/tmux"
        return 0
    fi

    rm -f -- "$WELCOME_LOCAL_BIN_DIR/tmux"
    hash -r 2>/dev/null || true
    printf 'Uninstalled tmux from %s.\n' "$WELCOME_LOCAL_BIN_DIR/tmux"
}

welcome_uninstall_maple() {
    local font_dir
    font_dir=$(maple_font_dir)

    if [ ! -d "$font_dir" ]; then
        printf 'maple font is not installed at %s.\n' "$font_dir"
        return 0
    fi

    welcome_remove_managed_dir "$font_dir" || return $?
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 || true
    fi
    printf 'Uninstalled maple font from %s.\n' "$font_dir"
}

welcome_uninstall_tool_by_command() {
    case "$1" in
        code)
            welcome_uninstall_code
            ;;
        gh|nvim|kitty)
            welcome_uninstall_stow_package "$1"
            ;;
        nvm)
            welcome_uninstall_nvm
            ;;
        stow)
            welcome_uninstall_stow
            ;;
        tmux)
            welcome_uninstall_tmux
            ;;
        maple)
            welcome_uninstall_maple
            ;;
        *)
            printf 'No uninstaller is registered for %s.\n' "$1"
            return 1
            ;;
    esac
}

welcome_run_tool_uninstaller() {
    local command_name="$1" i

    welcome_valid_token "$command_name" || {
        printf 'Invalid command name: %s\n' "$command_name"
        return 2
    }

    load_rows 0
    for i in "${!COMMANDS[@]}"; do
        if [ "${COMMANDS[$i]}" = "$command_name" ]; then
            if row_is_uninstallable "$i"; then
                welcome_uninstall_tool_by_command "$command_name"
                return $?
            fi
            printf '%s has no managed uninstall action right now.\n' "$command_name"
            return 0
        fi
    done

    printf 'Unknown managed command: %s\n' "$command_name"
    return 1
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

welcome_update_node() {
    local current="${1#v}" latest="${2#v}"
    local major target installed installed_output installed_versions default_version current_after rc cleanup_rc=0

    welcome_valid_node_version "$current" || {
        printf 'Invalid current Node version: %s\n' "$1"
        return 2
    }
    welcome_valid_node_version "$latest" || {
        printf 'Invalid latest Node version: %s\n' "$2"
        return 2
    }

    major="${current%%.*}"
    if [ "${latest%%.*}" != "$major" ]; then
        printf 'Refusing to change Node major from %s to %s.\n' "$major" "${latest%%.*}"
        return 2
    fi
    if [ "$current" = "$latest" ]; then
        printf 'Node %s is already current.\n' "$current"
        return 0
    fi
    if ! node_version_is_newer "$current" "$latest"; then
        printf 'Refusing to downgrade Node from %s to %s.\n' "$current" "$latest"
        return 2
    fi

    welcome_load_nvm || return 1
    target="v$latest"

    printf 'Installing Node %s with nvm...\n' "$target"
    if nvm install "$target"; then
        rc=0
    else
        rc=$?
        printf 'Failed to install Node %s.\n' "$target"
        return "$rc"
    fi

    printf 'Using Node %s...\n' "$target"
    if nvm use "$target"; then
        rc=0
    else
        rc=$?
        printf 'Failed to activate Node %s; older versions were kept.\n' "$target"
        return "$rc"
    fi
    hash -r 2>/dev/null || true

    current_after=$(nvm current 2>/dev/null) || current_after=""
    if [ "$current_after" != "$target" ] || [ "$(node --version 2>/dev/null)" != "$target" ]; then
        printf 'Node %s could not be verified; older versions were kept.\n' "$target"
        return 1
    fi

    default_version=$(nvm version default 2>/dev/null || true)
    if [[ "$default_version" =~ ^v?${major}\.[0-9]+\.[0-9]+$ ]] \
        && [ "${default_version#v}" != "$latest" ]; then
        printf 'Updating the default Node alias to major %s...\n' "$major"
        if ! nvm alias default "$major"; then
            printf 'Could not preserve the default alias; older versions were kept.\n'
            return 1
        fi
    fi

    if ! installed_output=$(nvm ls "$major" --no-colors 2>/dev/null); then
        printf 'Could not list installed Node %s.x versions; older versions were kept.\n' "$major"
        return 1
    fi
    installed_versions=$(printf '%s\n' "$installed_output" \
        | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -Vu) || true
    if ! grep -Fxq "$target" <<<"$installed_versions"; then
        printf 'Could not verify Node %s in the installed-version list; older versions were kept.\n' "$target"
        return 1
    fi

    while IFS= read -r installed; do
        [ -n "$installed" ] || continue
        [[ "$installed" =~ ^v${major}\.[0-9]+\.[0-9]+$ ]] || continue
        [ "$installed" != "$target" ] || continue
        node_version_is_newer "${installed#v}" "$latest" || continue

        current_after=$(nvm current 2>/dev/null) || current_after=""
        if [ "$current_after" != "$target" ]; then
            printf 'Active Node changed unexpectedly; remaining older versions were kept.\n'
            return 1
        fi

        printf 'Uninstalling superseded Node %s...\n' "$installed"
        nvm uninstall "$installed" || cleanup_rc=1
    done <<<"$installed_versions"

    if [ "$cleanup_rc" -ne 0 ]; then
        printf 'Node %s is active, but at least one older %s.x version could not be removed.\n' "$target" "$major"
        return "$cleanup_rc"
    fi

    printf 'Updated Node to %s and removed older %s.x installations.\n' "$target" "$major"
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
    local action command_name include_updates output action_output_file rc
    local action_output_fd action_output_pid tee_rc

    action=$(welcome_action_value ACTION "$action_file")
    include_updates=$(welcome_action_value INCLUDE_UPDATES "$action_file")
    [ "$include_updates" = "1" ] || include_updates=0

    case "$action" in
        install_tool)
            command_name=$(welcome_action_value COMMAND "$action_file")
            if [ "$command_name" = "node" ]; then
                action_output_file="${result_file}.action-output"
                if welcome_run_tool_installer "$command_name" "$include_updates" >"$action_output_file" 2>&1; then
                    rc=0
                else
                    rc=$?
                fi
                output=""
                if [ -s "$action_output_file" ]; then
                    IFS= read -r -d '' output <"$action_output_file" || true
                fi
                rm -f -- "$action_output_file"
            elif [ "$command_name" = "latex" ]; then
                # A full TeX Live install can take hours. Keep its progress on
                # the terminal and retain a bounded failure excerpt for Ink.
                action_output_file="${result_file}.action-output"
                exec {action_output_fd}> >(tee "$action_output_file")
                action_output_pid=$!
                if welcome_run_tool_installer "$command_name" "$include_updates" \
                    >&"$action_output_fd" 2>&1; then
                    rc=0
                else
                    rc=$?
                fi
                exec {action_output_fd}>&-
                if wait "$action_output_pid" 2>/dev/null; then
                    tee_rc=0
                else
                    tee_rc=$?
                fi
                [ "$rc" -ne 0 ] || rc=$tee_rc

                if [ "$rc" -eq 0 ]; then
                    output="Installer output was shown in the terminal."
                elif [ -s "$action_output_file" ]; then
                    output=$(tail -c 4096 "$action_output_file")
                    output=${output//$'\r'/$'\n'}
                    output=$(printf '%s\n' "$output" | tail -n 8)
                else
                    output="The installer failed without producing output."
                fi
                rm -f -- "$action_output_file"
            else
                output=$(welcome_run_tool_installer "$command_name" "$include_updates" 2>&1)
                rc=$?
            fi
            welcome_record_result "$result_file" "Tool action: $command_name" "$rc" "$output"
            return 0
            ;;
        uninstall_tool)
            command_name=$(welcome_action_value COMMAND "$action_file")
            output=$(welcome_run_tool_uninstaller "$command_name" 2>&1)
            rc=$?
            welcome_record_result "$result_file" "Tool uninstall: $command_name" "$rc" "$output"
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
    local session_dir action_file result_file update_cache_dir WELCOME_UPDATE_CACHE_DIR
    local include_updates=0
    local action next_updates
    local rc=0

    welcome_require_runtime || return 0

    session_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-welcome.XXXXXX") || return 1
    action_file="$session_dir/action.env"
    result_file="$session_dir/result.txt"
    update_cache_dir="$session_dir/update-cache"
    WELCOME_UPDATE_CACHE_DIR="$update_cache_dir"

    while true; do
        rm -f "$action_file"
        WELCOME_ACTION_FILE="$action_file" \
            WELCOME_RESULT_FILE="$result_file" \
            WELCOME_INCLUDE_UPDATES="$include_updates" \
            WELCOME_DOTFILES_DIR="$WELCOME_DOTFILES_DIR" \
            WELCOME_UPDATE_CACHE_DIR="$update_cache_dir" \
            node "$WELCOME_APP" || rc=$?

        [ -f "$action_file" ] || break

        action=$(welcome_action_value ACTION "$action_file")
        [ "$action" != "quit" ] || break

        next_updates=$(welcome_action_value INCLUDE_UPDATES "$action_file")

        welcome_execute_action_file "$action_file" "$result_file" || break
        [ "$next_updates" = "1" ] && include_updates=1 || include_updates=0
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
