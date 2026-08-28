#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

ORIGINAL_PATH="$PATH"
FAKE_BIN="$TMP_DIR/bin"
FAKE_TEXLIVE_HASH="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
FAKE_CURL_LOG="$TMP_DIR/curl.log"
FAKE_PERL_LOG="$TMP_DIR/perl.log"
mkdir -p "$FAKE_BIN"
export FAKE_TEXLIVE_HASH FAKE_CURL_LOG FAKE_PERL_LOG

cat >"$FAKE_BIN/curl" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_CURL_LOG"

output=''
write_format=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            output="$2"
            shift 2
            ;;
        -w)
            write_format="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

case "$output" in
    *.sha512)
        printf '%s  install-tl-unx.tar.gz\n' "$FAKE_TEXLIVE_HASH" >"$output"
        ;;
    *)
        printf 'fake TeX Live installer archive\n' >"$output"
        ;;
esac

if [ -n "$write_format" ]; then
    printf 'https://texlive.example.test/systems/texlive/tlnet/install-tl-unx.tar.gz'
fi
SCRIPT

cat >"$FAKE_BIN/sha512sum" <<'SCRIPT'
#!/bin/sh
printf '%s  %s\n' "$FAKE_TEXLIVE_HASH" "$1"
SCRIPT

cat >"$FAKE_BIN/tar" <<'SCRIPT'
#!/bin/sh
target=''
while [ "$#" -gt 0 ]; do
    if [ "$1" = '-C' ]; then
        target="$2"
        shift 2
    else
        shift
    fi
done

[ -n "$target" ] || exit 91
installer_dir="$target/install-tl-20260827"
mkdir -p "$installer_dir/tlpkg"
: >"$installer_dir/install-tl"
printf '%s\n' \
    'TeX Live (https://tug.org/texlive) version 2026' \
    '' \
    'This file is public domain.' \
    >"$installer_dir/release-texlive.txt"
SCRIPT

cat >"$FAKE_BIN/perl" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_PERL_LOG"

target=''
for argument in "$@"; do
    case "$argument" in
        --texdir=*) target=${argument#--texdir=} ;;
    esac
done
[ -n "$target" ] || exit 92

mkdir -p "$target/bin/x86_64-linux"
printf 'fixture install log\n' >"$target/install-tl.log"
cat >"$target/bin/x86_64-linux/latex" <<'LATEX'
#!/bin/sh
printf 'pdfTeX 3.141592653 (TeX Live 2026)\n'
LATEX
cat >"$target/bin/x86_64-linux/tlmgr" <<'TLMGR'
#!/bin/sh
printf 'TeX Live (https://tug.org/texlive) version 2026\n'
TLMGR
chmod +x "$target/bin/x86_64-linux/latex" "$target/bin/x86_64-linux/tlmgr"

[ "${FAKE_PERL_FAIL:-0}" -ne 1 ] || exit 42
SCRIPT

chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/sha512sum" "$FAKE_BIN/tar" "$FAKE_BIN/perl"

SUCCESS_HOME="$TMP_DIR/success-home"
SUCCESS_ROOT="$TMP_DIR/success-texlive"
mkdir -p "$SUCCESS_HOME"
: >"$FAKE_CURL_LOG"
: >"$FAKE_PERL_LOG"

HOME="$SUCCESS_HOME" \
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    TEXLIVE_ROOT="$SUCCESS_ROOT" \
    TEXLIVE_SCHEME=scheme-full \
    bash "$ROOT_DIR/scripts/install/latex.sh" >/dev/null

[ -x "$SUCCESS_ROOT/2026/bin/x86_64-linux/latex" ]
[ -L "$SUCCESS_ROOT/current" ]
[ "$(readlink "$SUCCESS_ROOT/current")" = '2026' ]
[ "$(wc -l <"$FAKE_CURL_LOG")" -eq 2 ]
grep -Fxq -- \
    '-fL --retry 3 --connect-timeout 30 https://texlive.example.test/systems/texlive/tlnet/install-tl-unx.tar.gz.sha512 -o' \
    <(sed 's| -o .*| -o|' "$FAKE_CURL_LOG")
grep -Fq -- '--no-interaction --no-continue --scheme=scheme-full --strict' "$FAKE_PERL_LOG"
grep -Fq -- "--texdir=$SUCCESS_ROOT/2026" "$FAKE_PERL_LOG"

FAIL_HOME="$TMP_DIR/fail-home"
FAIL_ROOT="$TMP_DIR/fail-texlive"
mkdir -p "$FAIL_HOME" "$FAIL_ROOT/2025"
printf 'keep\n' >"$FAIL_ROOT/2025/marker"
ln -s 2025 "$FAIL_ROOT/current"
: >"$FAKE_PERL_LOG"

if HOME="$FAIL_HOME" \
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    TEXLIVE_ROOT="$FAIL_ROOT" \
    TEXLIVE_SCHEME=scheme-full \
    FAKE_PERL_FAIL=1 \
    bash "$ROOT_DIR/scripts/install/latex.sh" >/dev/null 2>&1; then
    printf 'failing TeX Live fixture unexpectedly succeeded\n' >&2
    exit 1
fi

[ -f "$FAIL_ROOT/2025/marker" ]
[ "$(readlink "$FAIL_ROOT/current")" = '2025' ]
[ ! -e "$FAIL_ROOT/2026" ]
[ "$(cat "$FAIL_ROOT/install-tl-2026.failed.log")" = 'fixture install log' ]

BASHRC_UNDER_TEST="$ROOT_DIR/.bashrc"
export BASHRC_UNDER_TEST
selected_latex=$(HOME="$SUCCESS_HOME" \
    TEXLIVE_ROOT="$SUCCESS_ROOT" \
    bash --noprofile --norc -ic \
    'source "$BASHRC_UNDER_TEST"; command -v latex' \
    2>/dev/null)
[ "$selected_latex" = "$SUCCESS_ROOT/current/bin/x86_64-linux/latex" ]
