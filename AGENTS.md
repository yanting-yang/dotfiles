# Repository Guidelines

## Project Structure & Module Organization

This repository manages personal dotfiles and shell tooling.

- Root shell entry points: `.profile`, `.bashrc`, `bootstrap.sh`, `welcome.sh`.
- Configuration files: `.config/git/`, `.config/nvim/`, `.config/vim/`, `.config/alacritty/`, `.ssh/config`.
- Shared helpers: `scripts/lib/install.sh` for installer primitives, `scripts/lib/tui.sh` for terminal UI helpers, `scripts/lib/tool_status.sh` for welcome status rows, and `scripts/lib/code.sh` for Code-running detection.
- Installers: `scripts/install/*.sh`, which should do preflight checks and download/extract into temporary directories before mutating managed locations.
- Terminal interfaces: `scripts/tui/*.sh`; `scripts/tui/nvm.sh` is the second-level Node version manager and opens local-first until remote versions are requested.
- Installer/TUI notes live beside the scripts in `scripts/install/README.md` and `scripts/tui/README.md`.

There is no formal test directory; validation is done with shell syntax checks and focused smoke tests.

## Build, Test, and Development Commands

- `bash -n .profile welcome.sh bootstrap.sh scripts/**/*.sh`: syntax-check shell scripts before committing.
- `git diff --check`: detect whitespace errors.
- `source ./welcome.sh`: manually open the welcome TUI in an interactive shell.
- `source scripts/tui/nvm.sh; run_nvm_tui`: run the NVM TUI in the current shell so `nvm use` persists.
- `./bootstrap.sh --dry-run`: preview dotfile links without changing `$HOME`.
- `./bootstrap.sh --yes`: link dotfiles into `$HOME`; existing targets are backed up under `$HOME/.dotfiles-backup/`.

## Coding Style & Naming Conventions

Use Bash for shell tools. Prefer `#!/usr/bin/env bash` for executable scripts and `#!/bin/bash` only when already established. Use 4-space indentation, lowercase snake_case function names, and uppercase globals/constants such as `NVM_TUI_CURRENT`. Keep functions small and avoid hidden network calls during shell startup. Put shared installer behavior in `scripts/lib/install.sh`, shared terminal rendering/input in `scripts/lib/tui.sh`, and welcome status behavior in `scripts/lib/tool_status.sh` instead of duplicating it.

## Testing Guidelines

Run `bash -n` and `git diff --check` for every change. For TUI changes, test interactively with harmless stubs where possible, for example overriding `curl` or `nvm` in a subshell to avoid real downloads, installs, or version switches. Verify both TTY and non-TTY fallback paths when changing display logic. For bootstrap changes, smoke-test `--dry-run` and `--yes` with a temporary `HOME`.

## Commit & Pull Request Guidelines

Recent commits use short imperative summaries, for example `Add nvm TUI navigation` and `Prompt before showing welcome message`. Keep commit titles concise and focused. Pull requests should describe behavior changes, list validation commands run, and call out any installer, network, or dotfile-linking side effects. Include terminal screenshots or copied TUI output when changing interactive flows.

## Safety & Configuration Tips

Do not run installer scripts casually; they may download archives, replace stow packages, or update tool versions. Keep installer network access behind explicit commands and avoid mutating install targets until downloads/extractions have succeeded. Preserve the fast local welcome and NVM paths: network checks should stay behind explicit commands such as `/updates` and NVM remote refresh with `r`. Use `bootstrap.sh --dry-run` before linking real dotfiles, and keep its backup behavior intact.
