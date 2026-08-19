# If not running interactively, don't do anything
case $- in
    *i*) ;;
    *) return ;;
esac

timer_calc() {
    [[ -v _cmd_start ]] || return 0

    local delta=$((SECONDS - _cmd_start))
    unset _cmd_start

    printf '['
    (( delta >= 3600 )) && printf '%dh ' "$((delta / 3600))"
    (( delta >= 60 ))   && printf '%dm ' "$((delta % 3600 / 60))"
    printf '%ds]\n\n' "$((delta % 60))"
}

# optional shell behavior
shopt -s histappend # append to the history file, don't overwrite it

# shell variables
HISTCONTROL=ignoreboth  # ignore lines starting with space and duplicates
HISTFILE="$HOME/.local/state/bash_history"
HISTFILESIZE=2000
HISTSIZE=1000
PROMPT_COMMAND="timer_calc; ${PROMPT_COMMAND}"
PS0='${BASH_VERSION:0:$((_cmd_start=SECONDS, 0))}'
PS1='\u@\h:\w\$ '

# If this is an xterm set the title to user@host:dir
case "$TERM" in
    xterm* | rxvt*) PS1="\[\e]0;\u@\h:\w\a\]$PS1" ;;
    *) ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    export LS_COLORS="${LS_COLORS}:or=01;31:mi=01;31"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# nvm
NVM_DIR="$HOME/.config/nvm"
[ -d "$NVM_DIR" ] && export NVM_DIR
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# cuda
CUDA_PATH="/usr/local/cuda/bin"
[ -d "$CUDA_PATH" ] && export PATH="$CUDA_PATH:$PATH"

# texlive
TEXLIVE_PATH="/usr/local/texlive/2026/bin/x86_64-linux"
[ -d "$TEXLIVE_PATH" ] && export PATH="$TEXLIVE_PATH:$PATH"
TEXLIVE_PATH="$HOME/texlive/2026/bin/x86_64-linux"
[ -d "$TEXLIVE_PATH" ] && export PATH="$TEXLIVE_PATH:$PATH"

export LESSHISTFILE="$HOME/.local/state/lesshst"
export TZ="America/Vancouver"
