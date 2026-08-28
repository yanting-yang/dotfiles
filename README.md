# Dotfiles

Personal dotfiles, shell startup files, installers, and terminal tooling.

## Quick Start

Preview the links and welcome TUI setup:

```sh
./bootstrap.sh --dry-run
```

Apply the links:

```sh
./bootstrap.sh --yes
```

`bootstrap.sh` links the managed dotfiles into `$HOME`, backs up existing targets and
legacy `.profile`, `.lesshst`, `.bash_history`, and `.bash_logout` files under
`$HOME/.dotfiles-backup/`, and prepares the Ink-based welcome TUI. On a new system it
may install or activate nvm/Node and then run `npm ci` in this repository.
The `.ssh` directory is a private submodule, so applying the bootstrap requires
authenticated access to `ssh-config`. A dry run stays offline; after confirmation,
Bootstrap initializes the private submodule before changing managed dotfiles under
`$HOME`. Authenticate the transport used to clone this repository first; for HTTPS,
`gh auth login` followed by `gh auth setup-git` configures Git access.

On the first apply, Bootstrap uses `tzselect` to create a private, machine-local
`~/local.sh` containing `TZ`; `.bashrc` sources that file for interactive shells.
It also asks for the Git user name and email and writes them to the mode-`600`
`~/.config/git/local`, which the public Git config includes. The Git directory in
`$HOME` remains local and only its `config` file is linked to this repository, so the
identity file never resides in the public checkout. Existing `~/local.sh` and
`~/.config/git/local` files or symlinks are preserved; managed link targets retain
Bootstrap's normal backup-and-replace behavior. If a legacy `~/.gitconfig` still
defines `user.name` or `user.email`, Bootstrap stops with a migration message because
Git would read those values last.

For an unattended first apply, provide all local values explicitly:

```sh
BOOTSTRAP_TZ=Etc/UTC \
BOOTSTRAP_GIT_NAME='Example User' \
BOOTSTRAP_GIT_EMAIL='user@example.com' \
./bootstrap.sh --yes
```

The welcome TUI's Node major is pinned in the repository-local `.nvmrc`; Bootstrap
does not link it to `$HOME`. Bootstrap ensures that nvm has a compatible runtime for
the pinned major, installing it when needed. `WELCOME_NODE_VERSION` can select a
specific release within that major. This setup does not change nvm's global default
alias.

The package and lockfile engine ranges are generated mirrors. After changing
`.nvmrc`, synchronize them with:

```sh
npm run sync-node-version
```

## Welcome TUI

Interactive login shells prompt before opening `welcome.sh`. The welcome UI is an
Ink/React terminal app with local-first status checks. It opens in the terminal
alternate screen with a Claude Code-style layout: a bordered welcome/status panel at
the top, working content in the middle, and a fixed input bar at the bottom. While
active, it sets the terminal window title to `Welcome` and restores the previous
title on exit. Before launching the app, `welcome.sh` explicitly runs `nvm use` for
the major pinned in the repository's `.nvmrc`.

Run it manually:

```sh
source ./welcome.sh
```

Useful controls:

- arrows: move the selected tool
- `/`: open the bottom command menu with command descriptions; arrows move the highlighted command, `Enter` runs it, and Backspace on an empty slash prompt returns to action keys
- `/check`: update the current table with remote versions for managed tools; Node is checked through nvm against the latest release of its active major
- `/help`: show slash command help in the transcript
- `Enter`: open the selected tool's action menu; only currently available `Install`, `Update`, and `Uninstall` actions are shown, arrows move the highlighted action, and `Enter` chooses it
- `Esc`: close a transient command or action menu; choosing `Uninstall` opens a confirmation prompt that `Esc` can cancel
- `/exit`: the only way to exit Welcome

Node appears in the normal tool list. Updating it installs and activates the latest
release in the active major through nvm, then removes superseded installations from
that major while preserving installations from other majors.

LaTeX also appears in the managed tool list. Its install action uses TeX Live's
verified network installer for the full scheme, stores releases under
`$HOME/texlive/YYYY`, and selects the completed release through
`$HOME/texlive/current`. Set `TEXLIVE_ROOT` in `local.sh` to use another
filesystem. The action shows live progress because a full installation is roughly
10 GB and may take several hours.

The intentionally supported slash commands are `/check`, `/help`, and `/exit`.
Removed commands and aliases such as `/updates`, `/install`, `/update`, `/quit`,
`/nvm`, `/node`, `/tools`, `/local`, and `/all` should remain unavailable.

## Layout

- `.bash_profile`, `.bashrc`, `welcome.sh`, `bootstrap.sh`: root shell entry points.
- `.nvmrc`: repository-local canonical Node major for the welcome TUI and package metadata.
- `.config/git/config`: public Git configuration; it includes the generated, untracked `~/.config/git/local` identity file.
- `.config/nvim/`, `.config/vim/`, `.config/alacritty/`, `.config/kitty/`, `.config/tmux/`: public managed configuration directories.
- `.ssh/`: private `ssh-config` submodule containing the managed SSH configuration.
- `scripts/lib/`: shared Bash helpers for installers, status checks, and terminal utilities.
- `scripts/install/`: explicit installers for managed tools.
- `scripts/tui/welcome/`: Ink welcome app, slash command metadata, JSON status exporter, and tests.
- `scripts/tui/nvm.sh`: standalone legacy/sourceable Bash NVM TUI helper.

## Development

Install JavaScript dependencies:

```sh
npm ci
```

Run validation:

```sh
npm test
bash -O globstar -n .bash_profile welcome.sh bootstrap.sh scripts/**/*.sh
git diff --check
```

For bootstrap changes, smoke-test with a temporary home:

```sh
tmp_home=$(mktemp -d)
BOOTSTRAP_TZ=Etc/UTC \
BOOTSTRAP_GIT_NAME='Bootstrap Test' \
BOOTSTRAP_GIT_EMAIL='bootstrap@example.com' \
HOME="$tmp_home" ./bootstrap.sh --yes
```

## Safety

Installer scripts may download archives, replace stow packages, or update tool versions.
Remote version checks should stay behind explicit user actions such as `/check` and
NVM remote refresh with `r`. Use `./bootstrap.sh --dry-run` before linking real dotfiles.
