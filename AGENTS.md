# Repository Guidelines

## Project Structure & Module Organization

This repository manages personal dotfiles and shell tooling.

- Root shell entry points: `.profile`, `.bashrc`, `bootstrap.sh`, `welcome.sh`; the repository-local `.nvmrc` pins the welcome TUI's Node major and is not linked into `$HOME`.
- Configuration files: `.config/git/`, `.config/nvim/`, `.config/vim/`, `.config/alacritty/`, `.config/kitty/`, `.config/tmux/`, `.ssh/config`.
- Shared helpers: `scripts/lib/install.sh` for installer primitives, `scripts/lib/tui.sh` for terminal UI helpers, `scripts/lib/tool_status.sh` for welcome status rows, and `scripts/lib/code.sh` for Code-running detection.
- Installers: `scripts/install/*.sh`, which should do preflight checks and download/extract into temporary directories before mutating managed locations.
- Welcome TUI: `scripts/tui/welcome/` contains the Ink/React app, JSON status exporter, action helpers, and tests. `welcome.sh` is the sourceable Bash bridge that launches Ink and applies mutating actions in the parent shell.
- Terminal interfaces: `scripts/tui/*.sh`; `scripts/tui/nvm.sh` is the legacy/sourceable Node version helper and opens local-first until remote versions are requested.
- Installer/TUI notes live beside the scripts in `scripts/install/README.md` and `scripts/tui/README.md`.

Welcome tests live beside the TUI implementation, and `scripts/bootstrap.test.sh` covers bootstrap migrations/runtime setup. General validation is done with `npm test`, shell syntax checks, and focused smoke tests.

## Build, Test, and Development Commands

- `npm ci`: install the pinned Ink/React dependencies for the welcome TUI.
- `npm test`: run Ink rendering/state tests and shell bridge smoke tests.
- `bash -O globstar -n .profile welcome.sh bootstrap.sh scripts/**/*.sh`: syntax-check shell scripts before committing.
- `git diff --check`: detect whitespace errors.
- `source ./welcome.sh`: manually open the welcome TUI in an interactive shell.
- `node scripts/tui/welcome/cli.mjs`: run the welcome status path directly; non-TTY output prints a plain summary.
- `source scripts/tui/nvm.sh; run_nvm_tui`: run the legacy/sourceable NVM TUI in the current shell.
- `./bootstrap.sh --dry-run`: preview dotfile links without changing `$HOME`.
- `./bootstrap.sh --yes`: link dotfiles into `$HOME`, ensure nvm has the Node major pinned by the repository-local `.nvmrc` without changing nvm's default alias, and run `npm ci`; `.nvmrc` itself is not linked into `$HOME`, and existing link targets are backed up under `$HOME/.dotfiles-backup/`.

## Coding Style & Naming Conventions

Use Bash for shell tools. Prefer `#!/usr/bin/env bash` for executable scripts and `#!/bin/bash` only when already established. Use 4-space indentation, lowercase snake_case function names, and uppercase globals/constants such as `NVM_TUI_CURRENT`. Keep functions small and avoid hidden network calls during shell startup. Put shared installer behavior in `scripts/lib/install.sh`, shared terminal rendering/input in `scripts/lib/tui.sh`, and welcome status behavior in `scripts/lib/tool_status.sh` instead of duplicating it.

Use ESM `.mjs` for the Ink app under `scripts/tui/welcome/`. Keep React components small, use plain `React.createElement` unless the repo adds a transpile step, and keep mutating actions behind `welcome.sh` action files so `nvm use` can affect the parent shell. Before each welcome launch, explicitly use nvm to select the major pinned in the repository-local `.nvmrc`.

The welcome UI should stay close to Claude Code's terminal shape: alternate full-screen buffer, fixed terminal window title `Welcome` while active, bordered top welcome/status panel, middle content area, command menu above a fixed bottom input bar. The top panel must show the available tool action keys as aligned key and description columns, plus slash-command picker keys while `/` mode is active. Tool and slash-command selection must use arrow keys only; do not add `j`/`k` navigation. `/check` must update the current tool table in place without introducing a back level. Only `/exit` exits Welcome; normal-mode `q` and `Esc` must not exit or reset the table. Esc may still cancel a transient slash menu or uninstall prompt. Node stays in the normal managed-tool list; do not add a separate Node-version screen. Typing `/` must show all available slash commands with descriptions; arrows move the highlighted command and `Enter` runs it. Keep supported slash commands limited to `/check`, `/help`, and `/exit`; do not reintroduce `/updates`, `/install`, `/update`, `/quit`, `/nvm`, `/node`, `/tools`, `/local`, or `/all` aliases.

## Testing Guidelines

Run `npm test`, `bash -O globstar -n .profile welcome.sh bootstrap.sh scripts/**/*.sh`, and `git diff --check` for every change. For TUI changes, test interactively with harmless stubs where possible, for example overriding `curl`, installers, or `nvm` in a subshell to avoid real downloads, installs, or version switches. Verify both TTY and non-TTY paths when changing display logic, verify the tools view shows its action keys, verify the fixed terminal title is set/restored, and verify the `/` command menu renders at the bottom with descriptions plus working arrow/Enter selection. For bootstrap changes, smoke-test `--dry-run` and `--yes` with a temporary `HOME`.

## Commit & Pull Request Guidelines

Recent commits use short imperative summaries, for example `Add nvm TUI navigation` and `Prompt before showing welcome message`. Keep commit titles concise and focused. Pull requests should describe behavior changes, list validation commands run, and call out any installer, network, or dotfile-linking side effects. Include terminal screenshots or copied TUI output when changing interactive flows.

## Safety & Configuration Tips

Do not run installer scripts casually; they may download archives, replace stow packages, install Node/npm packages, or update tool versions. Keep installer network access behind explicit commands and avoid mutating install targets until downloads/extractions have succeeded. Preserve the fast local welcome and NVM paths: network checks should stay behind explicit commands such as `/check` and NVM remote refresh with `r`. Use `bootstrap.sh --dry-run` before linking real dotfiles, and keep its backup behavior intact. `bootstrap.sh --yes` may install nvm/Node and run `npm ci` so the welcome TUI works on a fresh system.
