#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

# Run the ordinary bootstrap cases against a self-contained public fixture so
# they never depend on access to the real private SSH submodule.
ROOT_DIR="$TEST_ROOT/dotfiles"
mkdir -p \
    "$ROOT_DIR/.ssh" \
    "$ROOT_DIR/.config/git" \
    "$ROOT_DIR/.config/nvim" \
    "$ROOT_DIR/.config/kitty" \
    "$ROOT_DIR/.config/tmux" \
    "$ROOT_DIR/scripts/lib" \
    "$ROOT_DIR/scripts/tui/welcome" \
    "$ROOT_DIR/node_modules/ink" \
    "$ROOT_DIR/node_modules/react"
cp "$SOURCE_ROOT/bootstrap.sh" "$ROOT_DIR/bootstrap.sh"
cp "$SOURCE_ROOT/.bash_profile" "$ROOT_DIR/.bash_profile"
cp "$SOURCE_ROOT/.bashrc" "$ROOT_DIR/.bashrc"
cp "$SOURCE_ROOT/.nvmrc" "$ROOT_DIR/.nvmrc"
cp "$SOURCE_ROOT/package.json" "$ROOT_DIR/package.json"
cp "$SOURCE_ROOT/package-lock.json" "$ROOT_DIR/package-lock.json"
cp "$SOURCE_ROOT/.config/git/config" "$ROOT_DIR/.config/git/config"
cp "$SOURCE_ROOT/scripts/lib/node.sh" "$ROOT_DIR/scripts/lib/node.sh"
printf 'Host bootstrap-test\n' >"$ROOT_DIR/.ssh/config"
: >"$ROOT_DIR/scripts/tui/welcome/cli.mjs"
for config_dir in git nvim kitty tmux; do
    : >"$ROOT_DIR/.config/$config_dir/.keep"
done

setup_case() {
    local name="$1" installed="${2:-yes}" default_alias="${3:-none}"

    CASE_DIR="$TEST_ROOT/$name"
    CASE_HOME="$CASE_DIR/home"
    CASE_NVM_DIR="$CASE_DIR/nvm"
    CASE_BIN="$CASE_DIR/bin"
    CASE_LOG="$CASE_DIR/nvm.log"
    CASE_STATE="$CASE_DIR/node-installed"
    CASE_NVM_SYMLINK_CURRENT=false
    CASE_BOOTSTRAP_TZ=Etc/UTC
    CASE_BOOTSTRAP_GIT_NAME="Bootstrap Test"
    CASE_BOOTSTRAP_GIT_EMAIL="bootstrap@example.com"
    mkdir -p "$CASE_HOME" "$CASE_NVM_DIR/alias" "$CASE_BIN"
    : >"$CASE_LOG"

    if [ "$installed" = "yes" ]; then
        : >"$CASE_STATE"
    fi
    if [ "$default_alias" != "none" ]; then
        printf '%s\n' "$default_alias" >"$CASE_NVM_DIR/alias/default"
    fi

    cat >"$CASE_BIN/node" <<'SCRIPT'
#!/bin/sh
case "${1:-}" in
    -p)
        printf '24\n'
        ;;
    --version)
        printf 'v24.1.0\n'
        ;;
    *)
        exit 2
        ;;
esac
SCRIPT
    cat >"$CASE_BIN/npm" <<'SCRIPT'
#!/bin/sh
printf 'npm:%s\n' "$*" >>"$FAKE_NVM_LOG"
SCRIPT
    chmod +x "$CASE_BIN/node" "$CASE_BIN/npm"

    cat >"$CASE_NVM_DIR/nvm.sh" <<'SCRIPT'
nvm() {
    printf 'nvm:%s\n' "$*" >>"$FAKE_NVM_LOG"
    case "${1:-}" in
        version)
            if [ -f "$FAKE_NVM_STATE" ]; then
                printf 'v24.1.0\n'
            else
                printf 'N/A\n'
            fi
            ;;
        install)
            : >"$FAKE_NVM_STATE"
            mkdir -p "$NVM_DIR/alias"
            if [ ! -e "$NVM_DIR/alias/default" ] && [ ! -L "$NVM_DIR/alias/default" ]; then
                printf '%s\n' "${2:-}" >"$NVM_DIR/alias/default"
            fi
            ;;
        use)
            [ -f "$FAKE_NVM_STATE" ] || return 3
            if [ "${NVM_SYMLINK_CURRENT:-false}" = "true" ]; then
                rm -f -- "$NVM_DIR/current"
                ln -s "$FAKE_NVM_STATE" "$NVM_DIR/current"
            fi
            PATH="$FAKE_NVM_BIN:$PATH"
            export PATH
            ;;
        *)
            return 91
            ;;
    esac
}
SCRIPT
}

