#!/bin/sh
# Claude Code statusLine command

input=$(cat)

# --- ANSI colors (light theme) ---
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
LGREEN='\033[92m'
LRED='\033[91m'
LGREEN_BG='\033[48;5;157;30m'
LRED_BG='\033[48;5;217;30m'
YELLOW_BG='\033[48;5;229;30m'
GREY_BG='\033[48;5;252;30m'
BLUE='\033[94m'
DBLUE='\033[34m'
BLUE_BG='\033[48;5;153;34m'
RED_BG_USAGE='\033[48;5;217;31m'
LABEL_BG='\033[48;5;240;97m'

# --- Parse JSON ---
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
lines_add=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_del=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
rate_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0')
rate_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0')
reset_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
reset_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0')

# --- Context bg color by percentage ---
ctx_bg_color() {
  pct=$1
  if [ "$pct" -ge 85 ] 2>/dev/null; then printf '%s' "$LRED_BG"
  elif [ "$pct" -ge 65 ] 2>/dev/null; then printf '%s' "$YELLOW_BG"
  else printf '%s' "$GREY_BG"; fi
}

# --- Usage bar bg color ---
usage_bg() {
  pct=$1
  if [ "$pct" -ge 70 ] 2>/dev/null; then printf '%s' "$RED_BG_USAGE"
  else printf '%s' "$BLUE_BG"; fi
}

# --- Git (with timeout) ---
git_indicator="${GREEN}✔${RST}"
git_branch="—"
git_extra=""
git_files=""
if timeout 1 git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(timeout 1 git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    git_branch="$branch"
    dirty=0
    if ! timeout 1 git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null || \
       ! timeout 1 git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then
      git_indicator="${YELLOW}!${RST}"
      dirty=1
    fi
    upstream=$(timeout 1 git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref '@{u}' 2>/dev/null)
    if [ -n "$upstream" ]; then
      ab=$(timeout 1 git -C "$cwd" --no-optional-locks rev-list --left-right --count HEAD...@{u} 2>/dev/null)
      if [ -n "$ab" ]; then
        a=$(echo "$ab" | cut -f1)
        b=$(echo "$ab" | cut -f2)
        [ "$a" -gt 0 ] 2>/dev/null && git_extra="${git_extra} ↑${a}"
        [ "$b" -gt 0 ] 2>/dev/null && git_extra="${git_extra} ↓${b}"
      fi
    fi
    if [ "$dirty" -eq 1 ]; then
      stats=$(timeout 1 git -C "$cwd" --no-optional-locks diff --name-status HEAD 2>/dev/null)
      untracked=$(timeout 1 git -C "$cwd" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null)
      n_new=$(echo "$untracked" | grep -c . 2>/dev/null || echo 0)
      n_mod=$(echo "$stats" | grep -c '^M' 2>/dev/null || echo 0)
      n_del=$(echo "$stats" | grep -c '^D' 2>/dev/null || echo 0)
      staged_new=$(timeout 1 git -C "$cwd" --no-optional-locks diff --cached --name-status 2>/dev/null | grep -c '^A' 2>/dev/null || echo 0)
      n_new=$(( n_new + staged_new ))
      parts=""
      [ "$n_new" -gt 0 ] && parts="${LGREEN}+${n_new}${RST}"
      [ "$n_mod" -gt 0 ] && parts="${parts:+$parts }${YELLOW}~${n_mod}${RST}"
      [ "$n_del" -gt 0 ] && parts="${parts:+$parts }${LRED}-${n_del}${RST}"
      [ -n "$parts" ] && git_files=" ${parts}"
    fi
  fi
fi

# --- Progress bar with % overlaid at the end ---
raw_bar() {
  pct=$1; w=${2:-20}
  label=" ${pct}%% "
  label_len=$(( ${#pct} + 3 ))
  filled=$(( pct * w / 100 ))
  bar_before=$(( w - label_len ))
  b=""
  i=0
  while [ $i -lt $bar_before ]; do
    if [ $i -lt $filled ]; then b="${b}█"; else b="${b}▁"; fi
    i=$((i+1))
  done
  printf '%s' "$b"
  printf '%s' "$label"
}

# --- Time left ---
ttl() {
  ts=$1
  [ "$ts" -eq 0 ] 2>/dev/null && { printf '%s' '--'; return; }
  now=$(date +%s)
  d=$(( ts - now ))
  if [ "$d" -le 0 ]; then printf 'now'
  elif [ "$d" -lt 3600 ]; then printf '%dm' "$(( d / 60 ))"
  elif [ "$d" -lt 86400 ]; then printf '%dh%dm' "$(( d / 3600 ))" "$(( (d % 3600) / 60 ))"
  else printf '%dd%dh' "$(( d / 86400 ))" "$(( (d % 86400) / 3600 ))"; fi
}

# --- Values ---
ctx_int=$(printf '%.0f' "${used_pct:-0}")
r5=$(printf '%.0f' "$rate_5h")
r7=$(printf '%.0f' "$rate_7d")
cost_fmt="—"
[ -n "$cost" ] && cost_fmt="\$$(printf '%.2f' "$cost")"
ctx_bg=$(ctx_bg_color "$ctx_int")
bg_5h=$(usage_bg "$r5")
bg_7d=$(usage_bg "$r7")

# --- Cloud theme: basename of cwd ---
cwd_base=$(basename "$cwd")

# --- Output ---
printf "${BOLD}workspace:${RST} ${BOLD}\033[0;32m${cwd_base}${RST} · ${BOLD}model:${RST} ${model} · ${BOLD}git:${RST} ${git_branch} ${git_indicator}${git_extra}${git_files} · ${BOLD}context:${RST} ${ctx_bg} ${ctx_int}%% ${RST} · ${LGREEN_BG} +${lines_add} ${RST} ${LRED_BG} -${lines_del} ${RST} · ${BOLD}cost:${RST} ${cost_fmt}\n"
printf "${BOLD}usage:${RST} ${LABEL_BG} 5h [$(ttl "$reset_5h")] ${RST}${bg_5h}$(raw_bar "$r5" 20)${RST} | ${LABEL_BG} 7d [$(ttl "$reset_7d")] ${RST}${bg_7d}$(raw_bar "$r7" 20)${RST}\n"
printf "\033[38;5;242m    Alt+P model  Alt+T think  Alt+O fast  Shift+Tab mode${RST}"
