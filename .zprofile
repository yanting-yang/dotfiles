[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv zsh)"

# Pull dotfiles (the repo this file links into) in the background so login never waits on
# the network, e.g. on offline compute nodes; updates take effect from the next shell.
if [[ -o interactive ]]; then
    GIT_TERMINAL_PROMPT=0 git -C "${${(%):-%x}:A:h}" pull --ff-only --quiet &>/dev/null &!
fi
