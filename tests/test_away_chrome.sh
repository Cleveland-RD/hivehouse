#!/usr/bin/env bash
# Chrome in away mode: off for every away launch unless the owner turned it on (Chrome in the delegate file's tools=, written by
# hh-hub away --chrome) AND a session that holds the grant passes it down (hh-hub start --chrome by the hub, hh-spawn --chrome by a session
# carrying HH_AWAY_CHROME=1). The delegate file is a fixture (t_delegate_bin); the callers are node scripts named claude whose launch
# environment ps -E can read.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
ME=$(id -u); NOW=$(date +%s)
NODEBIN=$(command -v node || true); READABLE=0
ep=$(t_env_probe HH_PROBE=1) || ep=""
if [ -n "$ep" ]; then t_track "$ep"; sleep 0.5; hh_env_has "$ep" HH_PROBE=1 && READABLE=1; kill "$ep" 2>/dev/null; fi
if [ "$READABLE" != 1 ]; then echo "  SKIP only Apple platform binaries were found (no node): a Claude's launch environment cannot be read here"; t_done; exit 0; fi
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -x 200 -y 56 -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/$T_HUB"
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
DD="$T_TMP/dg/area"; DF="$DD/delegate"
mkdel() {  # mkdel [tools list]: a version 4 delegate file naming this hub, with that tools= line
  mkdir -p "$DD"; chmod 755 "$DD" "$T_TMP/dg"
  printf '%s 4\nhub=%s\nuntil=%s\nmcp=\nhosts=\nallow=\ntools=%s\npeers=\n' "$T_DELEGATE_TAG" "$H" "$((NOW + 3600))" "${1:-}" > "$DF"; chmod 644 "$DF"
}
mkdel Chrome
if ! hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1; then hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1; echo "  SKIP the fixture folder is not eligible here: $HH_DELEGATE_WHY"; t_done; exit 0; fi
DB=$(t_delegate_bin "$DF")
mk app; (cd "$H" && hh-hub init >/dev/null && hh-hub add app --home app >/dev/null)
printf '{"name":"hub"}\n' > "$P/hub.json"
NCP=$(t_node_claude "$H/app"); NCH=$(t_node_claude "$H" "$DB/hh-hub")
echo role > "$T_TMP/role.md"; echo rules > "$T_TMP/RULES.md"
M=(env HH_AWAY_BYPASS=1)                      # a marked session with no Chrome grant
G=(env HH_AWAY_BYPASS=1 HH_AWAY_CHROME=1)     # a marked session that holds the grant
screen() { hh_tmux capture-pane -p -J -S - -t "$1"; }
sp() {  # sp <caller> <agent> <mode> <env prefix words...> -- [more hh-spawn args]: the pane it prints
  local who=$1 a=$2 m=$3; shift 3; local pre=(); while [ "$1" != -- ]; do pre+=("$1"); shift; done; shift
  HH_PROJECT="$H/app" "${pre[@]}" node "$who" "$DB/hh-spawn" --agent "$a" --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode "$m" --still 2 --max-wait 15 "$@" 2>"$T_TMP/sp.err"
}
rec() { jq -r --arg a "$1" --arg k "$2" '[.agents[] | select(.name == $a)][0] | .[$k] // empty | tostring' "$H/app/$T_STATE/team.json"; }
hh() { local who=$1; shift; (cd "$H" && "${M[@]}" HH_PROJECT="$H" node "$who" "$DB/hh-hub" "$@" 2>"$T_TMP/hh.err"); }
noerr() { [ ! -s "$T_TMP/sp.err" ]; }

