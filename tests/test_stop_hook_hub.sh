#!/usr/bin/env bash
# The Stop hook (bin/hh-stop-hook) for the hub: the hub has no registry file, so it is proven from hub.json (the Claude above the hook is the
# recorded one, in the recorded pane and tmux server, and the hook input's session is the hub's own). At or above the level it is told once
# per crossing to update its handoff and run hh-hub rotate; anything not proven is silent.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
H=$(t_repo hubroot); mkdir -p "$H/$T_HUB"; HF="$H/$T_HUB/hub.json"
hh_tmux new-session -d -s hubhook 'sleep 300'; P=$(hh_tmux list-panes -t hubhook -F '#{pane_id}' | head -1)
IDENT=$(hh_pane_identity "$HH_TMUX_SOCKET" "$P"); PPID_=${IDENT%%$'\t'*}; PSTART=${IDENT#*$'\t'}
mkdir -p "$T_TMP/cl" "$CLAUDE_CONFIG_DIR/projects/p"
mkdir -p "$T_TMP/cl2"
cat > "$T_TMP/cl2/claude" <<'CL'
#!/usr/bin/env bash
cd "$WORK" && printf '%s' "$INPUT" | TMUX="${TMUXV:-$HH_TMUX_SOCKET,1,0}" TMUX_PANE="${TPANE:-$TP}" CLAUDE_PLUGIN_OPTION_ROTATE_AT_PERCENT="${LEVEL:-50}" hh-stop-hook
CL
cat > "$T_TMP/cl/claude" <<'CL'
#!/usr/bin/env bash
. "$HH_REPO_ROOT/bin/hh-lib.sh"
# "self" in hub.json is this process: the pid, and the start time when that says "self" too (a wrong one stays wrong)
jq 'if .claude_pid == "self" then .claude_pid = $c | (if .claude_started == "self" then .claude_started = $t else . end) else . end' --arg c "$$" --arg t "$(hh_lstart $$)" "$HF" > "$HF.n" 2>/dev/null && mv "$HF.n" "$HF"
# REC: Claude Code's own record of this running session (<config dir>/sessions/<pid>.json), which names the hub's session before hub.json does
if [ -n "${REC:-}" ]; then mkdir -p "$CLAUDE_CONFIG_DIR/sessions"; jq -nc --argjson p "$$" --arg s "$REC" '{pid:$p, sessionId:$s}' > "$CLAUDE_CONFIG_DIR/sessions/$$.json"; fi
trap 'rm -f "$CLAUDE_CONFIG_DIR/sessions/$$.json"' EXIT
# NEST: a second Claude (a claude -p from the hub's own Bash) between the recorded one and the hook
if [ -n "${NEST:-}" ]; then bash "$T_TMP/cl2/claude"
else cd "$WORK" && printf '%s' "$INPUT" | TMUX="${TMUXV:-$HH_TMUX_SOCKET,1,0}" TMUX_PANE="${TPANE:-$TP}" CLAUDE_PLUGIN_OPTION_ROTATE_AT_PERCENT="${LEVEL:-50}" hh-stop-hook; fi
CL
export HH_REPO_ROOT HF T_TMP TP="$P"
FIX="$HH_REPO_ROOT/tests/fixtures/transcript.jsonl"   # reads 50 of a 200000 window
cp "$FIX" "$CLAUDE_CONFIG_DIR/projects/p/hs1.jsonl"; cp "$FIX" "$CLAUDE_CONFIG_DIR/projects/p/hs2.jsonl"
hub() {  # hub [extra jq filter]: hub.json naming the stand-in as the hub, in this pane
  jq -nc --arg i "$PPID_" --arg s "$PSTART" --arg k "$HH_TMUX_SOCKET" --arg p "$P" '{name:"hub",claude_pid:"self",claude_started:"self",session_id:"hs1",window:200000,socket:$k,pane:$p,pane_pid:$i,pane_started:$s}' \
    | jq -c "${1:-.}" > "$HF"; }
stop() {  # stop [level] [stop_hook_active]: the hook below the stand-in; prints what it said
  INPUT=$(jq -nc --arg s "${SID:-hs1}" --argjson a "${2:-false}" '{session_id:$s, hook_event_name:"Stop", stop_hook_active:$a}') WORK="${WORK:-$H}" LEVEL="${1:-50}" bash "$T_TMP/cl/claude"; }
MARK="$H/$T_HUB/rotate-asked.json"

hub; out=$(stop); assert_status "the hub at the level" $? 0
R=$(printf '%s' "$out" | jq -r .reason)
assert_eq "...is blocked" "$(printf '%s' "$out" | jq -r .decision)" "block"
assert_contains "...told its level" "$R" "50%"
assert_contains "...to update the hub handoff" "$R" "$T_HUB/memory/hub-handoff.md"
assert_contains "...and run hh-hub rotate as its last act" "$R" "hh-hub rotate as the last act of this turn"
assert_contains "...never in the middle of a message to the owner" "$R" "Never in the middle of a message to the owner"
case "$R" in *"ROTATE READY"*|*"hh-self-rotate"*) bad "the hub is told an agent's or the orchestrator's way" ;; *) ok "...not the agent's way" ;; esac
[ -f "$MARK" ] && ok "...the crossing is marked under the hub folder" || bad "no marker under $T_HUB"
hub; out=$(stop); assert_eq "the same crossing is not told twice" "$out" ""
hub; out=$(stop 60); assert_eq "below the level: nothing" "$out" ""
[ ! -f "$MARK" ] && ok "...and the marker is dropped" || bad "the marker stayed below the level"
hub; out=$(stop 40); assert_eq "a new crossing is told again" "$(printf '%s' "$out" | jq -r .decision)" "block"
# the hub from a folder below its root
mkdir -p "$H/sub"; rm -f "$MARK"; hub; out=$(WORK="$H/sub" stop); assert_eq "the hub started in a folder below its root is found" "$(printf '%s' "$out" | jq -r .decision)" "block"
rm -f "$MARK"
# a stop the hook already continued is never blocked again
hub; out=$(stop 50 true); assert_eq "a stop this hook already continued is not blocked again" "$out" ""
# the hook input's session must be the hub's own
hub; out=$(SID=other stop); assert_eq "a session that is not the recorded hub session is not told" "$out" ""
# hub.json's own id is only the fallback: the session record of the recorded Claude comes first (a /clear changes the id there)
hub '.session_id = "stale"'; out=$(stop); assert_eq "no record and a hub.json id that is not this session's: not told" "$out" ""
hub '.session_id = "stale"'; out=$(REC=hs1 stop); assert_eq "a record naming this session wins over a stale hub.json id: told" "$(printf '%s' "$out" | jq -r .decision)" "block"
rm -f "$MARK"; hub; out=$(REC=other stop); assert_eq "a record naming another session wins over hub.json's id: not told" "$out" ""
rm -f "$MARK"
# not proven: another process, another pane, another tmux server, a pane that was restarted
hub '.claude_pid = "1" | .claude_started = "x"'; out=$(stop); assert_eq "another process than the recorded one is not told" "$out" ""
hub '.claude_started = "Mon Jan  1 00:00:00 2001"'; out=$(stop); assert_eq "a recorded pid with another start time (a reused pid) is not told" "$out" ""
hub; out=$(NEST=1 stop); assert_eq "a Claude nested below the recorded one (claude -p from its Bash) is not told" "$out" ""
hub '.pane = "%99"'; out=$(stop); assert_eq "another pane is not told" "$out" ""
hub '.socket = "/nowhere/sock"'; out=$(stop); assert_eq "another tmux server is not told" "$out" ""
hub '.pane_started = "Mon Jan  1 00:00:00 2001"'; out=$(stop); assert_eq "a pane that was restarted is not told" "$out" ""
hub 'del(.pane, .socket, .pane_pid, .pane_started)'; out=$(stop); assert_eq "a hub that recorded no pane is not told" "$out" ""
out=$(TMUXV= TPANE= stop); assert_status "outside tmux" $? 0; assert_eq "...says nothing" "$out" ""
rm -f "$HF"; out=$(stop); assert_eq "no hub.json: nothing" "$out" ""
# a level that cannot be read: nothing
hub '.session_id = "none"'; out=$(SID=none stop); assert_eq "a hub whose transcript is not there is not told" "$out" ""
# a guessed window is told once, never a request to rotate
hub 'del(.window)'; rm -f "$H/$T_HUB/window-guess-told.json"; out=$(stop); R=$(printf '%s' "$out" | jq -r .reason)
assert_eq "a guessed window at the level: told once" "$(printf '%s' "$out" | jq -r .decision)" "block"
assert_contains "...that the window is not known" "$R" "not known (guessed at $T_WINDOW)"
assert_contains "...with how the hub records it" "$R" "hh-hub self --window"
case "$R" in *"hh-hub rotate"*|*"START HERE"*) bad "a guessed window is told to rotate" ;; *) ok "...and never asked to rotate" ;; esac
hub 'del(.window)'; out=$(stop); assert_eq "...not told twice for that session" "$out" ""
# tokens over a window that was only assumed: no percent, counts as at or above, told once
jq -nc '{type:"assistant", isSidechain:false, message:{model:"claude-sonnet-5-5", usage:{input_tokens:300000, cache_read_input_tokens:0, cache_creation_input_tokens:0, output_tokens:0}}}' > "$CLAUDE_CONFIG_DIR/projects/p/hs2.jsonl"
rm -f "$MARK"; hub '.session_id = "hs2"'; out=$(SID=hs2 stop); R=$(printf '%s' "$out" | jq -r .reason)
assert_contains "a window that cannot be measured counts as at or above the level" "$R" "window unknown"
hub '.session_id = "hs2"'; out=$(SID=hs2 stop); assert_eq "...and is told once" "$out" ""
# the hub's folder is tracked by git: nothing is written
rm -f "$MARK"; git -C "$H" add -f "$T_HUB/hub.json" >/dev/null 2>&1; hub; git -C "$H" add -f "$T_HUB/hub.json" >/dev/null 2>&1
out=$(stop); assert_eq "a hub folder git tracks is left alone" "$out" ""
t_done
