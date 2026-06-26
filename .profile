# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin
export PATH="$HOME/.local/bin:$PATH"

# Show welcome message for interactive shells, but not inside tmux panes/windows.
case $- in
    *i*)
        if [ -z "$TMUX" ]; then
            . "$HOME/dotfiles/welcome.sh"
        fi
        ;;
esac
