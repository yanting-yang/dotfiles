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

`bootstrap.sh` links the managed dotfiles into `$HOME`, backs up existing targets under
`$HOME/.dotfiles-backup/`, and prepares the Ink-based welcome TUI. On a new system it
may install or activate nvm/Node and then run `npm ci` in this repository.

The welcome TUI requires Node `>=22`. Bootstrap installs Node `24` through nvm when a
compatible Node/npm pair is not already available. Override that with:

```sh
WELCOME_NODE_VERSION=22 ./bootstrap.sh --yes
```

## Welcome TUI

Interactive login shells prompt before opening `welcome.sh`. The welcome UI is an
Ink/React terminal app with local-first status checks. It opens in the terminal
alternate screen with a Claude Code-style layout: a bordered welcome/status panel at
the top, working content in the middle, and a fixed input bar at the bottom.

Run it manually:

```sh
source ./welcome.sh
```

Useful controls:

- `j/k` or arrows: move selection
- `Enter`: run the selected action
- `/`: open the bottom command menu with command descriptions
- `/nvm`: open Node versions
- `/updates` or `/check`: check remote versions for managed tools
- `/install` or `/update`: install or update the selected actionable tool
- `/help`: show slash command help in the transcript
- `r`: refresh local tool status, or load remote Node versions inside NVM
- `/quit`, `/exit`, or `q`: exit

NVM actions are applied through the `welcome.sh` Bash bridge so `nvm use` affects the
current shell.

The intentionally supported slash commands are `/nvm`, `/updates`, `/check`,
`/install`, `/update`, `/help`, `/quit`, and `/exit`. Removed aliases such as
`/node`, `/tools`, `/local`, and `/all` should remain unavailable.

## Layout

- `.profile`, `.bashrc`, `welcome.sh`, `bootstrap.sh`: root shell entry points.
- `.config/git/`, `.config/nvim/`, `.config/vim/`, `.config/alacritty/`, `.ssh/config`: managed configuration.
- `scripts/lib/`: shared Bash helpers for installers, status checks, and terminal utilities.
- `scripts/install/`: explicit installers for managed tools.
- `scripts/tui/welcome/`: Ink welcome app, slash command metadata, JSON status exporter, and tests.
- `scripts/tui/nvm.sh`: legacy/sourceable Bash NVM TUI helper used by the exporter.

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
