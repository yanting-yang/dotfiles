#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/install.sh
source "$SCRIPT_DIR/../lib/install.sh"

TEXLIVE_INSTALLER_URL="${TEXLIVE_INSTALLER_URL:-https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz}"
TEXLIVE_ROOT="${TEXLIVE_ROOT:-$HOME/texlive}"
TEXLIVE_SCHEME="${TEXLIVE_SCHEME:-scheme-full}"
TEMP_DIR=""
TARGET_DIR=""
TARGET_CREATED=0
ROOT_CREATED=0
INSTALL_COMPLETE=0
CURRENT_LINK_TEMP=""

cleanup_latex_install() {
    if [ "$INSTALL_COMPLETE" -ne 1 ] \
        && [ "$TARGET_CREATED" -eq 1 ] \
        && [ -n "$TARGET_DIR" ] \
        && [ -d "$TARGET_DIR" ]; then
        if [ -f "$TARGET_DIR/install-tl.log" ] && [ -n "${TEXLIVE_YEAR:-}" ]; then
            cp "$TARGET_DIR/install-tl.log" \
                "$TEXLIVE_ROOT/install-tl-$TEXLIVE_YEAR.failed.log" 2>/dev/null || true
            if [ -f "$TEXLIVE_ROOT/install-tl-$TEXLIVE_YEAR.failed.log" ]; then
                printf 'Preserved the failed installer log at %s.\n' \
                    "$TEXLIVE_ROOT/install-tl-$TEXLIVE_YEAR.failed.log" >&2
            fi
        fi
        rm -rf -- "$TARGET_DIR"
    fi
    if [ -n "$CURRENT_LINK_TEMP" ]; then
        rm -f -- "$CURRENT_LINK_TEMP"
    fi
    if [ -n "$TEMP_DIR" ]; then
        cleanup_temp_dir "$TEMP_DIR"
    fi
    if [ "$ROOT_CREATED" -eq 1 ]; then
        rmdir "$TEXLIVE_ROOT" 2>/dev/null || true
    fi
}

trap cleanup_latex_install EXIT
trap 'exit 130' HUP INT TERM

validate_texlive_root() {
    local resolved_root

    case "$TEXLIVE_ROOT" in
        /*) ;;
        *) die "TEXLIVE_ROOT must be an absolute path: $TEXLIVE_ROOT" ;;
    esac
    if [ -e "$TEXLIVE_ROOT" ] || [ -L "$TEXLIVE_ROOT" ]; then
        [ -d "$TEXLIVE_ROOT" ] || die "TEXLIVE_ROOT is not a directory: $TEXLIVE_ROOT"
    fi

    resolved_root=$(readlink -m "$TEXLIVE_ROOT" 2>/dev/null) \
        || die "could not resolve TEXLIVE_ROOT: $TEXLIVE_ROOT"
    case "$resolved_root" in
        /|"$HOME"|"$DOTFILES_DIR"|"$DOTFILES_DIR"/*)
            die "refusing unsafe TEXLIVE_ROOT: $resolved_root"
            ;;
    esac
    TEXLIVE_ROOT="$resolved_root"

    [[ "$TEXLIVE_SCHEME" =~ ^scheme-[A-Za-z0-9][A-Za-z0-9_-]*$ ]] \
        || die "invalid TEXLIVE_SCHEME: $TEXLIVE_SCHEME"
}

verify_installer_checksum() {
    local archive="$1" checksum_file="$2" actual_hash expected_hash checksum_name
    local checksum_rows=()

    mapfile -t checksum_rows < <(awk 'NF { print $1 "|" $2 }' "$checksum_file")
    [ "${#checksum_rows[@]}" -eq 1 ] || die "unexpected TeX Live checksum format"

    IFS='|' read -r expected_hash checksum_name <<<"${checksum_rows[0]}"
    checksum_name="${checksum_name#\*}"
    [ "$checksum_name" = "install-tl-unx.tar.gz" ] \
        || die "unexpected TeX Live checksum filename: $checksum_name"
    [[ "$expected_hash" =~ ^[[:xdigit:]]{128}$ ]] \
        || die "invalid TeX Live SHA-512 checksum"

    actual_hash=$(sha512sum "$archive" | awk '{ print $1 }')
    [ "${actual_hash,,}" = "${expected_hash,,}" ] \
        || die "TeX Live installer checksum verification failed"
}

find_texlive_bin() {
    local candidate found=""

    for candidate in "$TARGET_DIR"/bin/*; do
        [ -x "$candidate/latex" ] || continue
        [ -x "$candidate/tlmgr" ] || continue
        [ -z "$found" ] || die "multiple TeX Live binary directories found in $TARGET_DIR"
        found="$candidate"
    done

    [ -n "$found" ] || die "installed TeX Live commands could not be verified"
    printf '%s' "$found"
}

select_texlive_install() {
    local rc=0

    # Ignore cancellation only for the tiny atomic commit sequence. Otherwise
    # a signal after replacing `current` but before recording success could
    # make EXIT cleanup remove the newly selected release.
    trap '' HUP INT TERM
    if mv -Tf "$CURRENT_LINK_TEMP" "$TEXLIVE_ROOT/current"; then
        CURRENT_LINK_TEMP=""
        INSTALL_COMPLETE=1
    else
        rc=$?
    fi
    trap 'exit 130' HUP INT TERM

    [ "$rc" -eq 0 ] || die "could not select the new TeX Live release"
}

require_command awk cp curl head ln mkdir mv perl readlink sed sha512sum tar
validate_texlive_root

TEMP_DIR=$(make_temp_dir)
ARCHIVE="$TEMP_DIR/install-tl-unx.tar.gz"
CHECKSUM_FILE="$TEMP_DIR/install-tl-unx.tar.gz.sha512"
SOURCE_DIR="$TEMP_DIR/source"

printf 'Downloading the TeX Live network installer...\n'
ARCHIVE_EFFECTIVE_URL=$(curl -fL --retry 3 --connect-timeout 30 \
    "$TEXLIVE_INSTALLER_URL" -o "$ARCHIVE" -w '%{url_effective}')
ARCHIVE_MIRROR_URL="${ARCHIVE_EFFECTIVE_URL%%\?*}"
case "$ARCHIVE_MIRROR_URL" in
    https://*/install-tl-unx.tar.gz) ;;
    *) die "unexpected TeX Live installer mirror URL: $ARCHIVE_EFFECTIVE_URL" ;;
