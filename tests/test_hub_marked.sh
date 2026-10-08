#!/usr/bin/env bash
# `hh-hub self` and `hh-hub rotate` record or drive "the hub". A project agent started while the owner is away carries the away marker too,
# and the away hook only reads words, so `hh-hub $(echo self)` gets through it: the script itself refuses a marked caller whose
# HH_PROJECT is not this hub's folder (the hub's own start line sets it to the hub's folder, an agent's is its project).
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/$T_HUB"; mkdir -p "$T_TMP/proj"
hub() { (cd "$H" && hh-hub "$@"); }
hub init >/dev/null
READABLE=0; ep=$(t_env_probe HH_PROBE=1) || ep=""
if [ -n "$ep" ]; then t_track "$ep"; sleep 0.5; hh_env_has "$ep" HH_PROBE=1 && READABLE=1; kill "$ep" 2>/dev/null; fi
if [ "$READABLE" != 1 ]; then echo "  SKIP no process here shows its launch environment (a node script is needed)"; t_done; exit 0; fi
NC=$(t_node_claude "$H"); NODEBIN=$(command -v node)
run() {  # run <VAR=value>... -- <hh-hub args>: the command, run by a Claude launched with those variables
  local envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  env ${envs[@]+"${envs[@]}"} "$NODEBIN" "$NC" hh-hub "$@" 2>"$T_TMP/err"; echo $? > "$T_TMP/rc"; RC=$(cat "$T_TMP/rc")
}
rec() { jq -r '.claude_pid // "none"' "$P/hub.json" 2>/dev/null || echo none; }

# a marked Claude whose HH_PROJECT is another folder (a project agent) is refused
run HH_AWAY_BYPASS=1 HH_PROJECT="$T_TMP/proj" -- self --name hub; assert_status "marked, another project: self is refused" "$RC" 4
assert_contains "...saying why" "$(cat "$T_TMP/err")" "HH_PROJECT"
assert_eq "...and no hub is recorded" "$(rec)" "none"
run HH_AWAY_BYPASS=1 HH_PROJECT="$T_TMP/proj" -- rotate; assert_status "marked, another project: rotate is refused" "$RC" 4
assert_contains "...saying why" "$(cat "$T_TMP/err")" "HH_PROJECT"
run HH_AWAY_BYPASS=1 -- self --name hub; assert_status "marked with no HH_PROJECT at all: self is refused" "$RC" 4
run HH_AWAY_BYPASS=1 -- rotate; assert_status "...and rotate" "$RC" 4
run HH_AWAY_BYPASS=1 HH_PROJECT="$H/" -- self --name hub; assert_status "marked, the folder with a trailing slash is not the hub's folder" "$RC" 4

# the marked hub (HH_PROJECT is the hub's folder) goes on as before
run HH_AWAY_BYPASS=1 HH_PROJECT="$H" -- self --name hub; assert_status "marked, the hub's folder: self works" "$RC" 0
[ "$(rec)" != none ] && ok "...and records the hub" || bad "the marked hub was not recorded"
run HH_AWAY_BYPASS=1 HH_PROJECT="$H" -- rotate; assert_status "...rotate gets past the check (and stops at the missing pane record)" "$RC" 2

# an unmarked caller is unchanged, whatever its HH_PROJECT
rm -f "$P/hub.json"
run HH_PROJECT="$T_TMP/proj" -- self --name hub; assert_status "unmarked: self works" "$RC" 0
run HH_PROJECT="$T_TMP/proj" -- rotate; assert_status "unmarked: rotate gets past the check" "$RC" 2

# a launch environment that cannot be read (a bash stand-in shows none): no proof either way, so refused only while the owner is away
ME=$(id -u); NOW=$(date +%s); DD="$T_TMP/dg/area"; DF="$DD/delegate"; mkdir -p "$DD"; chmod 755 "$DD" "$T_TMP/dg"
printf "$T_DELEGATE_LINE1"'\nhub=%s\nuntil=%s\nmcp=\n' "$H" "$((NOW + 3600))" > "$DF"; chmod 644 "$DF"
if hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1; then
  DB=$(t_delegate_bin "$DF"); mkdir -p "$T_TMP/bcl"; printf '#!/usr/bin/env bash\ncd "%s" && "%s/hh-hub" self --name hub\n' "$H" "$DB" > "$T_TMP/bcl/claude"
  rm -f "$P/hub.json"
  bash "$T_TMP/bcl/claude" 2>"$T_TMP/err"; assert_status "away, a Claude whose environment cannot be read: self is refused" $? 4
  assert_contains "...saying why" "$(cat "$T_TMP/err")" "cannot be read"
  rm -f "$DF"
  bash "$T_TMP/bcl/claude" 2>/dev/null; assert_status "not away: the same caller is unchanged" $? 0
else echo "  SKIP the fixture folder is not eligible here: the unreadable-environment case"; fi
t_done
