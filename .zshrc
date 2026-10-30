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

# One tmux pane per Alliance cluster; answer each Duo prompt with "1" (push).
alliance() {
    local session=alliance
    local -a hosts=(fir narval nibi rorqual trillium-gpu killarney tamia vulcan)
    if ! tmux has-session -t "=$session" 2>/dev/null; then
        local -a rows=($(tmux new-session -d -s "$session" -P -F '#{pane_id}')) panes
        repeat $(( $#hosts / 2 - 1 )); do
            rows+=($(tmux split-window -v -t "$rows[-1]" -P -F '#{pane_id}'))
            # Even out after every split so the next one still has room.
            tmux select-layout -t "$session" even-vertical
        done
        # Halve each row so hosts fill left-to-right, top-to-bottom: 1 2 / 3 4 / 5 6 / 7 8.
        local row i
        for row in $rows; do
            panes+=($row $(tmux split-window -h -t "$row" -P -F '#{pane_id}'))
        done
        for i in {1..$#hosts}; do
            tmux send-keys -t "$panes[i]" "ssh $hosts[i]" Enter
            # Wait for the Duo prompt rather than typing ahead: ssh flushes pending input before
            # reading it, and with a live ControlMaster there is no prompt at all.
            (
                repeat 60; do
                    if tmux capture-pane -p -t "$panes[i]" | grep -q 'Passcode or option'; then
                        tmux send-keys -t "$panes[i]" 1 Enter
                        break
                    fi
                    sleep 0.5
                done
            ) &!
        done
    fi
    if [[ -n $TMUX ]]; then
        tmux switch-client -t "=$session"
    else
        tmux attach -t "=$session"
    fi
}