esac
curl -fL --retry 3 --connect-timeout 30 \
    "${ARCHIVE_MIRROR_URL}.sha512" -o "$CHECKSUM_FILE"
verify_installer_checksum "$ARCHIVE" "$CHECKSUM_FILE"

mkdir -p "$SOURCE_DIR"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIR"

shopt -s nullglob
INSTALLER_DIRS=("$SOURCE_DIR"/install-tl-*)
shopt -u nullglob
[ "${#INSTALLER_DIRS[@]}" -eq 1 ] \
    || die "expected one extracted TeX Live installer directory"
INSTALLER_DIR="${INSTALLER_DIRS[0]}"
INSTALL_TL="$INSTALLER_DIR/install-tl"
RELEASE_FILE="$INSTALLER_DIR/release-texlive.txt"
[ -f "$INSTALL_TL" ] || die "TeX Live install-tl is missing from the archive"
[ -f "$RELEASE_FILE" ] || die "TeX Live release metadata is missing from the archive"

TEXLIVE_YEAR=$(sed -n \
    's/^TeX Live .* version \(20[0-9][0-9]\)$/\1/p' \
    "$RELEASE_FILE" | head -1)
[[ "$TEXLIVE_YEAR" =~ ^20[0-9]{2}$ ]] \
    || die "could not determine the TeX Live release year"

TARGET_DIR="$TEXLIVE_ROOT/$TEXLIVE_YEAR"
if [ -e "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
    die "TeX Live $TEXLIVE_YEAR already exists at $TARGET_DIR"
fi
if [ -e "$TEXLIVE_ROOT/current" ] && [ ! -L "$TEXLIVE_ROOT/current" ]; then
    die "refusing to replace non-symlink $TEXLIVE_ROOT/current"
fi

if [ ! -d "$TEXLIVE_ROOT" ]; then
    mkdir -p "$TEXLIVE_ROOT"
    ROOT_CREATED=1
fi
mkdir "$TARGET_DIR"
TARGET_CREATED=1

printf 'Installing TeX Live %s (%s) into %s.\n' \
    "$TEXLIVE_YEAR" "$TEXLIVE_SCHEME" "$TARGET_DIR"
if [ "$TEXLIVE_SCHEME" = "scheme-full" ]; then
    printf 'The full scheme needs roughly 10 GB and may take several hours.\n'
fi
perl "$INSTALL_TL" \
    --no-interaction \
    --no-continue \
    --scheme="$TEXLIVE_SCHEME" \
    --strict \
    --texdir="$TARGET_DIR"

TEXLIVE_BIN=$(find_texlive_bin)
INSTALLED_YEAR=$("$TEXLIVE_BIN/latex" --version 2>/dev/null \
    | sed -n '1{s/.*(TeX Live \(20[0-9][0-9]\).*$/\1/p;q;}')
[ "$INSTALLED_YEAR" = "$TEXLIVE_YEAR" ] \
    || die "installed LaTeX does not report TeX Live $TEXLIVE_YEAR"
"$TEXLIVE_BIN/tlmgr" --version >/dev/null 2>&1 \
    || die "installed tlmgr could not be verified"

CURRENT_LINK_TEMP="$TEXLIVE_ROOT/.current.$$"
ln -s "$TEXLIVE_YEAR" "$CURRENT_LINK_TEMP"
select_texlive_install

printf 'Installed TeX Live %s and selected it through %s/current.\n' \
    "$TEXLIVE_YEAR" "$TEXLIVE_ROOT"
