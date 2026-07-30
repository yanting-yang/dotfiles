# TUIs

Terminal interfaces for managing tools after the dotfiles shell environment has loaded.

`nvm.sh` manages installed and remote Node versions through nvm. It opens with local
versions only; press `r` when you want to fetch remote versions.

```sh
source scripts/tui/nvm.sh
run_nvm_tui
```

Source it when you want `nvm use` to persist in the current shell. If run directly,
its back action opens the welcome TUI.

Controls:

- `Enter`: use an installed version, or install and use an available remote version
- `i`: install by typing a version or alias, defaulting to `lts/*`
- `d`: uninstall the selected installed version
- `r`: refresh installed versions and load remote versions with `nvm ls-remote`

The `lts` column shows the LTS codename when `nvm ls-remote --lts` reports one.