# ---- hh-spawn --chrome: a session that holds the grant passes it down, with the owner's switch on ----
p=$(sp "$NCP" c1 bypassPermissions "${G[@]}" -- --chrome); assert_status "a granted session spawns a Chrome agent while the switch is on" $? 0
sc=$(screen "$p")
case "$sc" in *"ARGV: --no-chrome"*) bad "the granted agent still has --no-chrome" ;; *) ok "...without --no-chrome" ;; esac
assert_contains "...with the grant in its launch environment" "$sc" "ENV3: HH_AWAY_CHROME=1"
assert_contains "...and the away marker as before" "$sc" "ENV2: HH_AWAY_BYPASS=1"
assert_eq "...team.json records chrome" "$(rec c1 chrome)" "true"
p=$(sp "$NCP" c2 bypassPermissions "${G[@]}" --); assert_status "the same session spawns an agent without --chrome" $? 0
sc=$(screen "$p")
assert_contains "...which keeps --no-chrome" "$sc" "ARGV: --no-chrome"
assert_contains "...and carries no grant" "$sc" "ENV3: HH_AWAY_CHROME="
case "$sc" in *"ENV3: HH_AWAY_CHROME=1"*) bad "an agent spawned without --chrome carries the grant" ;; *) ok "......(empty)" ;; esac
assert_eq "...its record has no chrome" "$(rec c2 chrome)" ""
sp "$NCP" c3 bypassPermissions "${M[@]}" -- --chrome >/dev/null; assert_status "a marked session without the grant cannot pass Chrome on" $? 4
assert_contains "...says why" "$(cat "$T_TMP/sp.err")" "was not granted Chrome"
sp "$NCH" c4 bypassPermissions "${M[@]}" -- --chrome >/dev/null; assert_status "the hub cannot grant itself (its own Claude carries no grant)" $? 4
assert_contains "...the same reason" "$(cat "$T_TMP/sp.err")" "was not granted Chrome"
sp "$NCP" c5 auto "${G[@]}" -- --chrome >/dev/null; assert_status "--chrome outside an away (bypass) launch is refused" $? 4
assert_contains "...says Chrome is only turned off for away launches" "$(cat "$T_TMP/sp.err")" "Chrome is only turned off for away launches"
mkdel ""
sp "$NCP" c6 bypassPermissions "${G[@]}" -- --chrome >/dev/null; assert_status "no owner switch: no Chrome even with the grant" $? 4
assert_contains "...says the file does not turn Chrome on" "$(cat "$T_TMP/sp.err")" "does not turn Chrome on"
mkdel WebFetch
sp "$NCP" c7 bypassPermissions "${G[@]}" -- --chrome >/dev/null; assert_status "a tools= list without Chrome is no switch" $? 4
mkdel Chrome

# ---- respawn: Chrome comes back only when the caller holds the grant itself ----
hh_tmux kill-pane -t "$(rec c1 pane)"; sleep 0.5
rp=$(HH_PROJECT="$H/app" "${M[@]}" node "$NCP" "$DB/hh-spawn" --respawn c1 --still 2 --max-wait 15 2>"$T_TMP/rs.err"); assert_status "respawn of a Chrome agent by a session with no grant" $? 0
sc=$(screen "$rp")
assert_contains "...comes back with --no-chrome" "$sc" "ARGV: --no-chrome"
case "$sc" in *"ENV3: HH_AWAY_CHROME=1"*) bad "the respawn kept the grant" ;; *) ok "...and no grant" ;; esac
assert_contains "...and says it dropped Chrome" "$(cat "$T_TMP/rs.err")" "respawned without Chrome"
assert_eq "...its record loses chrome" "$(rec c1 chrome)" ""
# a Chrome agent whose record says so, respawned by a session that holds the grant
p=$(sp "$NCP" c8 bypassPermissions "${G[@]}" -- --chrome); hh_tmux kill-pane -t "$p"; sleep 0.5
rp=$(HH_PROJECT="$H/app" "${G[@]}" node "$NCP" "$DB/hh-spawn" --respawn c8 --still 2 --max-wait 15 2>"$T_TMP/rs.err"); assert_status "respawn of a Chrome agent by a session that holds the grant" $? 0
sc=$(screen "$rp")
case "$sc" in *"ARGV: --no-chrome"*) bad "the granted respawn has --no-chrome" ;; *) ok "...Chrome comes back" ;; esac
assert_contains "...with the grant" "$sc" "ENV3: HH_AWAY_CHROME=1"
assert_eq "...and the record keeps chrome" "$(rec c8 chrome)" "true"
mkdel ""; hh_tmux kill-pane -t "$rp"; sleep 0.5
rp=$(HH_PROJECT="$H/app" "${G[@]}" node "$NCP" "$DB/hh-spawn" --respawn c8 --still 2 --max-wait 15 2>"$T_TMP/rs.err"); assert_status "respawn with the owner's switch off, by a session with the grant" $? 0
assert_contains "...comes back with --no-chrome" "$(screen "$rp")" "ARGV: --no-chrome"
assert_contains "...and says the file does not turn Chrome on" "$(cat "$T_TMP/rs.err")" "does not turn Chrome on"
mkdel Chrome
HH_PROJECT="$H/app" "${G[@]}" node "$NCP" "$DB/hh-spawn" --respawn c2 --chrome >/dev/null 2>&1; assert_status "--respawn takes no --chrome" $? 64

