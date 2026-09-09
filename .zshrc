export PATH="$HOME/.local/bin:$HOME/.local/nvim-linux-x86_64/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git timer)
source $ZSH/oh-my-zsh.sh
[[ -f "$HOME/dotfiles/local.sh" ]] && source "$HOME/dotfiles/local.sh"
