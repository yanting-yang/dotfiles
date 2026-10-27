export TZ="America/Vancouver"
export PATH="$HOME/.local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(ssh timer)
source $ZSH/oh-my-zsh.sh

ssht() {
    command ssh "$@"
    local rc=$?
    printf '\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l' > /dev/tty
    return "$rc"
}
compdef ssht=ssh
alias ssh='ssht'
