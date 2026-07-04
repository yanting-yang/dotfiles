#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
YES=0
BACKUP_DIR=""

SOURCES=(
    "$DOTFILES_DIR/.profile"
    "$DOTFILES_DIR/.bashrc"
    "$DOTFILES_DIR/.ssh/config"
    "$DOTFILES_DIR/.config/git"
    "$DOTFILES_DIR/.config/nvim"
)

TARGETS=(
    "$HOME/.profile"
    "$HOME/.bashrc"
    "$HOME/.ssh/config"
    "$HOME/.config/git"
    "$HOME/.config/nvim"
)

usage() {
    printf 'Usage: %s [--dry-run] [--yes]\n' "${0##*/}"
    printf '\n'
    printf '  --dry-run  show planned links without changing files\n'
    printf '  --yes      apply without prompting; required for non-interactive use\n'
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

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
}

print_plan() {
    local i status

    printf 'Dotfile links:\n'
    for i in "${!SOURCES[@]}"; do
        status=$(target_status "${SOURCES[$i]}" "${TARGETS[$i]}")
        printf '  %-7s %s -> %s\n' "$status" "$(display_path "${TARGETS[$i]}")" "${SOURCES[$i]}"
    done
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

validate_sources
print_plan

if [ "$DRY_RUN" -eq 1 ]; then
    printf '\nDry run only; no files changed.\n'
    exit 0
fi

confirm_apply || exit 0
apply_links

if [ -n "$BACKUP_DIR" ]; then
    printf '\nBackups saved in %s\n' "$BACKUP_DIR"
fi