# ---- hh-hub start --chrome: only the hub, in an away launch, with the switch on ----
t1=$(hh "$NCH" task app --text "First"); t1=${t1%%$'\t'*}
hh "$NCP" start app "$t1" --mode auto --chrome --still 2 --max-wait 15 >/dev/null; assert_status "a marked session that is not the hub cannot start with Chrome" $? 4
assert_eq "...nothing was launched" "$(hh_tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -c '^orchestrator$')" "0"
mkdel ""
hh "$NCH" start app "$t1" --mode auto --chrome --still 2 --max-wait 15 >/dev/null; assert_status "the hub without the owner's switch: refused" $? 4
assert_contains "...says the file does not turn Chrome on" "$(cat "$T_TMP/hh.err")" "does not turn Chrome on"
assert_eq "...nothing was launched" "$(hh_tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -c '^orchestrator$')" "0"
mkdel Chrome
hp=$(hh "$NCH" start app "$t1" --mode auto --chrome --still 2 --max-wait 15); assert_status "the hub with the switch on starts an orchestrator with Chrome" $? 0
sc=$(screen "$hp")
case "$sc" in *"ARGV: --no-chrome"*) bad "the granted orchestrator has --no-chrome" ;; *) ok "...without --no-chrome" ;; esac
assert_contains "...with the grant in its launch environment" "$sc" "ENV3: HH_AWAY_CHROME=1"
assert_contains "...in bypass" "$sc" "ARGV: bypassPermissions"
hh_tmux kill-pane -t "$hp"; sleep 0.5
hp=$(hh "$NCH" start app "$t1" --mode auto --still 2 --max-wait 15); assert_status "the same start without --chrome" $? 0
sc=$(screen "$hp")
assert_contains "...keeps --no-chrome" "$sc" "ARGV: --no-chrome"
case "$sc" in *"ENV3: HH_AWAY_CHROME=1"*) bad "an orchestrator started without --chrome carries the grant" ;; *) ok "...and has no grant" ;; esac
hh_tmux kill-pane -t "$hp"; sleep 0.5
mkdel Chrome; rm -f "$DF"
(cd "$H" && env node "$NCH" "$DB/hh-hub" start app "$t1" --mode auto --chrome --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/hh.err"); assert_status "outside away mode (no delegate file) --chrome is refused" $? 4
assert_contains "...says Chrome is only turned off for away launches" "$(cat "$T_TMP/hh.err")" "Chrome is only turned off for away launches"
mkdel Chrome

# ---- the hub's own start never has it ----
(cd "$H" && "$DB/hh-hub" away-args) > "$T_TMP/aa.out" 2>&1
case "$(cat "$T_TMP/aa.out")" in *HH_AWAY_CHROME*) bad "the hub's own start carries the Chrome grant" ;; *) ok "the hub's own start (away-args) carries no grant" ;; esac
assert_contains "...and keeps --no-chrome" "$(cat "$T_TMP/aa.out")" "arg --no-chrome"
cd /; t_teardown; t_done
