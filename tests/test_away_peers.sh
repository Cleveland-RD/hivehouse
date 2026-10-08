#!/usr/bin/env bash
# S6: hh-hub away --peers <names> writes peers= into the root-owned delegate file (version 4); while away, the hub and a registered
# orchestrator of one of the hub's projects may SendMessage a listed peer (a session on another machine), nobody else may, and every
# allowed send leaves one audit line in the hub's folder. The caller is proved by its Claude's pid and start time, never by its folder alone.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
proj=$(t_repo proj); hub="$T_TMP/hub"; mkdir -p "$hub/$T_HUB" "$proj/$T_STATE"
unl=$(t_repo unlisted); mkdir -p "$unl/$T_STATE"
mkdir -p "$T_TMP/cl" "$CLAUDE_CONFIG_DIR/sessions"
printf '#!/usr/bin/env bash\nfor i in $(seq 600); do sleep 1; done\n' > "$T_TMP/cl/claude"
SP=""; SS=""
spawn() {  # spawn <session name or empty>: a stand-in Claude; sets SP (pid) and SS (start time)
  bash "$T_TMP/cl/claude" & SP=$!; t_track "$SP"; sleep 0.2; SS=$(hh_lstart "$SP")
  [ -z "$1" ] || jq -nc --argjson p "$SP" --arg n "$1" '{pid:$p,name:$n}' > "$CLAUDE_CONFIG_DIR/sessions/$SP.json"
}
spawn hub1; HP=$SP; HS=$SS
spawn proj-orchestrator; OP=$SP; OS=$SS
jq -nc --arg p "$HP" --arg s "$HS" '{name:"hub1",claude_pid:$p,claude_started:$s}' > "$hub/$T_HUB/hub.json"
jq -nc --arg a "$proj" '{projects:[{name:"proj",home:$a,repos:[]}]}' > "$hub/$T_HUB/projects.json"
jq -nc --arg op "$OP" --arg os "$OS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"proj-orchestrator",pane_pid:"1",pane_started:"x"},{name:"implementer",pane_pid:"2",pane_started:"y"}]}' > "$proj/$T_STATE/team.json"
jq -nc --arg op "$OP" --arg os "$OS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"unlisted-orchestrator",pane_pid:"1",pane_started:"x"}]}' > "$unl/$T_STATE/team.json"

# the delegate file, as the hook reads it (a scratch copy of bin/ that reads this fixture as the root-owned file)
NOW=$(date +%s); DGD="$T_TMP/dg/area"; DGF="$DGD/delegate"; mkdir -p "$DGD"; chmod 755 "$DGD" "$T_TMP/dg"
mkdg() {  # mkdg <version> [<peers>] [<hub dir>]
  case "$1" in
    4) printf "$T_DELEGATE_LINE4"'\nhub=%s\nuntil=%s\nmcp=\nhosts=\nallow=\ntools=\npeers=%s\n' "$(cd "${3:-$hub}" && pwd -P)" "$((NOW + 3600))" "${2:-}" > "$DGF" ;;
    3) printf "$T_DELEGATE_LINE3"'\nhub=%s\nuntil=%s\nmcp=\nhosts=\nallow=\ntools=\n' "$(cd "$hub" && pwd -P)" "$((NOW + 3600))" > "$DGF" ;;
  esac
  chmod 644 "$DGF"
}
mkdg 4 "far-orchestrator,far-agent"
hh_delegate_read "$DGF" "$(id -u)" "$NOW" >/dev/null 2>&1; assert_status "a version 4 file with peers= reads as valid" $? 0
assert_eq "...and exposes the list" "$HH_DR_PEERS" "far-orchestrator,far-agent"
RUNBIN=$(t_delegate_bin "$DGF"); HOOK="$RUNBIN/hh-away-hook"

