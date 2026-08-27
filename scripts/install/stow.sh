#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/install.sh"

require_command perl sed cp

TAG_NAME=$(latest_git_tag https://github.com/aspiers/stow.git)
URL="https://github.com/aspiers/stow/archive/refs/tags/$TAG_NAME.tar.gz"

TEMP_DIR=$(make_temp_dir)
trap 'cleanup_temp_dir "$TEMP_DIR"' EXIT

SRC_DIR="$TEMP_DIR/src"
DIST_DIR="$TEMP_DIR/dist"
download_tar_to_dir "$URL" "$SRC_DIR" --strip-components=1

# GitHub source tarballs ship configure.ac but no generated ./configure, and
# stow is pure Perl, so expand the templates the way Makefile.am's `edit` rule
# does instead of requiring the autotools and texinfo toolchain.
STOW_VERSION="${TAG_NAME#v}"
PERL_BIN=$(command -v perl)
PM_DIR="$LOCAL_PREFIX/share/perl5"

stow_edit() {
    sed -e "s|[@]PERL[@]|$PERL_BIN|g" \
        -e "s|[@]VERSION[@]|$STOW_VERSION|g" \
        -e "s|[@]USE_LIB_PMDIR[@]|use lib \"$PM_DIR\";|g" \
        "$1"
}

mkdir -p "$DIST_DIR/bin" "$DIST_DIR/share/perl5/Stow"

stow_edit "$SRC_DIR/bin/stow.in" >"$DIST_DIR/bin/stow"
stow_edit "$SRC_DIR/bin/chkstow.in" >"$DIST_DIR/bin/chkstow"
chmod +x "$DIST_DIR/bin/stow" "$DIST_DIR/bin/chkstow"

# Stow.pm is the expanded template with the default ignore list appended.
{
    stow_edit "$SRC_DIR/lib/Stow.pm.in"
    cat "$SRC_DIR/default-ignore-list"
} >"$DIST_DIR/share/perl5/Stow.pm"
stow_edit "$SRC_DIR/lib/Stow/Util.pm.in" >"$DIST_DIR/share/perl5/Stow/Util.pm"

# The generated scripts point at the final $PM_DIR, which does not exist until
# the copy below, so smoke-test the staged build against the staged modules.
PERL5LIB="$DIST_DIR/share/perl5" "$DIST_DIR/bin/stow" --version >/dev/null \
    || die "built stow is not runnable"

copy_dir_contents "$DIST_DIR" "$LOCAL_PREFIX"
mkdir -p "$LOCAL_STOW_DIR"
