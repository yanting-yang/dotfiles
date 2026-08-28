#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
YES=0
BACKUP_DIR=""
LOCAL_CONFIG="$HOME/local.sh"
SSH_SUBMODULE_PATH=".ssh"
SSH_CONFIG_SOURCE="$DOTFILES_DIR/$SSH_SUBMODULE_PATH/config"

# shellcheck source=scripts/lib/node.sh
source "$DOTFILES_DIR/scripts/lib/node.sh"

SOURCES=(
    "$DOTFILES_DIR/.bash_profile"
    "$DOTFILES_DIR/.bashrc"
    "$SSH_CONFIG_SOURCE"
    "$DOTFILES_DIR/.config/git"
    "$DOTFILES_DIR/.config/nvim"
    "$DOTFILES_DIR/.config/kitty"
    "$DOTFILES_DIR/.config/tmux"
)

TARGETS=(
    "$HOME/.bash_profile"
    "$HOME/.bashrc"
    "$HOME/.ssh/config"
    "$HOME/.config/git"
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
    printf '  --yes      skip apply confirmation; timezone selection may still prompt\n'
    printf '\n'
    printf 'Environment:\n'
    printf '  BOOTSTRAP_TZ         timezone for unattended local.sh creation\n'
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

local_config_exists() {
    [ -f "$LOCAL_CONFIG" ] || [ -L "$LOCAL_CONFIG" ]
}

validate_local_config_target() {
    if [ -e "$LOCAL_CONFIG" ] && ! local_config_exists; then
        die "$LOCAL_CONFIG exists but is not a regular file or symlink"
    fi
}

timezone_value_is_single_line() {
    [ -n "$1" ] && [[ "$1" != *$'\n'* ]] && [[ "$1" != *$'\r'* ]]
}

installed_timezone_is_valid() {
    local timezone="$1" zoneinfo_dir="${TZDIR:-/usr/share/zoneinfo}"

    timezone_value_is_single_line "$timezone" || return 1
    [[ "$timezone" =~ ^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*$ ]] || return 1
    case "/$timezone/" in
        */./*|*/../*) return 1 ;;
    esac
    [ -f "$zoneinfo_dir/$timezone" ] && [ -r "$zoneinfo_dir/$timezone" ]
}

validate_local_configuration_request() {
    validate_local_config_target
    if ! local_config_exists && [ -n "${BOOTSTRAP_TZ:-}" ]; then
        installed_timezone_is_valid "$BOOTSTRAP_TZ" \
            || die "invalid BOOTSTRAP_TZ: expected an installed timezone such as America/Vancouver"
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
    timezone_value_is_single_line "$timezone" \
        || die "tzselect returned an invalid timezone"
    printf '%s' "$timezone"
}

publish_local_config() (
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

    if local_config_exists; then
        printf '  keep    %s (created concurrently)\n' "$(display_path "$LOCAL_CONFIG")"
        return 0
    fi
    if ln -T -- "$temporary" "$LOCAL_CONFIG" 2>/dev/null; then
        printf '  created %s with TZ=%s\n' "$(display_path "$LOCAL_CONFIG")" "$timezone"
        return 0
    fi

    if local_config_exists; then
        printf '  keep    %s (created concurrently)\n' "$(display_path "$LOCAL_CONFIG")"
        return 0
    fi
    validate_local_config_target
    die "could not create $LOCAL_CONFIG"
)

ensure_local_config() {
    local timezone

    validate_local_configuration_request
    local_config_exists && return 0
    if ! timezone=$(select_timezone); then
        return 1
    fi
    publish_local_config "$timezone"
}

ssh_submodule_needs_init() {
    [ -f "$DOTFILES_DIR/.gitmodules" ] || return 1
    command -v git >/dev/null 2>&1 || return 1
    git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
    git -C "$DOTFILES_DIR" submodule status -- "$SSH_SUBMODULE_PATH" 2>/dev/null \
        | grep -q '^-'
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
    if local_config_exists; then
        printf '  keep    %s (user-managed)\n' "$(display_path "$LOCAL_CONFIG")"
    elif [ -n "${BOOTSTRAP_TZ:-}" ]; then
        printf '  create  %s with the configured timezone\n' "$(display_path "$LOCAL_CONFIG")"
    else
        printf '  select  %s timezone with tzselect during apply\n' "$(display_path "$LOCAL_CONFIG")"
    fi

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

init_submodules() {
    [ "${BOOTSTRAP_SKIP_SUBMODULES:-0}" = "1" ] && return 0
    [ -f "$DOTFILES_DIR/.gitmodules" ] || return 0
    command -v git >/dev/null 2>&1 || return 0
    git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 0

    printf '\nInitializing git submodules...\n'
    if ! git -C "$DOTFILES_DIR" submodule update --init --recursive; then
        printf 'warning: git submodule update failed; vendored plugins may be missing.\n' >&2
    fi
}

init_required_ssh_submodule() {
    [ "${BOOTSTRAP_SKIP_SUBMODULES:-0}" = "1" ] && return 0
    ssh_submodule_needs_init || return 0

    printf '\nInitializing private SSH configuration...\n'
    if ! git -C "$DOTFILES_DIR" submodule update --init --recursive -- "$SSH_SUBMODULE_PATH"; then
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
validate_local_configuration_request
print_plan

if [ "$DRY_RUN" -eq 1 ]; then
    printf '\nDry run only; no files changed.\n'
    exit 0
fi

confirm_apply || exit 0
init_required_ssh_submodule
validate_sources
ensure_local_config
apply_links
backup_only_targets
init_submodules
install_welcome_deps

if [ -n "$BACKUP_DIR" ]; then
    printf '\nBackups saved in %s\n' "$BACKUP_DIR"
fi
