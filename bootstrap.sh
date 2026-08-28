#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
YES=0
BACKUP_DIR=""
SHELL_LOCAL_CONFIG="$HOME/local.sh"
GIT_CONFIG_DIR="$HOME/.config/git"
GIT_CONFIG_PARENT="$HOME/.config"
GIT_CONFIG_SOURCE="$DOTFILES_DIR/.config/git/config"
GIT_CONFIG_TARGET="$GIT_CONFIG_DIR/config"
GIT_LOCAL_CONFIG="$GIT_CONFIG_DIR/local"
LEGACY_GIT_CONFIG="$HOME/.gitconfig"
SSH_SUBMODULE_PATH=".ssh"
SSH_CONFIG_SOURCE="$DOTFILES_DIR/$SSH_SUBMODULE_PATH/config"
LOCAL_BIN_DIR="${LOCAL_PREFIX:-$HOME/.local}/bin"
GH_BIN=""
SSH_SUBMODULE_GIT_ARGS=()
CREATE_SHELL_LOCAL_CONFIG=0
CREATE_GIT_LOCAL_CONFIG=0
SELECTED_TIMEZONE=""
SELECTED_GIT_NAME=""
SELECTED_GIT_EMAIL=""

# shellcheck source=scripts/lib/node.sh
source "$DOTFILES_DIR/scripts/lib/node.sh"

SOURCES=(
    "$DOTFILES_DIR/.bash_profile"
    "$DOTFILES_DIR/.bashrc"
    "$SSH_CONFIG_SOURCE"
    "$DOTFILES_DIR/.config/nvim"
    "$DOTFILES_DIR/.config/kitty"
    "$DOTFILES_DIR/.config/tmux"
)

TARGETS=(
    "$HOME/.bash_profile"
    "$HOME/.bashrc"
    "$HOME/.ssh/config"
    "$HOME/.config/nvim"
    "$HOME/.config/kitty"
    "$HOME/.config/tmux"
)

BACKUP_ONLY_TARGETS=(
    "$HOME/.profile"
    "$HOME/.lesshst"
    "$HOME/.bash_history"
    "$HOME/.bash_logout"
)