run_bootstrap() {
    PATH="$CASE_BIN:$PATH" \
        HOME="$CASE_HOME" \
        NVM_DIR="$CASE_NVM_DIR" \
        BOOTSTRAP_TZ="$CASE_BOOTSTRAP_TZ" \
        BOOTSTRAP_GIT_NAME="$CASE_BOOTSTRAP_GIT_NAME" \
        BOOTSTRAP_GIT_EMAIL="$CASE_BOOTSTRAP_GIT_EMAIL" \
        FAKE_NVM_BIN="$CASE_BIN" \
        FAKE_NVM_LOG="$CASE_LOG" \
        FAKE_NVM_STATE="$CASE_STATE" \
        NVM_SYMLINK_CURRENT="$CASE_NVM_SYMLINK_CURRENT" \
        BOOTSTRAP_SKIP_SUBMODULES=1 \
        "$ROOT_DIR/bootstrap.sh" "$@"
}

run_bootstrap_with_tty() {
    local command

    printf -v command 'env -u BOOTSTRAP_TZ %q --yes' "$ROOT_DIR/bootstrap.sh"
    PATH="$CASE_BIN:$PATH" \
        HOME="$CASE_HOME" \
        NVM_DIR="$CASE_NVM_DIR" \
        BOOTSTRAP_GIT_NAME="$CASE_BOOTSTRAP_GIT_NAME" \
        BOOTSTRAP_GIT_EMAIL="$CASE_BOOTSTRAP_GIT_EMAIL" \
        FAKE_NVM_BIN="$CASE_BIN" \
        FAKE_NVM_LOG="$CASE_LOG" \
        FAKE_NVM_STATE="$CASE_STATE" \
        FAKE_TZSELECT_LOG="$CASE_DIR/tzselect.log" \
        NVM_SYMLINK_CURRENT="$CASE_NVM_SYMLINK_CURRENT" \
        BOOTSTRAP_SKIP_SUBMODULES=1 \
        script -qec "$command" /dev/null
}

run_bootstrap_git_with_tty() {
    local command

    printf -v command 'env -u BOOTSTRAP_GIT_NAME -u BOOTSTRAP_GIT_EMAIL %q --yes' \
        "$ROOT_DIR/bootstrap.sh"
    PATH="$CASE_BIN:$PATH" \
        HOME="$CASE_HOME" \
        NVM_DIR="$CASE_NVM_DIR" \
        BOOTSTRAP_TZ="$CASE_BOOTSTRAP_TZ" \
        FAKE_NVM_BIN="$CASE_BIN" \
        FAKE_NVM_LOG="$CASE_LOG" \
        FAKE_NVM_STATE="$CASE_STATE" \
        NVM_SYMLINK_CURRENT="$CASE_NVM_SYMLINK_CURRENT" \
        BOOTSTRAP_SKIP_SUBMODULES=1 \
        script -qec "$command" /dev/null
}

assert_no_home_nvmrc() {
    [ ! -e "$CASE_HOME/.nvmrc" ] && [ ! -L "$CASE_HOME/.nvmrc" ]
}

