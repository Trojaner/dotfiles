#!/bin/sh
PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
export PATH
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
dir=$(dirname "$self")
cmd=$1
shift

case $cmd in
list)
  client=$1
  current=$(tmux list-clients -F '#{client_name}|#{session_id}' | awk -F '|' -v c="$client" '$1 == c { print $2; exit }')
  tmux list-sessions -F '#{@tab_index}	#{session_id}	#{?@permanent,1,0}	#{?#{E:@tab_bell},1,0}	#{E:@tab_name}' | sort -n -t '	' -k 1,1 |
    while IFS='	' read -r n id pin bell name; do
      if [ "$id" = "$current" ]; then
        lead='\033[38;2;255;121;198m▸\033[0m'
        style='\033[1;38;2;248;248;242m'
      else
        lead=' '
        style='\033[38;2;248;248;242m'
      fi
      marks=
      [ "$pin" = 1 ] && marks="$marks \033[38;2;255;184;108m󰐃\033[0m"
      [ "$bell" = 1 ] && marks="$marks \033[38;2;241;250;140m󰂞\033[0m"
      printf '%s\t%b \033[38;2;189;147;249m%2s\033[0m  %b%s\033[0m%b\n' "$id" "$lead" "$n" "$style" "$name" "$marks"
    done
  ;;
go)
  tmux switch-client -c "$1" -t "$2"
  ;;
jump)
  exec "$dir/vscode-goto.sh" "$1" "$2"
  ;;
pin)
  client=$1 id=$2
  if [ -n "$(tmux show -t "$id" -v @permanent 2>/dev/null)" ]; then
    tmux set -t "$id" -u @permanent \; set -t "$id" @owner "$client"
  else
    tmux set -t "$id" @permanent 1
  fi
  tmux refresh-client -S -t "$client"
  ;;
close)
  id=$1
  label=$(tmux display -p -t "$id" '#{@tab_index} #{E:@tab_name}')
  printf '\n  \033[38;2;255;85;85mClose tab %s?\033[0m (y/n) ' "$label"
  answer=$(bash -c 'read -rsn1 a; printf %s "$a"')
  case $answer in
  y | Y)
    tmux kill-session -t "$id"
    "$dir/vscode-renumber.sh"
    ;;
  esac
  ;;
rename)
  id=$1
  name=$(tmux display -p -t "$id" '#{s/^[0-9]+$//:session_name}')
  new=$(: | fzf --query "$name" --prompt '  Rename tab: ' --no-info --no-separator --layout=reverse \
    --bind 'enter:print-query' \
    --color='bg:#282a36,fg:#f8f8f2,prompt:#bd93f9:bold,query:#f8f8f2') || exit 0
  [ -n "$new" ] && tmux rename-session -t "$id" -- "$new" && tmux refresh-client -S
  ;;
move)
  id=$1 step=$2 state=$3
  set --
  for x in $(tmux list-sessions -F '#{?@tab_order,#{@tab_order},999999} #{s/[$]//:session_id} #{session_id}' | sort -n -k1,1 -k2,2 | awk -v id="$id" -v step="$step" '
    { ids[NR] = $3; if ($3 == id) at = NR }
    END {
      to = at + step
      if (at && to >= 1 && to <= NR) { t = ids[at]; ids[at] = ids[to]; ids[to] = t }
      for (i = 1; i <= NR; i++) print i ":" ids[i]
    }'); do
    set -- "$@" set -t "${x#*:}" @tab_order "${x%%:*}" \;
  done
  [ $# -gt 0 ] && tmux "$@"
  "$dir/vscode-renumber.sh"
  tmux display -p -t "$id" '#{@tab_index}' > "$state"
  ;;
cursor)
  [ -s "$1" ] || exit 0
  printf 'pos(%s)' "$(cat "$1")"
  : > "$1"
  ;;
ui)
  client=$1
  state=$(mktemp "${TMPDIR:-/tmp}/vscode-pick.XXXXXX")
  trap 'rm -f "$state"' EXIT
  pos=$(tmux display -p -t "$(tmux list-clients -F '#{client_name}|#{session_id}' | awk -F '|' -v c="$client" '$1 == c { print $2; exit }')" '#{@tab_index}')
  printf '%s' "$pos" > "$state"
  legend=$(printf '\033[38;2;139;233;253m⏎\033[38;2;98;114;164m go  \033[38;2;139;233;253m1-9\033[38;2;98;114;164m jump  \033[38;2;139;233;253mp\033[38;2;98;114;164m pin  \033[38;2;139;233;253mr\033[38;2;98;114;164m rename\n\033[38;2;139;233;253mx\033[38;2;98;114;164m close  \033[38;2;139;233;253m⇧↑ ⇧↓\033[38;2;98;114;164m move  \033[38;2;139;233;253mesc\033[38;2;98;114;164m quit')
  set -- \
    --bind "enter:become($self go $client {1})" \
    --bind "p:execute-silent($self pin $client {1})+reload($self list $client)" \
    --bind "x:execute($self close {1})+reload($self list $client)" \
    --bind "r:execute($self rename {1})+reload($self list $client)" \
    --bind "shift-up:execute-silent($self move {1} -1 $state)+reload($self list $client)" \
    --bind "shift-down:execute-silent($self move {1} 1 $state)+reload($self list $client)" \
    --bind "j:down,k:up,q:abort" \
    --bind "0:become($self jump $client 10)"
  for i in 1 2 3 4 5 6 7 8 9; do
    set -- "$@" --bind "$i:become($self jump $client $i)"
  done
  "$self" list "$client" | fzf "$@" \
    --ansi --no-input --no-sort --cycle --layout=reverse \
    --delimiter='	' --with-nth=2 \
    --bind "load:transform($self cursor $state)" \
    --border=rounded --border-label=' Tabs ' --border-label-pos=0 \
    --footer="$legend" --footer-border=line \
    --info=hidden --no-scrollbar --highlight-line --pointer='▌' --gutter=' ' \
    --color='bg:#282a36,bg+:#44475a,fg:#f8f8f2,fg+:#f8f8f2,border:#bd93f9,label:#bd93f9:bold,pointer:#ff79c6,footer-border:#44475a,gutter:#282a36'
  ;;
*)
  client=$cmd
  count=$(tmux list-sessions | wc -l | tr -d ' ')
  height=$((count + 7))
  tmux display-popup -c "$client" -B -E -w 52 -h "$height" -x C -y C "'$self' ui '$client'" || :
  ;;
esac
