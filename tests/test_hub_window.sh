#!/usr/bin/env bash
# hh-hub window <project> <agent>[@<team root>] <tokens>: sets an agent's window in its team.json record (the hub's way to fix a window that
# reads wrong), through the one team.json writer (hh_team_edit, under a lock). Hub only: a marked session that is not the hub is refused.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/$T_HUB"
hub() { (cd "$H" && hh-hub "$@"); }
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
mk app; hub init >/dev/null; hub add app --home app >/dev/null
APP=$(cd "$H/app" && pwd -P); mkdir -p "$APP/$T_STATE"
tj() { jq -r "$1" "$APP/$T_STATE/team.json"; }
echo '{"agents":[{"name":"impl","pane":"%1","model":"sonnet","window":200000},{"name":"rev","pane":"%2","model":"opus"},{"name":"orchestrator","pane":"%3","claude_pid":"1","claude_started":"x"}]}' > "$APP/$T_STATE/team.json"

out=$(hub window app impl 1000000 2>&1); assert_status "window of an agent" $? 0
assert_contains "...prints the new reading" "$out" "impl window 1000000"
assert_eq "...is recorded in team.json" "$(tj '.agents[] | select(.name == "impl") | .window')" "1000000"
assert_eq "...and nothing else of the record changed" "$(tj '.agents[] | select(.name == "impl") | [.pane, .model] | join(" ")')" "%1 sonnet"
assert_eq "...nor any other agent" "$(tj '[.agents[] | select(.name != "impl")] | length')" "2"
hub window app rev 500000 >/dev/null 2>&1; assert_eq "an agent with no window gets one" "$(tj '.agents[] | select(.name == "rev") | .window')" "500000"
hub window app orchestrator 1000000 >/dev/null 2>&1; assert_eq "...the orchestrator too" "$(tj '.agents[] | select(.name == "orchestrator") | .window')" "1000000"
[ -z "$(ls "$APP/$T_STATE" | grep -E 'tmp|lock')" ] && ok "...leaving no temporary file or lock" || bad "left behind: $(ls "$APP/$T_STATE")"
for bad_w in 0 abc -5 1.5 ""; do hub window app impl "$bad_w" >/dev/null 2>&1; assert_status "a window of [$bad_w] is refused" $? 4; done
hub window app impl >/dev/null 2>&1; assert_status "no tokens: usage" $? 64
hub window app nobody 1000 >/dev/null 2>&1; assert_status "an agent that does not exist" $? 2
hub window nope impl 1000 >/dev/null 2>&1; assert_status "a project that does not exist" $? 2
assert_eq "a refused call changed nothing" "$(tj '.agents[] | select(.name == "impl") | .window')" "1000000"

# a name in two team roots needs the root
WT="$H/app-wt"; git -C "$H/app" worktree add -q "$WT" -b team; WT=$(cd "$WT" && pwd -P); mkdir -p "$WT/$T_STATE"
echo '{"agents":[{"name":"impl","pane":"%9","window":200000}]}' > "$WT/$T_STATE/team.json"
out=$(hub window app impl 300000 2>&1); assert_status "a name in two team roots is ambiguous" $? 4
assert_contains "...naming both roots" "$out" "impl@$WT"
hub window app "impl@$WT" 300000 >/dev/null 2>&1; assert_status "...with its root it works" $? 0
assert_eq "...in that root" "$(jq -r '.agents[0].window' "$WT/$T_STATE/team.json")" "300000"
assert_eq "...and not in the other" "$(tj '.agents[] | select(.name == "impl") | .window')" "1000000"

# the one team.json writer takes a lock: an edit waits for a live holder, and goes ahead when it lets go
LK="$APP/$T_STATE/team.json.lock"; sleep 30 & hp=$!; t_track "$hp"
hh_lock_try "$LK" "$(hh_holder_json "$hp")"; assert_status "a live process holds the team.json lock" $? 0
( hh_team_edit "$APP" '.agents |= map(if .name == "rev" then .window = ($w | tonumber) else . end)' --arg w 777 ) & ep=$!; t_track "$ep"
sleep 1; assert_eq "an edit waits while it is held" "$(tj '.agents[] | select(.name == "rev") | .window')" "500000"
hh_lock_release "$LK" "$hp" || rm -rf "$LK"
wait "$ep"; assert_eq "...and goes ahead once it is released" "$(tj '.agents[] | select(.name == "rev") | .window')" "777"
kill "$hp" 2>/dev/null

# hub only: a marked session that is not the hub is refused, the marked hub is not
READABLE=0; ep=$(t_env_probe HH_PROBE=1) || ep=""
if [ -n "$ep" ]; then t_track "$ep"; sleep 0.5; hh_env_has "$ep" HH_PROBE=1 && READABLE=1; kill "$ep" 2>/dev/null; fi
if [ "$READABLE" = 1 ]; then
  NC=$(t_node_claude "$H"); NODEBIN=$(command -v node)
  run() { local envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
          env ${envs[@]+"${envs[@]}"} "$NODEBIN" "$NC" hh-hub "$@" 2>"$T_TMP/err"; RC=$?; }
  run HH_AWAY_BYPASS=1 HH_PROJECT="$APP" -- window app impl@"$WT" 111000; assert_status "a marked session of the project is refused" "$RC" 4
  assert_eq "...and nothing was written" "$(jq -r '.agents[0].window' "$WT/$T_STATE/team.json")" "300000"
  run HH_AWAY_BYPASS=1 -- window app impl@"$WT" 111000; assert_status "a marked session with no HH_PROJECT is refused" "$RC" 4
  run HH_AWAY_BYPASS=1 HH_PROJECT="$H" -- window app impl@"$WT" 111000; assert_status "the marked hub may" "$RC" 0
  assert_eq "...and it is written" "$(jq -r '.agents[0].window' "$WT/$T_STATE/team.json")" "111000"
  run HH_PROBE=1 -- window app impl@"$WT" 222000; assert_status "an unmarked session may (the owner is here)" "$RC" 0
else echo "  SKIP no process here shows its launch environment (a node script is needed)"; fi
cd /; t_teardown; t_done