# a stand-in Claude that records itself as the role's session, then runs the hook below itself (so the hook's Claude ancestor is it)
mkdir -p "$T_TMP/run"; cat > "$T_TMP/run/claude" <<'CL'
#!/usr/bin/env bash
. "$HH_REPO_ROOT/bin/hh-lib.sh"
case "${REC:-}" in
  hub) jq --arg p "$$" --arg s "$(hh_lstart $$)" '.claude_pid = $p | .claude_started = $s' "$HUBJ" > "$HUBJ.n" && mv "$HUBJ.n" "$HUBJ" ;;
  hubpid) jq --arg p "$$" '.claude_pid = $p | .claude_started = "Mon Jan  1 00:00:00 2001"' "$HUBJ" > "$HUBJ.n" && mv "$HUBJ.n" "$HUBJ" ;;   # the pid is this session's, the start time is not
  hubstart) jq --arg s "$(hh_lstart $$)" '.claude_started = $s' "$HUBJ" > "$HUBJ.n" && mv "$HUBJ.n" "$HUBJ" ;;   # the start time is this session's, the pid is not
  orch) jq --arg p "$$" --arg s "$(hh_lstart $$)" '(.agents[] | select(.name == "orchestrator")) |= (.claude_pid = $p | .claude_started = $s)' "$TEAMJ" > "$TEAMJ.n" && mv "$TEAMJ.n" "$TEAMJ" ;;
  orchpid) jq --arg p "$$" '(.agents[] | select(.name == "orchestrator")) |= (.claude_pid = $p | .claude_started = "Mon Jan  1 00:00:00 2001")' "$TEAMJ" > "$TEAMJ.n" && mv "$TEAMJ.n" "$TEAMJ" ;;
  orchstart) jq --arg s "$(hh_lstart $$)" '(.agents[] | select(.name == "orchestrator")) |= (.claude_started = $s)' "$TEAMJ" > "$TEAMJ.n" && mv "$TEAMJ.n" "$TEAMJ" ;;
esac
"$HOOK" <&0
CL
export HH_REPO_ROOT
msg() { jq -nc --arg t "$1" --arg m "${2:-hello far side}" '{tool_name:"SendMessage",cwd:"/",tool_input:{to:$t,message:$m}}'; }
AUDIT="$hub/$T_HUB/$T_PEER_LOG"
send() {  # send <rec: hub|orch|none> <project dir> <to> [message]: the hook as a marked session of that project; sets RC and ERR
  local team="${TEAMDIR:-$2}/$T_STATE/team.json"
  ERR=$(msg "$3" "${4:-hello far side}" | REC="$1" HUBJ="$hub/$T_HUB/hub.json" TEAMJ="$team" HOOK="$HOOK" HH_REPO_ROOT="$HH_REPO_ROOT" HH_AWAY_BYPASS=1 HH_PROJECT="$2" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= bash "$T_TMP/run/claude" 2>&1 >/dev/null); RC=$?
}
passes()  { send "$2" "$3" "$4" "${5:-}"; [ "$RC" -eq 0 ] && ok "$1" || bad "$1: exit $RC [$ERR]"; }
refused() { send "$2" "$3" "$4" "${5:-}"; [ "$RC" -eq 2 ] && [ -n "$ERR" ] && ok "$1" || bad "$1: exit $RC [$ERR]"; }
resethub() { jq --arg p "$HP" --arg s "$HS" '.claude_pid = $p | .claude_started = $s' "$hub/$T_HUB/hub.json" > "$T_TMP/h.n" && mv "$T_TMP/h.n" "$hub/$T_HUB/hub.json"; }

