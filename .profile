# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin
export PATH="$HOME/.local/bin:$PATH"

# Ask before showing the welcome message for interactive bash shells outside tmux.
case $- in
    *i*)
        if [ -z "$TMUX" ] && [ -n "$BASH_VERSION" ] && [ -t 0 ]; then
            printf 'Show welcome message? [Y/n] '
            if IFS= read -r -t 3 show_welcome; then
                case "$show_welcome" in
                    ''|[Yy]|[Yy][Ee][Ss])
                        . "$HOME/dotfiles/welcome.sh"
                        ;;
                esac
            else
                printf '\n'
            fi
        fi
        ;;
esac
