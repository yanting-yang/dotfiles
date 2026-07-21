# If not running interactively, don't do anything
case $- in
    *i*) ;;
    *) return ;;
esac

shopt -s histappend # append to the history file, don't overwrite it

HISTCONTROL=ignoreboth  # ignore lines starting with space and duplicates
HISTFILE="$HOME/.local/state/bash_history"
HISTFILESIZE=2000
HISTSIZE=1000

# Record when each command starts, without a DEBUG trap. PS0 (bash 4.4+) is
# expanded once, right after a command line is read but just before it runs.
#
# Dissecting PS0='${_ps0:0:$((_cmd_start=SECONDS, _cmd_run=1, 0))}':
#   ${_ps0:0:N}  substring of _ps0 (empty) at offset 0, length N -> expands to
#                nothing; it exists only to host the arithmetic in the length.
#   $(( ... ))   arithmetic runs in THIS shell (unlike $(...), a subshell), so
#                its assignments persist. The comma operator runs each in turn:
#                  _cmd_start=SECONDS  remember when the command started
#                  _cmd_run=1          flag that a command actually ran
#                                      (an empty Enter never expands PS0)
#                  0                   the value used as the substring length
# _ps0 must stay set (even empty): bash skips the substring's length arithmetic
# when the base variable is unset, which would drop the side effect entirely.
_ps0=
PS0='${_ps0:0:$((_cmd_start=SECONDS, _cmd_run=1, 0))}'

# Format the elapsed time right before drawing the next prompt.
function timer_calc() {
    [ -n "$_cmd_run" ] || { _cmd_duration_str=""; return; }
    _cmd_run=

    local delta=$((SECONDS - _cmd_start))
    _cmd_duration_str="["
    (( delta >= 3600 )) && _cmd_duration_str+="$((delta / 3600))h "
    (( delta >= 60 ))   && _cmd_duration_str+="$((delta % 3600 / 60))m "
    # Trailing newlines live here, not in PS1, so an empty Enter stays compact.
    _cmd_duration_str+="$((delta % 60))s]"$'\n\n'
}
PROMPT_COMMAND="timer_calc; ${PROMPT_COMMAND}"

PS1='${_cmd_duration_str}\u@\h:\w\$ '

# If this is an xterm set the title to user@host:dir
case "$TERM" in
    xterm* | rxvt*) PS1="\[\e]0;\u@\h: \w\a\]$PS1" ;;
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