usage() {
    printf 'Usage: %s [--dry-run] [--yes]\n' "${0##*/}"
    printf '\n'
    printf '  --dry-run  show planned links without changing files\n'
    printf '  --yes      skip apply confirmation; missing local settings may still prompt\n'
    printf '\n'
    printf 'Environment:\n'
    printf '  BOOTSTRAP_TZ          timezone for unattended local.sh creation\n'
    printf '  BOOTSTRAP_GIT_NAME    Git user name for unattended identity creation\n'
    printf '  BOOTSTRAP_GIT_EMAIL   Git user email for unattended identity creation\n'
    printf '  GH_TOKEN              GitHub token used instead of gh for the private submodule\n'
    printf '  GITHUB_TOKEN          GitHub token used when GH_TOKEN is unset\n'
    printf '  BOOTSTRAP_SKIP_GITHUB_AUTH  clone the private submodule with your own Git credentials\n'
    printf '  BOOTSTRAP_SKIP_SUBMODULES   skip all git submodule initialization\n'
    printf '  WELCOME_NODE_VERSION  Node major/version to install with nvm when needed [%s]\n' "$WELCOME_NODE_VERSION"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

NODE_VERSION_FILE="$DOTFILES_DIR/.nvmrc"
if ! WELCOME_NODE_MAJOR=$(node_major_from_file "$NODE_VERSION_FILE"); then
    die "invalid Node version file: $NODE_VERSION_FILE (expected one numeric major)"
fi
WELCOME_NODE_VERSION="${WELCOME_NODE_VERSION:-$WELCOME_NODE_MAJOR}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --yes|-y)
            YES=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done

display_path() {
    local path="$1"

    case "$path" in
        "$HOME")
            printf '~'
            ;;
        "$HOME"/*)
            printf '~/%s' "${path#"$HOME"/}"
            ;;
        *)
            printf '%s' "$path"
            ;;
    esac
}

target_is_current() {
    local source="$1" target="$2"
    local link resolved_source resolved_target

    [ -L "$target" ] || return 1
    link=$(readlink "$target" 2>/dev/null) || return 1
    [ "$link" = "$source" ] && return 0

    resolved_source=$(readlink -f "$source" 2>/dev/null || printf '%s' "$source")
    resolved_target=$(readlink -f "$target" 2>/dev/null || printf '%s' "$link")
    [ "$resolved_source" = "$resolved_target" ]
}

target_status() {
    local source="$1" target="$2"

    if target_is_current "$source" "$target"; then
        printf 'ok'
    elif [ -e "$target" ] || [ -L "$target" ]; then
        printf 'replace'
    else
        printf 'create'
    fi
}

shell_local_config_exists() {
    [ -f "$SHELL_LOCAL_CONFIG" ] || [ -L "$SHELL_LOCAL_CONFIG" ]
}

validate_shell_local_config_target() {
    if [ -e "$SHELL_LOCAL_CONFIG" ] && ! shell_local_config_exists; then
        die "$SHELL_LOCAL_CONFIG exists but is not a regular file or symlink"
    fi
}

value_is_nonempty_single_line() {
    [ -n "$1" ] && [[ "$1" != *$'\n'* ]] && [[ "$1" != *$'\r'* ]]
}

installed_timezone_is_valid() {
    local timezone="$1" zoneinfo_dir="${TZDIR:-/usr/share/zoneinfo}"

    value_is_nonempty_single_line "$timezone" || return 1
    [[ "$timezone" =~ ^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*$ ]] || return 1
    case "/$timezone/" in
        */./*|*/../*) return 1 ;;
    esac
    [ -f "$zoneinfo_dir/$timezone" ] && [ -r "$zoneinfo_dir/$timezone" ]
}

validate_shell_local_configuration_request() {
    validate_shell_local_config_target
    if ! shell_local_config_exists && [ -n "${BOOTSTRAP_TZ:-}" ]; then
        installed_timezone_is_valid "$BOOTSTRAP_TZ" \
            || die "invalid BOOTSTRAP_TZ: expected an installed timezone such as America/Vancouver"
    fi
}

git_local_config_exists() {
    [ -f "$GIT_LOCAL_CONFIG" ] || [ -L "$GIT_LOCAL_CONFIG" ]
}

git_local_path_is_present() {
    [ -e "$GIT_LOCAL_CONFIG" ] || [ -L "$GIT_LOCAL_CONFIG" ]
}

git_config_directory_is_local() {
    [ -d "$GIT_CONFIG_DIR" ] && [ ! -L "$GIT_CONFIG_DIR" ]
}

git_config_directory_requires_replacement() {
    [ -L "$GIT_CONFIG_DIR" ] \
        || { [ -e "$GIT_CONFIG_DIR" ] && [ ! -d "$GIT_CONFIG_DIR" ]; }
}

git_config_directory_resolves_inside_dotfiles() {
    local resolved_directory resolved_dotfiles

    resolved_directory=$(readlink -f "$GIT_CONFIG_DIR" 2>/dev/null) || return 1
    resolved_dotfiles=$(readlink -f "$DOTFILES_DIR" 2>/dev/null) || return 1
    case "$resolved_directory" in
        "$resolved_dotfiles"|"$resolved_dotfiles"/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

validate_git_configuration_layout() {
    if { [ -e "$GIT_CONFIG_PARENT" ] || [ -L "$GIT_CONFIG_PARENT" ]; } \
        && [ ! -d "$GIT_CONFIG_PARENT" ]; then
        die "$(display_path "$GIT_CONFIG_PARENT") exists but is not a directory"
    fi
    if [ ! -L "$GIT_CONFIG_DIR" ] && git_config_directory_resolves_inside_dotfiles; then
        die "$(display_path "$GIT_CONFIG_DIR") resolves inside the public dotfiles checkout through a linked ancestor"
    fi
    if [ -L "$GIT_CONFIG_DIR" ] && git_local_path_is_present; then
        die "$(display_path "$GIT_LOCAL_CONFIG") is inside a linked Git config directory; move it aside before running bootstrap"
    fi
    if git_config_directory_is_local \
        && git_local_path_is_present \
        && ! git_local_config_exists; then
        die "$(display_path "$GIT_LOCAL_CONFIG") exists but is not a regular file or symlink"
    fi
}

git_identity_is_usable() {
    local identity pattern='^.+ <.+> [0-9]+ [+-][0-9]{4}$'

    identity=$(env -u EMAIL -u GIT_AUTHOR_DATE -u GIT_AUTHOR_EMAIL -u GIT_AUTHOR_NAME \
        -u GIT_DIR -u GIT_WORK_TREE \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_NOSYSTEM=1 \
        git -c "user.name=$1" -c "user.email=$2" -C "$HOME" \
        var GIT_AUTHOR_IDENT 2>/dev/null) \
        || return 1
    [[ "$identity" =~ $pattern ]]
}

validate_git_identity_values() {
    value_is_nonempty_single_line "$1" \
        && value_is_nonempty_single_line "$2" \
        && git_identity_is_usable "$1" "$2"
}

legacy_git_config_has_identity() {
    [ -f "$LEGACY_GIT_CONFIG" ] || [ -L "$LEGACY_GIT_CONFIG" ] || return 1
    git config --file "$LEGACY_GIT_CONFIG" --includes --get user.name >/dev/null 2>&1 \
        || git config --file "$LEGACY_GIT_CONFIG" --includes --get user.email >/dev/null 2>&1
}

validate_git_identity_request() {
    validate_git_configuration_layout
    if legacy_git_config_has_identity; then
        die "$(display_path "$LEGACY_GIT_CONFIG") defines a Git identity that would override $(display_path "$GIT_LOCAL_CONFIG"); remove its [user] settings before running bootstrap"
    fi
    git_local_config_exists && return 0

    command -v git >/dev/null 2>&1 \
        || die "git is required to create $GIT_LOCAL_CONFIG"

    if [ -n "${BOOTSTRAP_GIT_NAME:-}" ] || [ -n "${BOOTSTRAP_GIT_EMAIL:-}" ]; then
        [ -n "${BOOTSTRAP_GIT_NAME:-}" ] && [ -n "${BOOTSTRAP_GIT_EMAIL:-}" ] \
            || die "set both BOOTSTRAP_GIT_NAME and BOOTSTRAP_GIT_EMAIL"
        validate_git_identity_values "$BOOTSTRAP_GIT_NAME" "$BOOTSTRAP_GIT_EMAIL" \
            || die "BOOTSTRAP_GIT_NAME and BOOTSTRAP_GIT_EMAIL must be non-empty single-line values with Git-usable characters"
    fi
}

select_timezone() {
    local timezone

    if [ -n "${BOOTSTRAP_TZ:-}" ]; then
        installed_timezone_is_valid "$BOOTSTRAP_TZ" \
            || die "invalid BOOTSTRAP_TZ: expected an installed timezone such as America/Vancouver"
        printf '%s' "$BOOTSTRAP_TZ"
        return 0
    fi

    [ -t 0 ] \
        || die "cannot create ~/local.sh non-interactively; set BOOTSTRAP_TZ"
    command -v tzselect >/dev/null 2>&1 \
        || die "tzselect is required to create ~/local.sh"
    timezone=$(command tzselect) \
        || die "timezone selection failed; ~/local.sh was not created"
    value_is_nonempty_single_line "$timezone" \
        || die "tzselect returned an invalid timezone"
    printf '%s' "$timezone"
}

select_git_identity() {
    if [ -n "${BOOTSTRAP_GIT_NAME:-}" ] || [ -n "${BOOTSTRAP_GIT_EMAIL:-}" ]; then
        SELECTED_GIT_NAME="$BOOTSTRAP_GIT_NAME"
        SELECTED_GIT_EMAIL="$BOOTSTRAP_GIT_EMAIL"
        return 0
    fi

    [ -t 0 ] \
        || die "cannot create ~/.config/git/local non-interactively; set BOOTSTRAP_GIT_NAME and BOOTSTRAP_GIT_EMAIL"
    printf 'Git user name: ' >&2
    IFS= read -r SELECTED_GIT_NAME \
        || die "Git user name input ended; ~/.config/git/local was not created"
    printf 'Git user email: ' >&2
    IFS= read -r SELECTED_GIT_EMAIL \
        || die "Git user email input ended; ~/.config/git/local was not created"
    validate_git_identity_values "$SELECTED_GIT_NAME" "$SELECTED_GIT_EMAIL" \
        || die "Git user name and email must be non-empty single-line values with Git-usable characters"
}

collect_local_settings() {
    if ! shell_local_config_exists; then
        if ! SELECTED_TIMEZONE=$(select_timezone); then
            return 1
        fi
        CREATE_SHELL_LOCAL_CONFIG=1
    fi
    if ! git_local_config_exists; then
        select_git_identity
        CREATE_GIT_LOCAL_CONFIG=1
    fi
}

publish_shell_local_config() (
    local temporary="" timezone="$1"

    trap '[ -z "$temporary" ] || rm -f -- "$temporary"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    temporary=$(mktemp "$HOME/.local.sh.XXXXXX") \
        || die "could not create a temporary local configuration"
    printf '# Generated by bootstrap.sh for machine-local settings.\nexport TZ=%q\n' \
        "$timezone" >"$temporary" \
        || die "could not write the local configuration"
    chmod 600 "$temporary" \
        || die "could not secure the local configuration"

    if shell_local_config_exists; then
        printf '  keep    %s (created concurrently)\n' "$(display_path "$SHELL_LOCAL_CONFIG")"
        return 0
    fi
    if ln -T -- "$temporary" "$SHELL_LOCAL_CONFIG" 2>/dev/null; then
        printf '  created %s with TZ=%s\n' "$(display_path "$SHELL_LOCAL_CONFIG")" "$timezone"
        return 0
    fi

    if shell_local_config_exists; then
        printf '  keep    %s (created concurrently)\n' "$(display_path "$SHELL_LOCAL_CONFIG")"
        return 0
    fi
    validate_shell_local_config_target
    die "could not create $SHELL_LOCAL_CONFIG"
)

validate_git_config_directory_ready() {
    git_config_directory_is_local \
        || die "$GIT_CONFIG_DIR must be a real directory before creating Git identity"
}

publish_git_local_config() (
    local email="$2" lock_file="" name="$1" stored_email stored_name temporary=""

    umask 077
    trap '[ -z "$lock_file" ] || rm -f -- "$lock_file" 2>/dev/null || true; [ -z "$temporary" ] || rm -f -- "$temporary" 2>/dev/null || true' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    validate_git_config_directory_ready
    temporary=$(mktemp "$GIT_CONFIG_DIR/.local.XXXXXX") \
        || die "could not create a temporary Git identity configuration"
    lock_file="$temporary.lock"
    printf '# Generated by bootstrap.sh for machine-local Git identity.\n' >"$temporary" \
        || die "could not write the Git identity configuration"
    git config --file "$temporary" user.name "$name" \
        || die "could not write the Git user name"
    git config --file "$temporary" user.email "$email" \
        || die "could not write the Git user email"
    chmod 600 "$temporary" \
        || die "could not secure the Git identity configuration"
    stored_name=$(git config --file "$temporary" --get user.name) \
        || die "could not verify the Git user name"
    stored_email=$(git config --file "$temporary" --get user.email) \
        || die "could not verify the Git user email"
    [ "$stored_name" = "$name" ] && [ "$stored_email" = "$email" ] \
        || die "Git identity did not round-trip safely"

    if git_local_config_exists; then
        printf '  keep    %s (created concurrently)\n' "$(display_path "$GIT_LOCAL_CONFIG")"
        return 0
    fi
    validate_git_config_directory_ready
    if ln -T -- "$temporary" "$GIT_LOCAL_CONFIG" 2>/dev/null; then
        printf '  created %s\n' "$(display_path "$GIT_LOCAL_CONFIG")"
        return 0
    fi

    if git_local_config_exists; then
        printf '  keep    %s (created concurrently)\n' "$(display_path "$GIT_LOCAL_CONFIG")"
        return 0
    fi
    validate_git_configuration_layout
    die "could not create $GIT_LOCAL_CONFIG"
)

ssh_submodule_needs_init() {
    [ -f "$DOTFILES_DIR/.gitmodules" ] || return 1
    command -v git >/dev/null 2>&1 || return 1
    git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
    git -C "$DOTFILES_DIR" submodule status -- "$SSH_SUBMODULE_PATH" 2>/dev/null \
        | grep -q '^-'
}

# Resolve a relative submodule URL the way git does: each leading '../' drops one
# component from the superproject remote, and './' keeps it.
resolve_relative_git_url() {
    local base="${1%/}" relative="$2"

    while :; do
        case "$relative" in
            ./*)
                relative="${relative#./}"
                ;;
            ../*)
                relative="${relative#../}"
                base="${base%/*}"
                ;;
            *)
                break
                ;;
        esac
    done
    printf '%s/%s' "$base" "$relative"
}

private_submodule_url() {
    local origin url

    [ -f "$DOTFILES_DIR/.gitmodules" ] || return 1
    command -v git >/dev/null 2>&1 || return 1
    git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1

    # A checkout that already ran `submodule init` records the resolved URL; a
    # fresh clone only has the possibly relative .gitmodules value.
    url=$(git -C "$DOTFILES_DIR" config --get "submodule.$SSH_SUBMODULE_PATH.url" 2>/dev/null) \
        || url=""
    if [ -z "$url" ]; then
        url=$(git -C "$DOTFILES_DIR" config --file "$DOTFILES_DIR/.gitmodules" \
            --get "submodule.$SSH_SUBMODULE_PATH.url" 2>/dev/null) || url=""
    fi
    [ -n "$url" ] || return 1

    case "$url" in
        ./*|../*)
            # Git resolves relative submodule URLs against the raw remote value
            # without applying url.<base>.insteadOf rewrites.
            origin=$(git -C "$DOTFILES_DIR" config --get remote.origin.url 2>/dev/null) \
                || return 1
            [ -n "$origin" ] || return 1
            url=$(resolve_relative_git_url "$origin" "$url")
            ;;
    esac
    printf '%s' "$url"
}

private_submodule_uses_github_https() {
    case "$1" in
        https://github.com/*|https://gist.github.com/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

github_token_in_environment() {
    [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]
}

# Credential helpers run through `sh`, so quote for a POSIX shell instead of
# using printf %q, whose $'...' output dash does not understand.
shell_quote() {
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

find_gh() {
    local candidate

    if candidate=$(command -v gh 2>/dev/null) && [ -n "$candidate" ]; then
        printf '%s' "$candidate"
        return 0
    fi
    if [ -x "$LOCAL_BIN_DIR/gh" ]; then
        printf '%s' "$LOCAL_BIN_DIR/gh"
        return 0
    fi
    return 1
}

# `gh auth token` reads the stored credential without calling the API, so plan
# output and dry runs stay offline.
gh_has_github_token() {
    "$1" auth token --hostname github.com >/dev/null 2>&1
}

github_access_status() {
    local gh_bin url

    if [ "${BOOTSTRAP_SKIP_SUBMODULES:-0}" = "1" ]; then
        printf 'skip'
        return
    fi
    if [ "${BOOTSTRAP_SKIP_GITHUB_AUTH:-0}" = "1" ]; then
        printf 'skip-auth'
        return
    fi
    if ! ssh_submodule_needs_init; then
        printf 'ready'
        return
    fi
    if ! url=$(private_submodule_url); then
        printf 'unknown'
        return
    fi
    if ! private_submodule_uses_github_https "$url"; then
        printf 'other'
        return
    fi
    if github_token_in_environment; then
        printf 'token'
        return
    fi
    if ! gh_bin=$(find_gh); then
        printf 'install'
        return
    fi
    if gh_has_github_token "$gh_bin"; then
        printf 'ok'
    else
        printf 'login'
    fi
}

validate_sources() {
    local allow_pending_ssh="${1:-0}" source

    for source in "${SOURCES[@]}"; do
        if [ ! -e "$source" ]; then
            if [ "$allow_pending_ssh" -eq 1 ] \
                && [ "$source" = "$SSH_CONFIG_SOURCE" ] \
                && ssh_submodule_needs_init; then
                continue
            fi
            die "missing source: $source"
        fi
    done

    [ -f "$GIT_CONFIG_SOURCE" ] || die "missing source: $GIT_CONFIG_SOURCE"
    [ -f "$DOTFILES_DIR/package.json" ] || die "missing source: $DOTFILES_DIR/package.json"
    [ -f "$DOTFILES_DIR/package-lock.json" ] || die "missing source: $DOTFILES_DIR/package-lock.json"
    [ -f "$DOTFILES_DIR/scripts/tui/welcome/cli.mjs" ] || die "missing welcome app"
}

node_satisfies_welcome() {
    local major

    command -v node >/dev/null 2>&1 || return 1
    major=$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || printf '0')
    [ "$major" -eq "$WELCOME_NODE_MAJOR" ]
}

welcome_nvm_runtime_ready() {
    local nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"

    [ -s "$nvm_dir/nvm.sh" ] || return 1
    (
        # shellcheck source=/dev/null
        source "$nvm_dir/nvm.sh" --no-use
        command -v nvm >/dev/null 2>&1 || return 1
        NVM_SYMLINK_CURRENT=false \
            nvm use --silent "$WELCOME_NODE_VERSION" >/dev/null 2>&1 || return 1
        node_satisfies_welcome || return 1
        command -v npm >/dev/null 2>&1
    )
}

welcome_deps_installed() {
    [ -d "$DOTFILES_DIR/node_modules/ink" ] \
        && [ -d "$DOTFILES_DIR/node_modules/react" ]
}

welcome_dependency_status() {
    local runtime_ready=0

    welcome_nvm_runtime_ready && runtime_ready=1
    if [ "$runtime_ready" -eq 1 ] && welcome_deps_installed; then
        printf 'ok'
    elif [ "$runtime_ready" -eq 1 ]; then
        printf 'npm-ci'
    else
        printf 'node-and-npm-ci'
    fi
}

git_submodules_status() {
    [ -f "$DOTFILES_DIR/.gitmodules" ] || { printf 'none'; return; }
    command -v git >/dev/null 2>&1 || { printf 'no-git'; return; }
    git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 || { printf 'no-git'; return; }

    # `git submodule status` prefixes not-yet-checked-out entries with '-'.
    if git -C "$DOTFILES_DIR" submodule status 2>/dev/null | grep -q '^-'; then
        printf 'init'
    else
        printf 'ok'
    fi
}

print_plan() {
    local i status target
    local welcome_status

    printf 'Dotfile links:\n'
    for i in "${!SOURCES[@]}"; do
        status=$(target_status "${SOURCES[$i]}" "${TARGETS[$i]}")
        printf '  %-7s %s -> %s\n' "$status" "$(display_path "${TARGETS[$i]}")" "${SOURCES[$i]}"
    done

    printf '\nBackup-only files:\n'
    for target in "${BACKUP_ONLY_TARGETS[@]}"; do
        if [ -e "$target" ] || [ -L "$target" ]; then
            status="backup"
        else
            status="absent"
        fi
        printf '  %-7s %s\n' "$status" "$(display_path "$target")"
    done

    printf '\nLocal settings:\n'
    if shell_local_config_exists; then
        printf '  keep    %s (user-managed)\n' "$(display_path "$SHELL_LOCAL_CONFIG")"
    elif [ -n "${BOOTSTRAP_TZ:-}" ]; then
        printf '  create  %s with the configured timezone\n' "$(display_path "$SHELL_LOCAL_CONFIG")"
    else
        printf '  select  %s timezone with tzselect during apply\n' "$(display_path "$SHELL_LOCAL_CONFIG")"
    fi

    printf '\nGit configuration:\n'
    if [ -L "$GIT_CONFIG_DIR" ]; then
        printf '  migrate %s from a linked directory to a local directory\n' "$(display_path "$GIT_CONFIG_DIR")"
    elif [ -e "$GIT_CONFIG_DIR" ] && [ ! -d "$GIT_CONFIG_DIR" ]; then
        printf '  replace %s with a local directory\n' "$(display_path "$GIT_CONFIG_DIR")"
    elif git_config_directory_is_local; then
        printf '  keep    %s (local directory)\n' "$(display_path "$GIT_CONFIG_DIR")"
    else
        printf '  create  %s as a local directory\n' "$(display_path "$GIT_CONFIG_DIR")"
    fi
    if git_local_config_exists; then
        printf '  keep    %s (user-managed)\n' "$(display_path "$GIT_LOCAL_CONFIG")"
    elif [ -n "${BOOTSTRAP_GIT_NAME:-}" ] && [ -n "${BOOTSTRAP_GIT_EMAIL:-}" ]; then
        printf '  create  %s with the configured Git identity\n' "$(display_path "$GIT_LOCAL_CONFIG")"
    else
        printf '  select  %s Git identity during apply\n' "$(display_path "$GIT_LOCAL_CONFIG")"
    fi
    if git_config_directory_is_local; then
        status=$(target_status "$GIT_CONFIG_SOURCE" "$GIT_CONFIG_TARGET")
    else
        status="create"
    fi
    printf '  %-7s %s -> %s\n' "$status" "$(display_path "$GIT_CONFIG_TARGET")" "$GIT_CONFIG_SOURCE"

    welcome_status=$(welcome_dependency_status)
    printf '\nWelcome TUI:\n'
    case "$welcome_status" in
        ok)
            printf '  ok      Node %s.x available through nvm with Ink dependencies installed\n' "$WELCOME_NODE_MAJOR"
            ;;
        npm-ci)
            printf '  install npm ci with nvm Node %s in %s\n' "$WELCOME_NODE_VERSION" "$DOTFILES_DIR"
            ;;
        node-and-npm-ci)
            printf '  install nvm/Node %s if needed, then npm ci in %s\n' "$WELCOME_NODE_VERSION" "$DOTFILES_DIR"
            ;;
    esac

    printf '\nGitHub access:\n'
    case "$(github_access_status)" in
        skip)
            printf '  skip    submodule initialization disabled by BOOTSTRAP_SKIP_SUBMODULES\n'
            ;;
        skip-auth)
            printf '  skip    GitHub sign-in disabled by BOOTSTRAP_SKIP_GITHUB_AUTH\n'
            ;;
        ready)
            printf '  ok      private .ssh submodule already initialized\n'
            ;;
        unknown)
            printf '  skip    private .ssh submodule URL is unavailable\n'
            ;;
        other)
            printf '  none    private .ssh submodule does not use GitHub over HTTPS\n'
            ;;
        token)
            printf '  ok      an environment token provides github.com credentials\n'
            ;;
        ok)
            printf '  ok      gh is authenticated for github.com\n'
            ;;
        login)
            printf '  auth    gh auth login for github.com during apply\n'
            ;;
        install)
            printf '  install scripts/install/gh.sh, then gh auth login during apply\n'
            ;;
    esac

    printf '\nGit submodules:\n'
    case "$(git_submodules_status)" in
        none)
            printf '  none    no submodules registered\n'
            ;;
        no-git)
            printf '  skip    %s is not a git checkout\n' "$DOTFILES_DIR"
            ;;
        ok)
            printf '  ok      submodules initialized\n'
            ;;
        init)
            printf '  init    git submodule update --init --recursive in %s\n' "$DOTFILES_DIR"
            ;;
    esac
}

confirm_apply() {
    local answer

    [ "$YES" -eq 1 ] && return 0

    if [ ! -t 0 ]; then
        die "refusing to change files without --yes in a non-interactive shell"
    fi

    printf '\nApply these links? [y/N] '
    if ! IFS= read -r answer; then
        return 1
    fi

    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            printf 'Skipped.\n'
            return 1
            ;;
    esac
}

ensure_backup_dir() {
    if [ -z "$BACKUP_DIR" ]; then
        BACKUP_DIR="$HOME/.dotfiles-backup/$(date '+%Y%m%d-%H%M%S')"
        mkdir -p "$BACKUP_DIR"
    fi
}

backup_target() {
    local target="$1"
    local relative backup_path

    ensure_backup_dir
    relative="${target#"$HOME"/}"
    backup_path="$BACKUP_DIR/$relative"
    mkdir -p "$(dirname "$backup_path")"
    mv "$target" "$backup_path"
    printf '  backed up %s -> %s\n' "$(display_path "$target")" "$backup_path"
}

prepare_git_config_directory() {
    validate_git_configuration_layout
    if git_config_directory_requires_replacement; then
        backup_target "$GIT_CONFIG_DIR"
    fi
    mkdir -p "$GIT_CONFIG_DIR" \
        || die "could not create $GIT_CONFIG_DIR"
    validate_git_config_directory_ready
    validate_git_configuration_layout
}

link_target() {
    local source="$1" target="$2"

    if target_is_current "$source" "$target"; then
        printf '  ok      %s\n' "$(display_path "$target")"
        return 0
    fi

    mkdir -p "$(dirname "$target")"
    if [ -e "$target" ] || [ -L "$target" ]; then
        backup_target "$target"
    fi

    ln -s "$source" "$target"
    printf '  linked  %s -> %s\n' "$(display_path "$target")" "$source"
}

apply_links() {
    local i

    for i in "${!SOURCES[@]}"; do
        link_target "${SOURCES[$i]}" "${TARGETS[$i]}"
    done
}

backup_only_targets() {
    local target

    for target in "${BACKUP_ONLY_TARGETS[@]}"; do
        if [ -e "$target" ] || [ -L "$target" ]; then
            backup_target "$target"
        fi
    done
}

# `git -c` reaches the clone git spawns for a submodule through
# GIT_CONFIG_PARAMETERS, so credentials apply before ~/.config/git is linked.
# With a helper configured, a missing credential is a hard failure rather than a
# user name and password prompt GitHub would reject anyway.
submodule_update() {
    if [ "${#SSH_SUBMODULE_GIT_ARGS[@]}" -gt 0 ]; then
        GIT_TERMINAL_PROMPT=0 git -C "$DOTFILES_DIR" "${SSH_SUBMODULE_GIT_ARGS[@]}" \
            submodule update --init --recursive "$@"
    else
        git -C "$DOTFILES_DIR" submodule update --init --recursive "$@"
    fi
}

init_submodules() {
    [ "${BOOTSTRAP_SKIP_SUBMODULES:-0}" = "1" ] && return 0
    [ -f "$DOTFILES_DIR/.gitmodules" ] || return 0
    command -v git >/dev/null 2>&1 || return 0
    git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 0

    printf '\nInitializing git submodules...\n'
    if ! submodule_update; then
        printf 'warning: git submodule update failed; vendored plugins may be missing.\n' >&2
    fi
}

install_gh() {
    local gh_installer="$DOTFILES_DIR/scripts/install/gh.sh"

    [ -f "$gh_installer" ] || die "missing gh installer: $gh_installer"
    printf '\nInstalling gh for private SSH configuration access...\n'
    bash "$gh_installer" \
        || die "gh install failed; the private .ssh submodule needs GitHub access"
    hash -r 2>/dev/null || true
}

set_github_credential_helper() {
    SSH_SUBMODULE_GIT_ARGS=(
        -c 'credential.https://github.com.helper='
        -c "credential.https://github.com.helper=$1"
    )
}

# Dereference the token by name so it stays in the environment and never reaches
# GIT_CONFIG_PARAMETERS or the process list.
use_environment_github_token() {
    [ -z "${GH_TOKEN:-}" ] || export GH_TOKEN
    [ -z "${GITHUB_TOKEN:-}" ] || export GITHUB_TOKEN
    set_github_credential_helper \
        '!f() { test "$1" = get || exit 0; printf "username=x-access-token\npassword=%s\n" "${GH_TOKEN:-${GITHUB_TOKEN:-}}"; }; f'
}

# Resolve gh to an absolute path: $HOME/.local/bin is not necessarily on PATH
# after scripts/install/gh.sh runs, and the helper runs in the clone child.
use_gh_credential_helper() {
    set_github_credential_helper "!$(shell_quote "$GH_BIN") auth git-credential"
}

# Authenticate GitHub before the private submodule clone so git never falls back
# to prompting for a user name and password it cannot use.
ensure_github_access() {
    local status

    SSH_SUBMODULE_GIT_ARGS=()
    status=$(github_access_status)
    case "$status" in
        skip|skip-auth|ready|unknown|other)
            return 0
            ;;
        token)
            use_environment_github_token
            return 0
            ;;
    esac

    if [ "$status" = "ok" ]; then
        GH_BIN=$(find_gh) || die "gh became unavailable while preparing GitHub access"
        use_gh_credential_helper
        return 0
    fi

    # gh prompts only when stdin and stdout are both terminals.
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        die "GitHub authentication is required to clone the private .ssh submodule; run 'gh auth login' first, set GH_TOKEN, or set BOOTSTRAP_SKIP_GITHUB_AUTH=1 to use your own Git credentials"
    fi

    if [ "$status" = "install" ]; then
        install_gh
    fi
    GH_BIN=$(find_gh) || die "gh install completed, but gh is unavailable"
    printf '\nSigning in to github.com with gh...\n'
    "$GH_BIN" auth login --hostname github.com --git-protocol https \
        || die "gh auth login did not complete; the private .ssh submodule was not cloned"
    gh_has_github_token "$GH_BIN" \
        || die "gh is still not signed in to github.com; the private .ssh submodule was not cloned"
    use_gh_credential_helper
}

init_required_ssh_submodule() {
    [ "${BOOTSTRAP_SKIP_SUBMODULES:-0}" = "1" ] && return 0
    ssh_submodule_needs_init || return 0

    printf '\nInitializing private SSH configuration...\n'
    if ! submodule_update -- "$SSH_SUBMODULE_PATH"; then
        die "failed to initialize private .ssh submodule; verify access to ssh-config"
    fi
}

load_or_install_welcome_node() {
    local nvm_dir="${NVM_DIR:-$HOME/.config/nvm}"
    local nvm_installer="$DOTFILES_DIR/scripts/install/nvm.sh"
    local installed_version default_alias_file="$nvm_dir/alias/default"
    local had_default_alias=0

    if [ -e "$default_alias_file" ] || [ -L "$default_alias_file" ]; then
        had_default_alias=1
    fi

    if [ ! -s "$nvm_dir/nvm.sh" ]; then
        printf '\nPreparing nvm for welcome TUI...\n'
        [ -f "$nvm_installer" ] || die "missing nvm installer: $nvm_installer"
        bash "$nvm_installer"
    fi

    [ -s "$nvm_dir/nvm.sh" ] || die "nvm install completed, but $nvm_dir/nvm.sh is missing"
    # shellcheck source=/dev/null
    source "$nvm_dir/nvm.sh" --no-use
    command -v nvm >/dev/null 2>&1 || die "nvm install completed, but nvm is unavailable"

    installed_version=$(nvm version "$WELCOME_NODE_VERSION" 2>/dev/null || true)
    if [[ ! "$installed_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '\nPreparing Node %s for welcome TUI...\n' "$WELCOME_NODE_VERSION"
        nvm install "$WELCOME_NODE_VERSION"
        if [ "$had_default_alias" -eq 0 ] \
            && { [ -e "$default_alias_file" ] || [ -L "$default_alias_file" ]; }; then
            rm -f -- "$default_alias_file"
        fi
    fi
    nvm use "$WELCOME_NODE_VERSION"

    node_satisfies_welcome || die "Node $WELCOME_NODE_MAJOR.x is still unavailable after installing Node $WELCOME_NODE_VERSION"
    command -v npm >/dev/null 2>&1 || die "npm is unavailable after installing Node $WELCOME_NODE_VERSION"
}

install_welcome_deps() {
    if welcome_nvm_runtime_ready && welcome_deps_installed; then
        printf '\nWelcome TUI dependencies already installed.\n'
        return 0
    fi

    load_or_install_welcome_node

    printf '\nInstalling welcome TUI dependencies...\n'
    npm --prefix "$DOTFILES_DIR" ci
}

validate_sources 1
validate_shell_local_configuration_request
validate_git_identity_request
print_plan

if [ "$DRY_RUN" -eq 1 ]; then
    printf '\nDry run only; no files changed.\n'
    exit 0
fi

confirm_apply || exit 0
ensure_github_access
init_required_ssh_submodule
validate_sources
validate_shell_local_configuration_request
validate_git_identity_request
collect_local_settings
if [ "$CREATE_SHELL_LOCAL_CONFIG" -eq 1 ]; then
    publish_shell_local_config "$SELECTED_TIMEZONE"
fi
prepare_git_config_directory
if [ "$CREATE_GIT_LOCAL_CONFIG" -eq 1 ]; then
    publish_git_local_config "$SELECTED_GIT_NAME" "$SELECTED_GIT_EMAIL"
fi
link_target "$GIT_CONFIG_SOURCE" "$GIT_CONFIG_TARGET"
apply_links
backup_only_targets
init_submodules
install_welcome_deps

if [ -n "$BACKUP_DIR" ]; then
    printf '\nBackups saved in %s\n' "$BACKUP_DIR"
fi
