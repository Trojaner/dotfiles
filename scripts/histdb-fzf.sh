#!/usr/bin/env sh
# Backend for the Ctrl-R histdb search widget (see zsh/.zshrc).
#
# Subcommands:
#   search <query>   emit "<id>\t<flattened command>" rows for fzf to display
#   preview <id>     detail pane for one history row
#   header           status line: current sort + scope + shortcuts
#   cycle-sort       advance sort mode   (relevancy -> time -> ...)
#   cycle-scope      advance scope mode  (global -> cwd -> cwd+sub -> ...)
#
# The query hits the database on every keystroke (the widget runs fzf with
# --disabled + change:reload), so ranking/filtering is done here in SQL, never
# on an already-fetched list. Current sort/scope are kept in $HISTDB_STATE.
#
# Env: HISTDB_FILE HISTDB_STATE HISTDB_PWD HISTDB_LIMIT
#
# NOTE: zsh-histdb records only command metadata, never stdout/stderr, so the
# preview cannot show command output — there is nothing to read it from.

db="${HISTDB_FILE:-$HOME/.histdb/zsh-history.db}"
state="${HISTDB_STATE:-${TMPDIR:-/tmp}}"
here="${HISTDB_PWD:-$PWD}"
limit="${HISTDB_LIMIT:-1000}"
tab=$(printf '\t')
bs='\'                                   # a single backslash, used as LIKE ESCAPE

get_sort()  { cat "$state/sort"  2>/dev/null || printf 'relevancy'; }
get_scope() { cat "$state/scope" 2>/dev/null || printf 'global'; }

# ANSI colors (fzf renders these in the list header and preview)
esc=$(printf '\033')
reset="${esc}[0m"; bold="${esc}[1m"; dim="${esc}[2m"
red="${esc}[31m"; green="${esc}[32m"; yellow="${esc}[33m"; blue="${esc}[34m"; cyan="${esc}[36m"

run()     { sqlite3 -batch -noheader "$db" "$1"; }
run_tab() { sqlite3 -batch -noheader -separator "$tab" "$db" "$1"; }

# escape a string for inside a single-quoted SQL literal (double the quotes)
sqlq()  { printf '%s' "$1" | sed "s/'/''/g"; }
# escape LIKE metacharacters (\ % _) so they match literally under ESCAPE '\'
likeq() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/%/\\%/g' -e 's/_/\\_/g'; }
# a "<col> LIKE '<pat>' ESCAPE '\'" fragment; <pat> must be pre-escaped
like_clause() { printf "%s LIKE '%s' ESCAPE '%s'" "$1" "$2" "$bs"; }

# build a fuzzy (subsequence) LIKE body: %c1%c2%...% with each char LIKE-escaped
fuzzy_body() {
  printf '%s\n' "$1" | awk 'BEGIN{FS=""} {
    p="%";
    for (i = 1; i <= NF; i++) {
      c = $i;
      if (c == "\\" || c == "%" || c == "_") c = "\\" c;
      p = p c "%";
    }
    if (NF == 0) p = "%";
    print p;
  }'
}

# WHERE fragment restricting rows to the active scope
scope_where() {
  case "$(get_scope)" in
    cwd)  printf "places.dir = '%s'" "$(sqlq "$here")" ;;
    tree)
      d=$(sqlq "$here")
      t=$(printf '%s/%s' "$(sqlq "$(likeq "$here")")" '%')   # <dir>/%
      printf "(places.dir = '%s' OR %s)" "$d" "$(like_clause 'places.dir' "$t")" ;;
    *)    printf '1=1' ;;
  esac
}

search() {
  q="$1"
  base=$(sqlq "$(likeq "$q")")
  pfx="${base}%"        # query%      -> exact prefix (rank 0)
  wrd="% ${base}%"      # % query%    -> a later word starts with query (rank 1)
  ctn="%${base}%"       # %query%     -> appears anywhere (rank 2)
  fz=$(sqlq "$(fuzzy_body "$q")")   # %q%u%e%... -> fuzzy subsequence (rank 3)
  hq=$(sqlq "$here")

  match="CASE
      WHEN $(like_clause 'commands.argv' "$pfx") THEN 0
      WHEN $(like_clause 'commands.argv' "$wrd") THEN 1
      WHEN $(like_clause 'commands.argv' "$ctn") THEN 2
      ELSE 3 END"
  # smart tier: prefer commands run here, and successful over failed
  tier="CASE
      WHEN places.dir = '$hq' AND history.exit_status = 0 THEN 0
      WHEN places.dir = '$hq' THEN 1
      WHEN history.exit_status = 0 THEN 2
      ELSE 3 END"

  # relevancy casts a wide (fuzzy) net and ranks; time sort uses a tighter
  # substring match so recency doesn't drag in loose fuzzy hits.
  case "$(get_sort)" in
    time)
      where_match=$(like_clause 'commands.argv' "$ctn")
      order="MAX(history.start_time) DESC" ;;
    *)
      where_match=$(like_clause 'commands.argv' "$fz")
      order="MIN($match) ASC, MIN($tier) ASC, MAX(history.start_time) DESC" ;;
  esac

  run_tab "SELECT MAX(history.id),
      replace(replace(commands.argv, char(10), '  '), char(9), ' ')
    FROM history
    LEFT JOIN commands ON history.command_id = commands.id
    LEFT JOIN places   ON history.place_id   = places.id
    WHERE $(scope_where) AND $where_match
    GROUP BY commands.argv
    ORDER BY $order
    LIMIT $limit"
}

