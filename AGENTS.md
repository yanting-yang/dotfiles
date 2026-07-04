# Repository Guidelines

## Project Structure & Module Organization

This repository manages personal dotfiles and shell tooling.

- Root shell entry points: `.profile`, `.bashrc`, `bootstrap.sh`, `welcome.sh`.
- Configuration files: `.config/git/`, `.config/nvim/`, `.config/vim/`, `.config/alacritty/`, `.ssh/config`.
- Installers: `scripts/install/*.sh`, with shared helpers in `scripts/lib/install.sh`.
- Terminal interfaces: `scripts/tui/*.sh`; `scripts/tui/nvm.sh` is the second-level Node version manager.
- Installer/TUI notes live beside the scripts in `scripts/install/README.md` and `scripts/tui/README.md`.

There is no formal test directory; validation is done with shell syntax checks and focused smoke tests.

## Build, Test, and Development Commands

- `bash -n .profile welcome.sh scripts/**/*.sh`: syntax-check shell scripts before committing.
- `git diff --check`: detect whitespace errors.
- `source ./welcome.sh`: manually open the welcome TUI in an interactive shell.
- `source scripts/tui/nvm.sh; run_nvm_tui`: run the NVM TUI in the current shell so `nvm use` persists.
- `./bootstrap.sh`: link dotfiles into `$HOME`; review changes before running because it replaces existing links/files.

## Coding Style & Naming Conventions

Use Bash for shell tools. Prefer `#!/usr/bin/env bash` for executable scripts and `#!/bin/bash` only when already established. Use 4-space indentation, lowercase snake_case function names, and uppercase globals/constants such as `NVM_TUI_CURRENT`. Keep functions small and avoid hidden network calls during shell startup. Put shared installer behavior in `scripts/lib/install.sh` instead of duplicating it.

## Testing Guidelines

Run `bash -n` and `git diff --check` for every change. For TUI changes, test interactively with harmless stubs where possible, for example overriding `curl` or `nvm` in a subshell to avoid real downloads, installs, or version switches. Verify both TTY and non-TTY fallback paths when changing display logic.

## Commit & Pull Request Guidelines

Recent commits use short imperative summaries, for example `Add nvm TUI navigation` and `Prompt before showing welcome message`. Keep commit titles concise and focused. Pull requests should describe behavior changes, list validation commands run, and call out any installer, network, or dotfile-linking side effects. Include terminal screenshots or copied TUI output when changing interactive flows.

## Safety & Configuration Tips

Do not run installer scripts casually; they may download archives, replace stow packages, or update tool versions. Avoid destructive file operations in `bootstrap.sh` without explicit review. Preserve the fast local welcome path: network checks should stay behind explicit commands such as `/updates`.
