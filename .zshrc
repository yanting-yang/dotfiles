export TZ="America/Vancouver"
export PATH="$HOME/.local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"

# One completion dump shared by all nodes, instead of a per-host ~/.zcompdump-<host>-<ver>.
ZSH_COMPDUMP="$ZSH/cache/.zcompdump-$ZSH_VERSION"
# Lmod exports FPATH, so nested shells re-prepend omz dirs; dedupe to keep the dump stable.
typeset -U fpath

ZSH_THEME="agnoster"
plugins=(ssh timer)
zstyle ':omz:update' mode auto
source $ZSH/oh-my-zsh.sh

# Lead the prompt with the Slurm cluster name, since login nodes everywhere are named like login01.
# Exported so nested shells (tmux, srun) skip the scontrol call.
if (( $+commands[scontrol] )); then
    export CLUSTER_NAME=${CLUSTER_NAME:-${"$(scontrol show config 2>/dev/null | grep '^ClusterName')"##* }}
    [[ -n $CLUSTER_NAME ]] && PROMPT="%K{magenta}%F{black} $CLUSTER_NAME %k%F{magenta}"$'\ue0b0'"%f$PROMPT"
fi

ssht() {
    command ssh "$@"
    local rc=$?
    printf '\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l' > /dev/tty
    return "$rc"
}
compdef ssht=ssh
alias ssh='ssht'

# One tmux pane per Alliance cluster, four to a window, plus a window running sqtop;
# answer each Duo prompt with "1" (push). Pane titles carry each cluster's state from
# status.alliancecan.ca, and clusters that are down or decommissioned are not connected to.
alliance() {
    local session=alliance url=https://status.alliancecan.ca
    local -a hosts=(fir narval nibi rorqual trillium-gpu killarney tamia vulcan)
    if ! tmux has-session -t "=$session" 2>/dev/null; then
        # The status site has no API: scrape the Material icon name in each service's row of the
        # front-page table, and give the services listed on /retired the Decommissioned one.
        local -A state
        local name icon
        curl -fsS --connect-timeout 3 -m 5 $url $url/retired 2>/dev/null | awk '
            /Decommissioned Date/ { retired = 1 }
            match($0, /<a href="\/system\/[^"]+">/) {
                name = tolower(substr($0, RSTART + 17, RLENGTH - 19))
                if (retired) { print name "\tpower_off"; name = "" }
            }
            name != "" && /material-icons/ { gsub(/.*">|<\/i>.*/, ""); print name "\t" $0; name = "" }
        ' | while IFS=$'\t' read -r name icon; do state[$name]=$icon; done
        # Nerd Font glyphs, keyed by the site's icon for each state.
        local -A glyph=(
            check         $'\U000f012c'  # Operational
            warning_amber $'\U000f002a'  # Available with conditions
            event         $'\U000f00ed'  # Scheduled events
            cloud_off     $'\U000f0164'  # Outage
            power_off     $'\U000f06a6'  # Decommissioned
            unknown       $'\U000f02d6'  # not reported, or the site is unreachable
        )
        local -a panes=($(tmux new-session -d -s "$session" -P -F '#{pane_id}'))
        local i
        for i in {2..$#hosts}; do
            if (( i % 4 == 1 )); then
                panes+=($(tmux new-window -d -t "$session:" -P -F '#{pane_id}'))
            else
                panes+=($(tmux split-window -t "$panes[-1]" -P -F '#{pane_id}'))
                # Tile after every split: it leaves room for the next one, and four tiled panes
                # sit left-to-right, top-to-bottom in host order: 0 1 / 2 3.
                tmux select-layout -t "$panes[-1]" tiled
            fi
        done
        for i in {1..$#hosts}; do
            # trillium-gpu is listed as Trillium.
            icon=$state[${hosts[i]%%-*}]
            # Title the pane with its state and host, and lock it: oh-my-zsh, here and on the
            # cluster, otherwise retitles the pane at every prompt.
            tmux set-option -p -t "$panes[i]" allow-set-title off
            tmux select-pane -t "$panes[i]" -T "${glyph[$icon]:-$glyph[unknown]} $hosts[i]"
            [[ $icon == (cloud_off|power_off) ]] && continue
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
        # sqtop never prompts for MFA; its remote tabs reuse the ssh connections opened above.
        tmux send-keys -t "$(tmux new-window -d -t "$session:" -P -F '#{pane_id}')" 'uvx sqtop' Enter
    fi
    if [[ -n $TMUX ]]; then
        tmux switch-client -t "=$session"
    else
        tmux attach -t "=$session"
    fi
}
