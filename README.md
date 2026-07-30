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
legacy `.lesshst`, `.bash_history`, and `.bash_logout` files under
`$HOME/.dotfiles-backup/`, and prepares the Ink-based welcome TUI. On a new system it
may install or activate nvm/Node and then run `npm ci` in this repository.

The welcome TUI's Node major is pinned in `.nvmrc`. Bootstrap links that file to
`$HOME/.nvmrc` and installs the pinned major through nvm when a compatible Node/npm
pair is not already available. `WELCOME_NODE_VERSION` can select a specific release
within the pinned major.

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
title on exit.

Run it manually:

```sh
source ./welcome.sh
```

Useful controls:

- `j/k` or arrows: move the selected tool
- `/`: open the bottom command menu with command descriptions; arrows move the highlighted command, `Enter` runs it, and Backspace on an empty slash prompt returns to action keys
- `/updates` or `/check`: check remote versions for managed tools; Node is checked through nvm against the latest release of its active major
- `/install` or `/update`: install or update the selected actionable tool
- `/help`: show slash command help in the transcript
- `Enter` installs or updates the selected tool, `d`/`x` uninstalls the selected managed tool, `r` refreshes local tool status, and `q`/`Esc` returns to local status or exits
- `/quit` or `/exit`: exit from the slash command menu

Node appears in the normal tool list. Updating it installs and activates the latest
release in the active major through nvm, then removes superseded installations from
that major while preserving installations from other majors.

The intentionally supported slash commands are `/updates`, `/check`, `/install`,
`/update`, `/help`, `/quit`, and `/exit`. Removed commands and aliases such as
`/nvm`, `/node`, `/tools`, `/local`, and `/all` should remain unavailable.

## Layout

- `.profile`, `.bashrc`, `welcome.sh`, `bootstrap.sh`: root shell entry points.
- `.nvmrc`: canonical Node major, managed as `$HOME/.nvmrc`.
- `.config/git/`, `.config/nvim/`, `.config/vim/`, `.config/alacritty/`, `.ssh/config`: managed configuration.
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
bash -O globstar -n .profile welcome.sh bootstrap.sh scripts/**/*.sh
git diff --check
```

For bootstrap changes, smoke-test with a temporary home:

```sh
tmp_home=$(mktemp -d)
HOME="$tmp_home" ./bootstrap.sh --yes
```

## Safety

Installer scripts may download archives, replace stow packages, or update tool versions.
Remote version checks should stay behind explicit user actions such as `/updates` and
NVM remote refresh with `r`. Use `./bootstrap.sh --dry-run` before linking real dotfiles.
