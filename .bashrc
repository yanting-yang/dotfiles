# If not running interactively, don't do anything
case $- in
    *i*) ;;
    *) return ;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000
HISTFILE="$HOME/.local/state/bash_history"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# 1. Capture the start time before the command runs
function timer_start() {
    if [ -z "$_cmd_start_time" ]; then
        _cmd_start_time=$SECONDS
    fi
}
trap 'timer_start' DEBUG

# 2. Calculate the duration after the command finishes
function timer_calc() {
    _cmd_duration_str=""

    local delta=$((SECONDS - _cmd_start_time))
    unset _cmd_start_time # Reset the timer in the main shell

    local hours=$((delta / 3600))
    local mins=$(( (delta % 3600) / 60 ))
    local secs=$((delta % 60))

    _cmd_duration_str="["
    (( hours > 0 )) && _cmd_duration_str+="${hours}h "
    (( mins > 0 )) && _cmd_duration_str+="${mins}m "
    _cmd_duration_str+="${secs}s]"
}

# 3. Tell bash to run the calculation right before drawing the prompt
PROMPT_COMMAND="timer_calc; ${PROMPT_COMMAND}"

PS1='${_cmd_duration_str}\n\n${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '

# If this is an xterm set the title to user@host:dir
case "$TERM" in
    xterm* | rxvt*) PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1" ;;
    *) ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
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
export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# cuda
export PATH="/usr/local/cuda/bin:$PATH"

# texlive
export PATH="/usr/local/texlive/2026/bin/x86_64-linux:$PATH"
