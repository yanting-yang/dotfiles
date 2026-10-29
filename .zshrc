export TZ="America/Vancouver"
export PATH="$HOME/.local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
# One completion dump shared by all nodes, instead of a per-host ~/.zcompdump-<host>-<ver>.
ZSH_COMPDUMP="$ZSH/cache/.zcompdump-$ZSH_VERSION"
# Lmod exports FPATH, so nested shells re-prepend omz dirs; dedupe to keep the dump stable.
typeset -U fpath
ZSH_THEME="agnoster"
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