preview() {
  id="$1"
  [ -z "$id" ] && return 0
  case "$id" in *[!0-9]*) return 0 ;; esac

  argv=$(run "SELECT commands.argv FROM history
    LEFT JOIN commands ON history.command_id = commands.id
    WHERE history.id = $id LIMIT 1")
  [ -z "$argv" ] && return 0

  # Split on Unit Separator (0x1f), NOT tab: tab is IFS-whitespace, so `read`
  # would collapse consecutive tabs and drop empty leading fields (e.g. a NULL
  # exit_status), shifting every value. 0x1f is non-whitespace so empty fields
  # are preserved.
  us=$(printf '\037')
  meta=$(sqlite3 -batch -noheader -separator "$us" "$db" "SELECT
      IFNULL(history.exit_status, ''),
      IFNULL(datetime(history.start_time, 'unixepoch', 'localtime'), ''),
      IFNULL(history.duration, ''),
      IFNULL(places.dir, ''),
      (SELECT COUNT(*) FROM history h WHERE h.command_id = history.command_id),
      (SELECT COUNT(*) FROM history h WHERE h.command_id = history.command_id AND h.exit_status = 0),
      (SELECT COUNT(*) FROM history h WHERE h.command_id = history.command_id AND h.exit_status <> 0)
    FROM history
    LEFT JOIN places ON history.place_id = places.id
    WHERE history.id = $id LIMIT 1")
  IFS="$us" read -r ex started dur dir runs oks fails <<EOF
$meta
EOF

  if [ -z "$ex" ]; then
    st="${dim}— unknown${reset}"
  elif [ "$ex" -eq 0 ] 2>/dev/null; then
    st="${green}${ex} ✔${reset}"
  else
    st="${red}${ex} ✘${reset}"
  fi

  if [ -z "$dur" ]; then
    dur_disp="${dim}—${reset}"
  elif [ "$dur" -ge 60 ] 2>/dev/null; then
    dur_disp="$((dur / 60))m $((dur % 60))s"
  else
    dur_disp="${dur}s"
  fi

  label() { printf '  %s%-10s%s %s\n' "$cyan" "$1" "$reset" "$2"; }

  printf '%s' "$argv" | bat --language=bash --color=always --style=plain --paging=never 2>/dev/null \
    || printf '%s%s%s\n' "$bold" "$argv" "$reset"

  printf '\n'
  label "Status"    "$st"
  label "When"      "${started:-${dim}—${reset}}"
  label "Duration"  "$dur_disp"
  label "Directory" "${yellow}${dir:-—}${reset}"
  label "History"   "ran ${bold}${runs}×${reset} · ${green}${oks} ok${reset} / ${red}${fails} fail${reset}"
}

header() {
  case "$(get_sort)" in
    time) s="${yellow}execution time${reset}" ;;
    *)    s="${green}relevancy${reset}" ;;
  esac
  case "$(get_scope)" in
    cwd)  sc="${blue}current dir${reset}" ;;
    tree) sc="${blue}current dir + subdirs${reset}" ;;
    *)    sc="${cyan}global${reset}" ;;
  esac
  printf ' %ssort%s %s   %sscope%s %s      %sctrl-s%s change sort · %sctrl-t%s change scope\n' \
    "$bold" "$reset" "$s" "$bold" "$reset" "$sc" "$dim" "$reset" "$dim" "$reset"
}

cmd="$1"
case "$cmd" in
  search)      search "$2" ;;
  preview)     preview "$2" ;;
  header)      header ;;
  cycle-sort)  case "$(get_sort)"  in relevancy) printf time      > "$state/sort"  ;; *) printf relevancy > "$state/sort"  ;; esac ;;
  cycle-scope) case "$(get_scope)" in global)    printf cwd       > "$state/scope" ;; cwd) printf tree > "$state/scope" ;; *) printf global > "$state/scope" ;; esac ;;
esac
