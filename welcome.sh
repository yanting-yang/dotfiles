#!/bin/bash

RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

HR='────────────────────────────────────────────────'

print_latest() {
    local current="$1" latest="$2"
    if [ -n "$latest" ] && [ -n "$current" ] && [ "$latest" != "$current" ]; then
        printf "  latest:  ${YELLOW}%s${NC}\n" "$latest"
    else
        echo "  latest:  ${latest:-unknown}"
    fi
}

get_github_latest() {
    curl -Ls -o /dev/null -w '%{url_effective}' "$1/releases/latest" | xargs basename | sed 's/^v//'
}

check_cmd() {
    local label="$1" cmd="$2" current="$3" latest="$4"
    local path resolved
    echo "=== $label ==="
    if path=$(command -v "$cmd" 2>/dev/null); then
        resolved=$(readlink -f "$path")
        if [ "$resolved" != "$path" ]; then
            echo "  path:    $path -> $resolved"
        else
            echo "  path:    $path"
        fi
        echo "  current: ${current:-unknown}"
        print_latest "$current" "$latest"
    else
        printf "  ${RED}not installed${NC}\n"
    fi
    echo
}

# code (installed directly to $HOME/code, not in PATH)
printf "${BOLD}${CYAN}┌%s┐${NC}\n" "$HR"
printf "${BOLD}${CYAN}│${NC}  %-46s${BOLD}${CYAN}│${NC}\n" "$(whoami)@$(hostname -s)  $(date '+%a %b %d %Y %H:%M')"
printf "${BOLD}${CYAN}└%s┘${NC}\n" "$HR"
echo

# code (installed directly to $HOME/code, not in PATH)
CODE_BIN="$HOME/code"
echo "=== code ==="
if [ -x "$CODE_BIN" ]; then
    CODE_CURRENT=$("$CODE_BIN" --version 2>/dev/null | head -1 | awk '{print $2}')
    CODE_LATEST=$(get_github_latest https://github.com/microsoft/vscode)
    echo "  path:    $CODE_BIN"
    echo "  current: ${CODE_CURRENT:-unknown}"
    print_latest "$CODE_CURRENT" "$CODE_LATEST"
else
    printf "  ${RED}not installed${NC}\n"
fi
echo

# gh
GH_CURRENT=$(gh --version 2>/dev/null | awk 'NR==1{print $3}')
GH_LATEST=$(get_github_latest https://github.com/cli/cli)
check_cmd "gh" "gh" "$GH_CURRENT" "$GH_LATEST"

# nvim
NVIM_CURRENT=$(nvim --version 2>/dev/null | awk 'NR==1{print $2}' | sed 's/^v//')
NVIM_LATEST=$(get_github_latest https://github.com/neovim/neovim)
check_cmd "nvim" "nvim" "$NVIM_CURRENT" "$NVIM_LATEST"

# nvm (shell function, not a binary)
NVM_DIR="${NVM_DIR:-$HOME/.config/nvm}"
echo "=== nvm ==="
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh" --no-use
    NVM_CURRENT=$(nvm --version 2>/dev/null)
    NVM_LATEST=$(cd "$NVM_DIR" && git describe --abbrev=0 --tags --match "v[0-9]*" \
        "$(git rev-list --tags --max-count=1)" 2>/dev/null | sed 's/^v//')
    echo "  path:    $NVM_DIR/nvm.sh (shell function)"
    echo "  current: ${NVM_CURRENT:-unknown}"
    print_latest "$NVM_CURRENT" "$NVM_LATEST"
else
    printf "  ${RED}not installed${NC}\n"
fi
echo

# stow
STOW_CURRENT=$(stow --version 2>/dev/null | grep -oP '[\d.]+' | head -1)
STOW_LATEST=$(curl -s https://ftp.gnu.org/gnu/stow/ \
    | grep -oP 'stow-\K[\d.]+(?=\.tar\.gz)' | sort -V | tail -1)
check_cmd "stow" "stow" "$STOW_CURRENT" "$STOW_LATEST"

# tmux
TMUX_CURRENT=$(tmux -V 2>/dev/null | awk '{print $2}')
TMUX_LATEST=$(get_github_latest https://github.com/tmux/tmux-builds)
check_cmd "tmux" "tmux" "$TMUX_CURRENT" "$TMUX_LATEST"

printf "${BOLD}${CYAN}└%s┘${NC}\n" "$HR"