assert_local_config_absent() {
    local temporary

    [ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
    temporary=$(find "$CASE_HOME" -maxdepth 1 -name '.local.sh.*' -print -quit)
    if [ -n "$temporary" ]; then
        printf 'bootstrap left a temporary local configuration: %s\n' "$temporary" >&2
        exit 1
    fi
}

assert_no_managed_home_changes() {
    assert_local_config_absent
    [ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
    [ ! -e "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]
    [ ! -e "$CASE_HOME/.dotfiles-backup" ]
}

if git config --file "$ROOT_DIR/.config/git/config" --get user.name >/dev/null; then
    printf 'public Git config still contains user.name\n' >&2
    exit 1
fi
if git config --file "$ROOT_DIR/.config/git/config" --get user.email >/dev/null; then
    printf 'public Git config still contains user.email\n' >&2
    exit 1
fi
[ "$(git config --file "$ROOT_DIR/.config/git/config" --get include.path)" = \
    '~/.config/git/local' ]
git -C "$SOURCE_ROOT" check-ignore -q .config/git/local

setup_case fresh
CASE_NVM_SYMLINK_CURRENT=true
CASE_BOOTSTRAP_TZ=""
cat >"$CASE_BIN/tzselect" <<'SCRIPT'
#!/bin/sh
printf 'called\n' >>"$FAKE_NVM_LOG.tzselect"
printf 'America/Vancouver\n'
SCRIPT
chmod +x "$CASE_BIN/tzselect"
output=$(run_bootstrap --dry-run)
if grep -Fq '~/.nvmrc' <<<"$output"; then
    printf 'fresh bootstrap still plans a home .nvmrc\n' >&2
    exit 1
fi
grep -Fq "~/.bash_profile -> $ROOT_DIR/.bash_profile" <<<"$output"
grep -Fq 'absent  ~/.profile' <<<"$output"
grep -Fq 'select  ~/local.sh timezone with tzselect during apply' <<<"$output"
grep -Fq 'create  ~/.config/git as a local directory' <<<"$output"
grep -Fq 'create  ~/.config/git/local with the configured Git identity' <<<"$output"
grep -Fq "create  ~/.config/git/config -> $ROOT_DIR/.config/git/config" <<<"$output"
if grep -Fq '~/.profile ->' <<<"$output"; then
    printf 'fresh bootstrap still plans a home .profile link\n' >&2
    exit 1
fi
assert_no_home_nvmrc
assert_local_config_absent
[ ! -e "$CASE_LOG.tzselect" ]
[ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
[ ! -e "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]
[ ! -e "$ROOT_DIR/.config/git/local" ] && [ ! -L "$ROOT_DIR/.config/git/local" ]
[ ! -e "$CASE_NVM_DIR/current" ] && [ ! -L "$CASE_NVM_DIR/current" ]

setup_case absolute_link
ln -s "$ROOT_DIR/.nvmrc" "$CASE_HOME/.nvmrc"
absolute_output=$(run_bootstrap --yes)
if grep -Fq "$CASE_BOOTSTRAP_GIT_NAME" <<<"$absolute_output" \
    || grep -Fq "$CASE_BOOTSTRAP_GIT_EMAIL" <<<"$absolute_output"; then
    printf 'bootstrap printed private Git identity values\n' >&2
    exit 1
fi
[ "$(stat -c '%a' "$CASE_HOME/local.sh")" = "600" ]
grep -Fxq '# Generated by bootstrap.sh for machine-local settings.' "$CASE_HOME/local.sh"
grep -Fxq 'export TZ=Etc/UTC' "$CASE_HOME/local.sh"
timezone_output=$(HOME="$CASE_HOME" TERM=dumb \
    bash --noprofile --rcfile "$ROOT_DIR/.bashrc" -ic 'printf %s "$TZ"' 2>/dev/null)
[ "$timezone_output" = "Etc/UTC" ]
[ -L "$CASE_HOME/.bash_profile" ]
[ "$(readlink "$CASE_HOME/.bash_profile")" = "$ROOT_DIR/.bash_profile" ]
[ -d "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]
[ -L "$CASE_HOME/.config/git/config" ]
[ "$(readlink "$CASE_HOME/.config/git/config")" = "$ROOT_DIR/.config/git/config" ]
[ -f "$CASE_HOME/.config/git/local" ] && [ ! -L "$CASE_HOME/.config/git/local" ]
[ "$(stat -c '%a' "$CASE_HOME/.config/git/local")" = "600" ]
[ "$(git config --file "$CASE_HOME/.config/git/local" --get user.name)" = \
    "$CASE_BOOTSTRAP_GIT_NAME" ]
[ "$(git config --file "$CASE_HOME/.config/git/local" --get user.email)" = \
    "$CASE_BOOTSTRAP_GIT_EMAIL" ]
resolved_git_name=$(HOME="$CASE_HOME" XDG_CONFIG_HOME="$CASE_HOME/.config" \
    GIT_CONFIG_NOSYSTEM=1 git -C "$CASE_HOME" config --get user.name)
resolved_git_email=$(HOME="$CASE_HOME" XDG_CONFIG_HOME="$CASE_HOME/.config" \
    GIT_CONFIG_NOSYSTEM=1 git -C "$CASE_HOME" config --get user.email)
[ "$resolved_git_name" = "$CASE_BOOTSTRAP_GIT_NAME" ]
[ "$resolved_git_email" = "$CASE_BOOTSTRAP_GIT_EMAIL" ]
author_ident=$(env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u EMAIL \
    HOME="$CASE_HOME" XDG_CONFIG_HOME="$CASE_HOME/.config" GIT_CONFIG_NOSYSTEM=1 \
    git -C "$CASE_HOME" var GIT_AUTHOR_IDENT)
[[ "$author_ident" = "$CASE_BOOTSTRAP_GIT_NAME <$CASE_BOOTSTRAP_GIT_EMAIL> "* ]]
[ ! -e "$ROOT_DIR/.config/git/local" ] && [ ! -L "$ROOT_DIR/.config/git/local" ]
[ -L "$CASE_HOME/.nvmrc" ]
[ "$(readlink "$CASE_HOME/.nvmrc")" = "$ROOT_DIR/.nvmrc" ]

setup_case legacy_home_git_identity
printf '[user]\n\tname = Legacy User\n\temail = legacy@example.com\n' \
    >"$CASE_HOME/.gitconfig"
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted an overriding legacy Git identity\n' >&2
    exit 1
fi
grep -Fq '~/.gitconfig defines a Git identity that would override' \
    <<<"$git_identity_error"
[ "$(git config --file "$CASE_HOME/.gitconfig" --get user.name)" = 'Legacy User' ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]
[ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]

setup_case git_identity_required
CASE_BOOTSTRAP_GIT_NAME=""
CASE_BOOTSTRAP_GIT_EMAIL=""
output=$(run_bootstrap --dry-run </dev/null)
grep -Fq 'select  ~/.config/git/local Git identity during apply' <<<"$output"
assert_no_managed_home_changes
if git_identity_error=$(run_bootstrap --yes </dev/null 2>&1); then
    printf 'bootstrap unexpectedly guessed a Git identity non-interactively\n' >&2
    exit 1
fi
grep -Fq 'cannot create ~/.config/git/local non-interactively' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_partial
CASE_BOOTSTRAP_GIT_EMAIL=""
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a partial Git identity\n' >&2
    exit 1
fi
grep -Fq 'set both BOOTSTRAP_GIT_NAME and BOOTSTRAP_GIT_EMAIL' \
    <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_multiline
CASE_BOOTSTRAP_GIT_NAME=$'Bootstrap\nInjected'
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a multiline Git identity\n' >&2
    exit 1
fi
grep -Fq 'must be non-empty single-line values' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_whitespace_name
CASE_BOOTSTRAP_GIT_NAME=$' \t '
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a whitespace-only Git user name\n' >&2
    exit 1
fi
grep -Fq 'Git-usable characters' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_disallowed_name
CASE_BOOTSTRAP_GIT_NAME=',:;<>'
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a disallowed Git user name\n' >&2
    exit 1
fi
grep -Fq 'Git-usable characters' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_quote_name
CASE_BOOTSTRAP_GIT_NAME='""'
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a quote-only Git user name\n' >&2
    exit 1
fi
grep -Fq 'Git-usable characters' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_backslash_name
CASE_BOOTSTRAP_GIT_NAME='\'
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a backslash-only Git user name\n' >&2
    exit 1
fi
grep -Fq 'Git-usable characters' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_whitespace_email
CASE_BOOTSTRAP_GIT_EMAIL=$' \t '
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a whitespace-only Git user email\n' >&2
    exit 1
fi
grep -Fq 'Git-usable characters' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_punctuation_email
CASE_BOOTSTRAP_GIT_EMAIL=':::'
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a punctuation-only Git user email\n' >&2
    exit 1
fi
grep -Fq 'Git-usable characters' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_interactive
CASE_BOOTSTRAP_GIT_NAME=""
CASE_BOOTSTRAP_GIT_EMAIL=""
printf 'Prompted User\nprompted@example.com\n' | run_bootstrap_git_with_tty >/dev/null
[ "$(git config --file "$CASE_HOME/.config/git/local" --get user.name)" = \
    'Prompted User' ]
[ "$(git config --file "$CASE_HOME/.config/git/local" --get user.email)" = \
    'prompted@example.com' ]

setup_case git_identity_prompt_eof
CASE_BOOTSTRAP_GIT_NAME=""
CASE_BOOTSTRAP_GIT_EMAIL=""
if git_identity_error=$(printf 'Prompted User\n' | run_bootstrap_git_with_tty 2>&1); then
    printf 'bootstrap unexpectedly accepted an incomplete Git identity prompt\n' >&2
    exit 1
fi
grep -Fq 'Git user email input ended' <<<"$git_identity_error"
assert_no_managed_home_changes

setup_case git_identity_special_characters
CASE_BOOTSTRAP_GIT_NAME='Tést "Quoted" \\ # ; User'
CASE_BOOTSTRAP_GIT_EMAIL='odd+tag;"quoted"@example.com'
run_bootstrap --yes >/dev/null
[ "$(git config --file "$CASE_HOME/.config/git/local" --get user.name)" = \
    "$CASE_BOOTSTRAP_GIT_NAME" ]
[ "$(git config --file "$CASE_HOME/.config/git/local" --get user.email)" = \
    "$CASE_BOOTSTRAP_GIT_EMAIL" ]

setup_case existing_git_identity
mkdir -p "$CASE_HOME/.config/git"
printf '[user]\n\tname = Existing User\n\temail = existing@example.com\n' \
    >"$CASE_HOME/.config/git/local"
printf 'old managed Git config\n' >"$CASE_HOME/.config/git/config"
printf 'preserve unrelated Git data\n' >"$CASE_HOME/.config/git/credentials"
chmod 640 "$CASE_HOME/.config/git/local"
CASE_BOOTSTRAP_GIT_NAME=""
CASE_BOOTSTRAP_GIT_EMAIL=""
git_identity_before=$(sha256sum "$CASE_HOME/.config/git/local")
run_bootstrap --yes </dev/null >/dev/null
[ "$(sha256sum "$CASE_HOME/.config/git/local")" = "$git_identity_before" ]
[ "$(stat -c '%a' "$CASE_HOME/.config/git/local")" = "640" ]
[ "$(<"$CASE_HOME/.config/git/credentials")" = 'preserve unrelated Git data' ]
[ -L "$CASE_HOME/.config/git/config" ]
old_git_config_backup=$(find "$CASE_HOME/.dotfiles-backup" -type f \
    -path '*/.config/git/config' -print -quit)
[ -n "$old_git_config_backup" ]
[ "$(<"$old_git_config_backup")" = 'old managed Git config' ]

setup_case existing_git_identity_link
mkdir -p "$CASE_HOME/.config/git"
printf '[user]\n\tname = Linked User\n\temail = linked@example.com\n' \
    >"$CASE_DIR/git-identity"
ln -s "$CASE_DIR/git-identity" "$CASE_HOME/.config/git/local"
CASE_BOOTSTRAP_GIT_NAME=""
CASE_BOOTSTRAP_GIT_EMAIL=""
run_bootstrap --yes </dev/null >/dev/null
[ -L "$CASE_HOME/.config/git/local" ]
[ "$(readlink "$CASE_HOME/.config/git/local")" = "$CASE_DIR/git-identity" ]

setup_case invalid_git_identity_target
mkdir -p "$CASE_HOME/.config/git/local"
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a Git identity directory\n' >&2
    exit 1
fi
grep -Fq 'exists but is not a regular file or symlink' <<<"$git_identity_error"
[ -d "$CASE_HOME/.config/git/local" ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]

setup_case invalid_git_config_parent
printf 'not a directory\n' >"$CASE_HOME/.config"
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a non-directory ~/.config\n' >&2
    exit 1
fi
grep -Fq '~/.config exists but is not a directory' <<<"$git_identity_error"
[ "$(<"$CASE_HOME/.config")" = 'not a directory' ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]

setup_case dangling_git_config_parent
ln -s "$CASE_DIR/missing-config-parent" "$CASE_HOME/.config"
if git_identity_error=$(run_bootstrap --yes </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a dangling ~/.config symlink\n' >&2
    exit 1
fi
grep -Fq '~/.config exists but is not a directory' <<<"$git_identity_error"
[ -L "$CASE_HOME/.config" ]
[ "$(readlink "$CASE_HOME/.config")" = "$CASE_DIR/missing-config-parent" ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]

setup_case linked_git_config_ancestor
ln -s "$ROOT_DIR/.config" "$CASE_HOME/.config"
git_source_before=$(sha256sum "$ROOT_DIR/.config/git/config")
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted Git config inside a linked ancestor\n' >&2
    exit 1
fi
grep -Fq 'resolves inside the public dotfiles checkout through a linked ancestor' \
    <<<"$git_identity_error"
[ "$(sha256sum "$ROOT_DIR/.config/git/config")" = "$git_source_before" ]
[ ! -e "$ROOT_DIR/.config/git/local" ] && [ ! -L "$ROOT_DIR/.config/git/local" ]
[ -L "$CASE_HOME/.config" ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]

setup_case foreign_git_config_link
mkdir -p "$CASE_HOME/.config" "$CASE_DIR/foreign-git"
printf 'preserve foreign directory\n' >"$CASE_DIR/foreign-git/sentinel"
ln -s "$CASE_DIR/foreign-git" "$CASE_HOME/.config/git"
run_bootstrap --yes >/dev/null
[ -d "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]
[ "$(<"$CASE_DIR/foreign-git/sentinel")" = 'preserve foreign directory' ]
[ ! -e "$CASE_DIR/foreign-git/local" ]
[ -f "$CASE_HOME/.config/git/local" ]
foreign_git_link_backup=$(find "$CASE_HOME/.dotfiles-backup" -type l \
    -path '*/.config/git' -print -quit)
[ -n "$foreign_git_link_backup" ]
[ "$(readlink "$foreign_git_link_backup")" = "$CASE_DIR/foreign-git" ]

setup_case legacy_git_config_link
mkdir -p "$CASE_HOME/.config"
ln -s "$ROOT_DIR/.config/git" "$CASE_HOME/.config/git"
output=$(run_bootstrap --dry-run)
grep -Fq 'migrate ~/.config/git from a linked directory to a local directory' \
    <<<"$output"
run_bootstrap --yes >/dev/null
[ -d "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]
[ -L "$CASE_HOME/.config/git/config" ]
[ "$(readlink "$CASE_HOME/.config/git/config")" = "$ROOT_DIR/.config/git/config" ]
[ -f "$CASE_HOME/.config/git/local" ]
legacy_git_link_backup=$(find "$CASE_HOME/.dotfiles-backup" -type l \
    -path '*/.config/git' -print -quit)
[ -n "$legacy_git_link_backup" ]
[ "$(readlink "$legacy_git_link_backup")" = "$ROOT_DIR/.config/git" ]
[ ! -e "$ROOT_DIR/.config/git/local" ] && [ ! -L "$ROOT_DIR/.config/git/local" ]

setup_case linked_git_identity_refusal
mkdir -p "$CASE_HOME/.config"
ln -s "$ROOT_DIR/.config/git" "$CASE_HOME/.config/git"
printf '[user]\n\tname = Repo Side User\n\temail = repo-side@example.com\n' \
    >"$ROOT_DIR/.config/git/local"
if git_identity_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted identity inside a linked Git directory\n' >&2
    exit 1
fi
grep -Fq 'is inside a linked Git config directory' <<<"$git_identity_error"
[ -L "$CASE_HOME/.config/git" ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]
rm -f -- "$ROOT_DIR/.config/git/local"

setup_case timezone_required
CASE_BOOTSTRAP_TZ=""
if timezone_error=$(run_bootstrap --yes </dev/null 2>&1); then
    printf 'bootstrap unexpectedly guessed a timezone non-interactively\n' >&2
    exit 1
fi
grep -Fq 'cannot create ~/local.sh non-interactively; set BOOTSTRAP_TZ' \
    <<<"$timezone_error"
assert_no_managed_home_changes

setup_case invalid_timezone
CASE_BOOTSTRAP_TZ="../etc/passwd"
if timezone_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap dry-run unexpectedly accepted an invalid timezone\n' >&2
    exit 1
fi
grep -Fq 'invalid BOOTSTRAP_TZ' <<<"$timezone_error"
assert_no_managed_home_changes
if timezone_error=$(run_bootstrap --yes </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted an invalid timezone\n' >&2
    exit 1
fi
grep -Fq 'invalid BOOTSTRAP_TZ' <<<"$timezone_error"
assert_no_managed_home_changes

setup_case uninstalled_timezone
CASE_BOOTSTRAP_TZ="Bootstrap_Test/Definitely_Missing"
if timezone_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted an uninstalled timezone\n' >&2
    exit 1
fi
grep -Fq 'invalid BOOTSTRAP_TZ' <<<"$timezone_error"
assert_no_managed_home_changes

setup_case invalid_local_config_target
mkdir "$CASE_HOME/local.sh"
if local_config_error=$(run_bootstrap --dry-run </dev/null 2>&1); then
    printf 'bootstrap unexpectedly accepted a local.sh directory\n' >&2
    exit 1
fi
grep -Fq 'exists but is not a regular file or symlink' <<<"$local_config_error"
[ -d "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]

setup_case existing_local_config
printf 'export MACHINE_NAME=test-box\n' >"$CASE_HOME/local.sh"
chmod 640 "$CASE_HOME/local.sh"
CASE_BOOTSTRAP_TZ=""
cat >"$CASE_BIN/tzselect" <<'SCRIPT'
#!/bin/sh
printf 'called\n' >>"$FAKE_NVM_LOG.tzselect"
exit 99
SCRIPT
chmod +x "$CASE_BIN/tzselect"
local_config_before=$(sha256sum "$CASE_HOME/local.sh")
run_bootstrap --yes </dev/null >/dev/null
[ "$(sha256sum "$CASE_HOME/local.sh")" = "$local_config_before" ]
[ "$(stat -c '%a' "$CASE_HOME/local.sh")" = "640" ]
[ ! -e "$CASE_LOG.tzselect" ]
[ -L "$CASE_HOME/.bash_profile" ]

setup_case existing_local_config_link
printf 'export MACHINE_NAME=linked-box\n' >"$CASE_DIR/local-settings"
ln -s "$CASE_DIR/local-settings" "$CASE_HOME/local.sh"
run_bootstrap --yes >/dev/null
[ -L "$CASE_HOME/local.sh" ]
[ "$(readlink "$CASE_HOME/local.sh")" = "$CASE_DIR/local-settings" ]
[ "$(<"$CASE_DIR/local-settings")" = 'export MACHINE_NAME=linked-box' ]

setup_case tzselect_interactive
CASE_BOOTSTRAP_TZ=""
cat >"$CASE_BIN/tzselect" <<'SCRIPT'
#!/bin/sh
printf 'called\n' >>"$FAKE_TZSELECT_LOG"
printf 'America/Vancouver\n'
SCRIPT
chmod +x "$CASE_BIN/tzselect"
: >"$CASE_DIR/tzselect.log"
run_bootstrap_with_tty >/dev/null
[ "$(<"$CASE_DIR/tzselect.log")" = "called" ]
grep -Fxq 'export TZ=America/Vancouver' "$CASE_HOME/local.sh"
[ "$(stat -c '%a' "$CASE_HOME/local.sh")" = "600" ]
[ -L "$CASE_HOME/.bash_profile" ]

setup_case tzselect_failure
CASE_BOOTSTRAP_TZ=""
cat >"$CASE_BIN/tzselect" <<'SCRIPT'
#!/bin/sh
printf 'called\n' >>"$FAKE_TZSELECT_LOG"
exit 23
SCRIPT
chmod +x "$CASE_BIN/tzselect"
: >"$CASE_DIR/tzselect.log"
if timezone_error=$(run_bootstrap_with_tty 2>&1); then
    printf 'bootstrap unexpectedly accepted a failed tzselect command\n' >&2
    exit 1
fi
grep -Fq 'timezone selection failed; ~/local.sh was not created' <<<"$timezone_error"
[ "$(<"$CASE_DIR/tzselect.log")" = "called" ]
assert_no_managed_home_changes

setup_case tzselect_empty
CASE_BOOTSTRAP_TZ=""
cat >"$CASE_BIN/tzselect" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
chmod +x "$CASE_BIN/tzselect"
if timezone_error=$(run_bootstrap_with_tty 2>&1); then
    printf 'bootstrap unexpectedly accepted empty tzselect output\n' >&2
    exit 1
fi
grep -Fq 'tzselect returned an invalid timezone' <<<"$timezone_error"
assert_no_managed_home_changes

setup_case tzselect_multiline
CASE_BOOTSTRAP_TZ=""
cat >"$CASE_BIN/tzselect" <<'SCRIPT'
#!/bin/sh
printf 'America/Vancouver\nEtc/UTC\n'
SCRIPT
chmod +x "$CASE_BIN/tzselect"
if timezone_error=$(run_bootstrap_with_tty 2>&1); then
    printf 'bootstrap unexpectedly accepted multiline tzselect output\n' >&2
    exit 1
fi
grep -Fq 'tzselect returned an invalid timezone' <<<"$timezone_error"
assert_no_managed_home_changes

setup_case tzselect_shell_quoting
CASE_BOOTSTRAP_TZ=""
cat >"$CASE_BIN/tzselect" <<'SCRIPT'
#!/bin/sh
printf '%s\n' 'UTC0;touch "$HOME/tz-injected"'
SCRIPT
chmod +x "$CASE_BIN/tzselect"
run_bootstrap_with_tty >/dev/null
timezone_output=$(HOME="$CASE_HOME" bash --noprofile --norc -c \
    'source "$HOME/local.sh"; printf %s "$TZ"')
[ "$timezone_output" = 'UTC0;touch "$HOME/tz-injected"' ]
[ ! -e "$CASE_HOME/tz-injected" ]

setup_case local_config_directory_race
CASE_BOOTSTRAP_TZ=""
cat >"$CASE_BIN/tzselect" <<'SCRIPT'
#!/bin/sh
mkdir "$HOME/local.sh"
printf 'America/Vancouver\n'
SCRIPT
chmod +x "$CASE_BIN/tzselect"
if local_config_error=$(run_bootstrap_with_tty 2>&1); then
    printf 'bootstrap unexpectedly wrote through a raced local.sh directory\n' >&2
    exit 1
fi
grep -Fq 'exists but is not a regular file or symlink' <<<"$local_config_error"
[ -d "$CASE_HOME/local.sh" ]
[ -z "$(find "$CASE_HOME" -maxdepth 1 -name '.local.sh.*' -print -quit)" ]
[ ! -e "$CASE_HOME/.bash_profile" ] && [ ! -L "$CASE_HOME/.bash_profile" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]

setup_case legacy_profile
printf 'preserve legacy profile\n' >"$CASE_HOME/.profile"
run_bootstrap --yes >/dev/null
[ ! -e "$CASE_HOME/.profile" ] && [ ! -L "$CASE_HOME/.profile" ]
legacy_profile_backup=$(find "$CASE_HOME/.dotfiles-backup" -type f -name .profile -print -quit)
[ -n "$legacy_profile_backup" ]
[ "$(<"$legacy_profile_backup")" = 'preserve legacy profile' ]
[ -L "$CASE_HOME/.bash_profile" ]

setup_case legacy_profile_link
ln -s "$SOURCE_ROOT/.profile" "$CASE_HOME/.profile"
run_bootstrap --yes >/dev/null
[ ! -e "$CASE_HOME/.profile" ] && [ ! -L "$CASE_HOME/.profile" ]
legacy_profile_link_backup=$(find "$CASE_HOME/.dotfiles-backup" -type l -name .profile -print -quit)
[ -n "$legacy_profile_link_backup" ]
[ "$(readlink "$legacy_profile_link_backup")" = "$SOURCE_ROOT/.profile" ]
[ -L "$CASE_HOME/.bash_profile" ]

setup_case relative_link
ln -s "$ROOT_DIR/.nvmrc" "$CASE_DIR/repo-nvmrc"
ln -s ../repo-nvmrc "$CASE_HOME/.nvmrc"
run_bootstrap --yes >/dev/null
[ -L "$CASE_HOME/.nvmrc" ]
[ "$(readlink "$CASE_HOME/.nvmrc")" = ../repo-nvmrc ]

setup_case user_file
printf '22\n' >"$CASE_HOME/.nvmrc"
run_bootstrap --yes >/dev/null
[ "$(<"$CASE_HOME/.nvmrc")" = "22" ]

setup_case other_link
printf '20\n' >"$CASE_DIR/other.nvmrc"
ln -s "$CASE_DIR/other.nvmrc" "$CASE_HOME/.nvmrc"
run_bootstrap --yes >/dev/null
[ -L "$CASE_HOME/.nvmrc" ]
[ "$(readlink "$CASE_HOME/.nvmrc")" = "$CASE_DIR/other.nvmrc" ]

setup_case no_default no
run_bootstrap --yes >/dev/null
assert_no_home_nvmrc
[ -f "$CASE_STATE" ]
[ ! -e "$CASE_NVM_DIR/alias/default" ] && [ ! -L "$CASE_NVM_DIR/alias/default" ]
grep -Fq 'nvm:install 24' "$CASE_LOG"
grep -Fq 'nvm:use 24' "$CASE_LOG"
if grep -Fq 'nvm:alias' "$CASE_LOG"; then
    printf 'bootstrap explicitly changed the nvm default alias\n' >&2
    exit 1
fi

setup_case existing_default no 22
run_bootstrap --yes >/dev/null
[ "$(<"$CASE_NVM_DIR/alias/default")" = "22" ]

run_submodule_bootstrap() {
    local dotfiles_dir="$1"
    shift

    PATH="$CASE_BIN:$PATH" \
        HOME="$CASE_HOME" \
        NVM_DIR="$CASE_NVM_DIR" \
        BOOTSTRAP_TZ="$CASE_BOOTSTRAP_TZ" \
        BOOTSTRAP_GIT_NAME="$CASE_BOOTSTRAP_GIT_NAME" \
        BOOTSTRAP_GIT_EMAIL="$CASE_BOOTSTRAP_GIT_EMAIL" \
        FAKE_NVM_BIN="$CASE_BIN" \
        FAKE_NVM_LOG="$CASE_LOG" \
        FAKE_NVM_STATE="$CASE_STATE" \
        NVM_SYMLINK_CURRENT="$CASE_NVM_SYMLINK_CURRENT" \
        GIT_ALLOW_PROTOCOL=file \
        "$dotfiles_dir/bootstrap.sh" "$@"
}

SUBMODULE_FIXTURE="$TEST_ROOT/submodule-fixture"
SSH_FIXTURE_REPO="$SUBMODULE_FIXTURE/ssh-config"
DOTFILES_FIXTURE_REPO="$SUBMODULE_FIXTURE/dotfiles"
mkdir -p "$SSH_FIXTURE_REPO" "$DOTFILES_FIXTURE_REPO"

git -C "$SSH_FIXTURE_REPO" init -q -b main
printf 'Host private-bootstrap-test\n' >"$SSH_FIXTURE_REPO/config"
git -C "$SSH_FIXTURE_REPO" add config
git -C "$SSH_FIXTURE_REPO" \
    -c user.name='Bootstrap Test' \
    -c user.email='bootstrap@example.com' \
    -c commit.gpgSign=false \
    -c core.hooksPath=/dev/null \
    commit -qm 'Add private SSH config'

cp -R "$ROOT_DIR/." "$DOTFILES_FIXTURE_REPO/"
rm -rf "$DOTFILES_FIXTURE_REPO/.ssh"
git -C "$DOTFILES_FIXTURE_REPO" init -q -b main
git -C "$DOTFILES_FIXTURE_REPO" add .
git -C "$DOTFILES_FIXTURE_REPO" \
    -c user.name='Bootstrap Test' \
    -c user.email='bootstrap@example.com' \
    -c commit.gpgSign=false \
    -c core.hooksPath=/dev/null \
    commit -qm 'Add public dotfiles'
GIT_ALLOW_PROTOCOL=file \
    git -C "$DOTFILES_FIXTURE_REPO" submodule add -q "$SSH_FIXTURE_REPO" .ssh
git -C "$DOTFILES_FIXTURE_REPO" \
    -c user.name='Bootstrap Test' \
    -c user.email='bootstrap@example.com' \
    -c commit.gpgSign=false \
    -c core.hooksPath=/dev/null \
    commit -qam 'Add private SSH submodule'

setup_case private_submodule
PRIVATE_CHECKOUT="$CASE_DIR/dotfiles"
git clone -q --no-recurse-submodules "$DOTFILES_FIXTURE_REPO" "$PRIVATE_CHECKOUT"

output=$(run_submodule_bootstrap "$PRIVATE_CHECKOUT" --dry-run)
grep -Fq 'init    git submodule update --init --recursive' <<<"$output"
[ ! -e "$PRIVATE_CHECKOUT/.ssh/config" ]
[ ! -e "$CASE_HOME/.ssh/config" ] && [ ! -L "$CASE_HOME/.ssh/config" ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]

if refusal_output=$(run_submodule_bootstrap "$PRIVATE_CHECKOUT" </dev/null 2>&1); then
    printf 'bootstrap unexpectedly initialized a private submodule without confirmation\n' >&2
    exit 1
fi
grep -Fq 'refusing to change files without --yes' <<<"$refusal_output"
[ ! -e "$PRIVATE_CHECKOUT/.ssh/config" ]
[ ! -e "$CASE_HOME/.ssh/config" ] && [ ! -L "$CASE_HOME/.ssh/config" ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ ! -e "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]

run_submodule_bootstrap "$PRIVATE_CHECKOUT" --yes >/dev/null 2>&1
[ -f "$PRIVATE_CHECKOUT/.ssh/config" ]
[ -L "$CASE_HOME/.ssh/config" ]
[ "$(readlink "$CASE_HOME/.ssh/config")" = "$PRIVATE_CHECKOUT/.ssh/config" ]
[ -f "$CASE_HOME/local.sh" ]
[ -d "$CASE_HOME/.config/git" ] && [ ! -L "$CASE_HOME/.config/git" ]
[ -L "$CASE_HOME/.config/git/config" ]
[ -f "$CASE_HOME/.config/git/local" ]

setup_case private_submodule_failure
FAILED_PRIVATE_CHECKOUT="$CASE_DIR/dotfiles"
git clone -q --no-recurse-submodules "$DOTFILES_FIXTURE_REPO" "$FAILED_PRIVATE_CHECKOUT"
git -C "$FAILED_PRIVATE_CHECKOUT" \
    config submodule..ssh.url "$CASE_DIR/unavailable-ssh-config"
mkdir -p "$CASE_HOME/.ssh"
printf 'existing ssh config\n' >"$CASE_HOME/.ssh/config"
mkdir -p "$CASE_HOME/.config"
ln -s "$FAILED_PRIVATE_CHECKOUT/.config/git" "$CASE_HOME/.config/git"

if failure_output=$(run_submodule_bootstrap "$FAILED_PRIVATE_CHECKOUT" --yes 2>&1); then
    printf 'bootstrap unexpectedly accepted an unavailable private submodule\n' >&2
    exit 1
fi
grep -Fq 'failed to initialize private .ssh submodule' <<<"$failure_output"
[ -f "$CASE_HOME/.ssh/config" ] && [ ! -L "$CASE_HOME/.ssh/config" ]
[ "$(<"$CASE_HOME/.ssh/config")" = 'existing ssh config' ]
[ ! -e "$CASE_HOME/local.sh" ] && [ ! -L "$CASE_HOME/local.sh" ]
[ -L "$CASE_HOME/.config/git" ]
[ "$(readlink "$CASE_HOME/.config/git")" = "$FAILED_PRIVATE_CHECKOUT/.config/git" ]
[ ! -e "$CASE_HOME/.dotfiles-backup" ]