echo "-- the hub"
passes "the hub messages a listed orchestrator" hub "$hub" "far-orchestrator"
passes "...and a listed agent" hub "$hub" "far-agent"
passes "...and a listed name with a ref" hub "$hub" "far-orchestrator [9ac3d1]"
refused "...but not an unlisted name" hub "$hub" "stranger"
refused "...nor a listed name with a different ref shape" hub "$hub" "far-orchestrator [x]y"
refused "...nor a name that only starts like a listed one" hub "$hub" "far-orchestrator-2"
resethub
refused "a session in the hub's folder that is not the hub Claude hub.json records is refused" none "$hub" "far-agent"
refused "a session whose pid is the hub's but whose start time is not is refused" hubpid "$hub" "far-agent"
resethub
refused "a session whose start time is the hub's but whose pid is not is refused" hubstart "$hub" "far-agent"
resethub
echo "-- a registered orchestrator of one of the hub's projects"
passes "its registered orchestrator messages a listed peer" orch "$proj" "far-agent"
refused "an orchestrator of a project the hub does not list is refused" orch "$unl" "far-agent"
refused "an orchestrator whose pid is recorded but whose start time is not is refused" orchpid "$proj" "far-agent"
jq -nc --arg op "$OP" --arg os "$OS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"proj-orchestrator",pane_pid:"1",pane_started:"x"},{name:"implementer",pane_pid:"2",pane_started:"y"}]}' > "$proj/$T_STATE/team.json"
refused "one whose start time is recorded but whose pid is not is refused" orchstart "$proj" "far-agent"
jq -nc --arg op "$OP" --arg os "$OS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"proj-orchestrator",pane_pid:"1",pane_started:"x"},{name:"implementer",pane_pid:"2",pane_started:"y"}]}' > "$proj/$T_STATE/team.json"
TEAMDIR="$proj" refused "a session that is the registered orchestrator of a listed project but runs with another folder as its project is refused" orch "$unl" "far-agent"
refused "a session in a project home that is not the registered orchestrator (another pid) is refused" none "$proj" "far-agent"
jq '(.agents[] | select(.name == "orchestrator")) |= (.claude_pid = "999999")' "$proj/$T_STATE/team.json" > "$T_TMP/t.n" && mv "$T_TMP/t.n" "$proj/$T_STATE/team.json"
refused "...and one whose recorded orchestrator pid is stale" none "$proj" "far-agent"
jq -nc --arg op "$OP" --arg os "$OS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"proj-orchestrator",pane_pid:"1",pane_started:"x"},{name:"implementer",pane_pid:"2",pane_started:"y"}]}' > "$proj/$T_STATE/team.json"
refused "a local agent (no Claude recorded in the team) is refused" none "$proj" "far-orchestrator"
echo "-- targets"
refused "a uds: address is never a peer" hub "$hub" "uds:/tmp/cc-socks/far-agent.sock"
resethub
echo "-- a live local session that carries a listed name"
spawn far-agent; LP=$SP
resethub
refused "the hub's send to a listed name a local session carries is refused" hub "$hub" "far-agent"
assert_contains "...saying a local session carries the peer's name" "$ERR" "a local session carries the peer's name"
kill "$LP" 2>/dev/null; rm -f "$CLAUDE_CONFIG_DIR/sessions/$LP.json"
resethub
passes "...and goes through again once it is gone" hub "$hub" "far-agent"
echo "-- the delegate file decides"
mkdg 3; resethub
refused "a version 3 file (no peers) refuses the hub's send" hub "$hub" "far-agent"
mkdg 4 ""; resethub
refused "a version 4 file with an empty peers= refuses it" hub "$hub" "far-agent"
rm -f "$DGF"; resethub
refused "no delegate file refuses it" hub "$hub" "far-agent"
hub2="$T_TMP/hub2"; mkdir -p "$hub2/$T_HUB"; cp "$hub/$T_HUB/hub.json" "$hub2/$T_HUB/hub.json"; echo '{"projects":[]}' > "$hub2/$T_HUB/projects.json"
mkdg 4 "far-agent" "$hub2"; resethub
refused "a file that lists the peer but names another hub refuses the hub's send" hub "$hub" "far-agent"
mkdg 4 "far-agent"; resethub
passes "a file listing only far-agent allows it" hub "$hub" "far-agent"
refused "...and not the other name" hub "$hub" "far-orchestrator"
echo "-- the audit"
rm -f "$AUDIT"; mkdg 4 "far-orchestrator,far-agent"; resethub
passes "an allowed send" hub "$hub" "far-orchestrator [aa11]" $'first line here\nsecond line'
assert_eq "...leaves one audit line" "$(wc -l < "$AUDIT" | tr -d ' ')" "1"
assert_eq "...naming the peer" "$(jq -r .peer "$AUDIT")" "far-orchestrator"
assert_eq "...with the first line of the message only" "$(jq -r .note "$AUDIT")" "first line here"
assert_contains "...and the time" "$(jq -r .at "$AUDIT")" "T"
resethub
refused "a refused send" hub "$hub" "stranger"
assert_eq "...leaves none" "$(wc -l < "$AUDIT" | tr -d ' ')" "1"
passes "an orchestrator's allowed send" orch "$proj" "far-agent" "from the orchestrator"
assert_eq "...adds one, naming who sent it" "$(tail -1 "$AUDIT" | jq -r '.peer + " " + .from')" "far-agent proj-orchestrator"

rm -f "$AUDIT"; mkdir "$AUDIT"; resethub
refused "a send whose audit line cannot be written (a folder at peers.jsonl) is refused" hub "$hub" "far-agent"
assert_contains "...saying the audit line could not be written" "$ERR" "could not be written"
rmdir "$AUDIT"

cd /; t_teardown; t_done
