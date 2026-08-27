#!/usr/bin/env bash

DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
LOCAL_PREFIX="${LOCAL_PREFIX:-$HOME/.local}"
LOCAL_BIN_DIR="$LOCAL_PREFIX/bin"
LOCAL_STOW_DIR="$LOCAL_PREFIX/stow"

case ":$PATH:" in
    *":$LOCAL_BIN_DIR:"*) ;;
    *)
        PATH="$LOCAL_BIN_DIR:$PATH"
        export PATH
        ;;
esac

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local cmd

    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
    done
}

make_temp_dir() {
    require_command mktemp
    mktemp -d
}

download_tar_to_dir() {
    local url="$1" target_dir="$2"
    shift 2

    require_command curl tar
    mkdir -p "$target_dir"
    curl -fLs "$url" | tar xz "$@" -C "$target_dir"
}

download_txz_to_dir() {
    local url="$1" target_dir="$2"
    shift 2

    require_command curl tar xz
    mkdir -p "$target_dir"
    curl -fLs "$url" | tar xJ "$@" -C "$target_dir"
}

download_zip_to_dir() {
    local url="$1" target_dir="$2" archive

    require_command curl unzip mktemp
    mkdir -p "$target_dir"
    archive=$(mktemp)
    curl -fLs "$url" -o "$archive"
    unzip -q -o "$archive" -d "$target_dir"
    rm -f -- "$archive"
}

copy_dir_contents() {
    local source_dir="$1" target_dir="$2"

    require_command cp
    mkdir -p "$target_dir"
    cp -a "$source_dir/." "$target_dir/"
}

clear_dir_contents() {
    local target_dir="$1"

    [ -d "$target_dir" ] || return 0
    require_command find
    find "$target_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

latest_github_tag() {
    local repo="$1" latest

    require_command curl
    latest=$(curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
    latest="${latest##*/}"

    [ -n "$latest" ] && [ "$latest" != "latest" ] || die "could not resolve latest release for $repo"
    printf '%s' "$latest"
}

latest_git_tag() {
    local repo_url="$1" latest

    require_command git
    latest=$(git ls-remote --tags --refs "$repo_url" 'v*' 2>/dev/null \
        | sed -n 's|.*refs/tags/\(v[0-9][0-9.]*\)$|\1|p' \
        | sort -V \
        | tail -1)

    [ -n "$latest" ] || die "could not resolve latest tag for $repo_url"
    printf '%s' "$latest"
}

stow_package_dir() {
    printf '%s/%s' "$LOCAL_STOW_DIR" "$1"
}

ensure_stow_available() {
    local stow_installer="$DOTFILES_DIR/scripts/install/stow.sh"

    if command -v stow >/dev/null 2>&1; then
        return 0
    fi

    [ -f "$stow_installer" ] || die "stow is required and $stow_installer is missing"
    printf 'stow is required; installing it first...\n'
    bash "$stow_installer"
    hash -r 2>/dev/null || true
    command -v stow >/dev/null 2>&1 || die "stow install completed, but stow is still not on PATH"
}

prepare_stow_package() {
    local package="$1" package_dir

    ensure_stow_available
    package_dir=$(stow_package_dir "$package")
    mkdir -p "$LOCAL_STOW_DIR"

    if [ -d "$package_dir" ]; then
        stow -d "$LOCAL_STOW_DIR" -D "$package" || true
        rm -rf "$package_dir"
    fi

    mkdir -p "$package_dir"
}

activate_stow_package() {
    local package="$1"

    ensure_stow_available
    stow -d "$LOCAL_STOW_DIR" --no-folding "$package"
}

cleanup_temp_dir() {
    local temp_dir="$1"

    [ -n "$temp_dir" ] && [ -d "$temp_dir" ] && rm -rf "$temp_dir"
}
