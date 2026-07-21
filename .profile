# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin
export PATH="$HOME/.local/bin:$PATH"

# Provide a `welcome` command to show the welcome message on demand.
# Sourced so mutating actions (e.g. nvm use) can affect the parent shell.
case $- in
    *i*)
        if [ -n "$BASH_VERSION" ]; then
            welcome() {
                . "$HOME/dotfiles/welcome.sh"
            }
            if [ -z "$TMUX" ] && [ -t 0 ]; then
                printf 'Run `welcome` to show the welcome message.\n'
            fi
        fi
        ;;
esac
