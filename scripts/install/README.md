# Installers

Each script installs or updates one managed command to the latest version used by this dotfiles setup.

Run an installer directly:

```sh
scripts/install/gh.sh
```

The login welcome TUI also uses these scripts for its install actions.

## LaTeX / TeX Live

`latex.sh` installs the current TeX Live release with `scheme-full` under
`$HOME/texlive/YYYY`, then points `$HOME/texlive/current` at the verified
release. The full scheme needs roughly 10 GB and can take several hours.

The script uses TeX Live's small, checksummed network installer instead of
downloading the multi-gigabyte ISO before installation. It downloads and
extracts into a temporary directory before creating the release directory,
and it leaves older releases and the existing `current` link unchanged if the
new install fails. Welcome retains the final installer error in its result
panel. If TeX Live created `install-tl.log` before failing, the script preserves
it as `$TEXLIVE_ROOT/install-tl-YYYY.failed.log` before removing the incomplete
release.

Set `TEXLIVE_ROOT` to put the versioned installation on another filesystem,
or `TEXLIVE_SCHEME` to choose another supported scheme:

```sh
TEXLIVE_ROOT=/fast/me/texlive scripts/install/latex.sh
TEXLIVE_SCHEME=scheme-small scripts/install/latex.sh
```

Welcome reports annual TeX Live releases. Same-year package maintenance
remains a separate `tlmgr update --self --all` operation.
