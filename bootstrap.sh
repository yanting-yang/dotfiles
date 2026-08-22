#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
YES=0
BACKUP_DIR=""

# shellcheck source=scripts/lib/node.sh
source "$DOTFILES_DIR/scripts/lib/node.sh"

SOURCES=(
    "$DOTFILES_DIR/.profile"
    "$DOTFILES_DIR/.bashrc"
    "$DOTFILES_DIR/.ssh/config"
    "$DOTFILES_DIR/.config/git"
    "$DOTFILES_DIR/.config/nvim"
    "$DOTFILES_DIR/.config/kitty"
    "$DOTFILES_DIR/.config/tmux"
)

TARGETS=(
    "$HOME/.profile"
    "$HOME/.bashrc"
    "$HOME/.ssh/config"
    "$HOME/.config/git"
    "$HOME/.config/nvim"
    "$HOME/.config/kitty"
    "$HOME/.config/tmux"
)

BACKUP_ONLY_TARGETS=(
    "$HOME/.lesshst"
    "$HOME/.bash_history"
    "$HOME/.bash_logout"
)

usage() {
    printf 'Usage: %s [--dry-run] [--yes]\n' "${0##*/}"
    printf '\n'
    printf '  --dry-run  show planned links without changing files\n'
    printf '  --yes      apply without prompting; required for non-interactive use\n'
    printf '\n'
    printf 'Environment:\n'
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

validate_sources() {
    local source

    for source in "${SOURCES[@]}"; do
        [ -e "$source" ] || die "missing source: $source"
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

validate_sources
print_plan

if [ "$DRY_RUN" -eq 1 ]; then
    printf '\nDry run only; no files changed.\n'
    exit 0
fi

confirm_apply || exit 0
apply_links
backup_only_targets
install_welcome_deps

if [ -n "$BACKUP_DIR" ]; then
    printf '\nBackups saved in %s\n' "$BACKUP_DIR"
fi
