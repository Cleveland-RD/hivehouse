#!/usr/bin/env bash
# The Stop hook (bin/hh-stop-hook): a registered session at or above the rotation level is told once, per crossing, to update its
# handoff and rotate. Unregistered sessions and sessions below the level are never touched.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
r=$(t_repo proj); other=$(t_repo other)
hh_tmux new-session -d -s hook 'sleep 300'; P=$(hh_tmux list-panes -t hook -F '#{pane_id}' | head -1)
IDENT=$(hh_pane_identity "$HH_TMUX_SOCKET" "$P"); PPID_=${IDENT%%$'\t'*}; PSTART=${IDENT#*$'\t'}
mkdir -p "$T_TMP/cl"
cat > "$T_TMP/cl/claude" <<'CL'
#!/usr/bin/env bash
. "$HH_REPO_ROOT/bin/hh-lib.sh"
jq 'if .claude_pid == "self" then .claude_pid = $c | .claude_started = $t else . end' --arg c "$$" --arg t "$(hh_lstart $$)" "$REGFILE" > "$REGFILE.n" 2>/dev/null && mv "$REGFILE.n" "$REGFILE"
printf '%s' "$INPUT" | TMUX="$HH_TMUX_SOCKET,1,0" TMUX_PANE="$TP" CLAUDE_PLUGIN_OPTION_ROTATE_AT_PERCENT="${LEVEL:-50}" hh-stop-hook
CL
export HH_REPO_ROOT TP="$P" REGFILE="$(hh_registry_dir)/$(hh_pane_key "$HH_TMUX_SOCKET" "$P").json"
mkdir -p "$(hh_registry_dir)"
reg() {  # reg <project> <agent>: the registry file, naming the Claude stand-in that runs the hook
  jq -nc --arg p "$1" --arg a "$2" --arg i "$PPID_" --arg s "$PSTART" '{project:$p,agent:$a,pane_pid:$i,pane_started:$s,claude_pid:"self",claude_started:"self"}' > "$REGFILE"; }
stop() {  # stop <cwd> [level] [stop_hook_active]: the hook, run below the stand-in; prints what it said
  (cd "$1" && INPUT=$(jq -nc --arg s "${SID:-s1}" --argjson a "${3:-false}" '{session_id:$s, hook_event_name:"Stop", stop_hook_active:$a}') LEVEL="${2:-50}" bash "$T_TMP/cl/claude"); }
session() {  # session <project> <agent> <session id> <transcript>: what the SessionStart hook records
  mkdir -p "$1/$T_STATE/team/$2"; jq -nc --arg s "$3" --arg t "$4" '{session_id:$s, transcript_path:$t}' > "$1/$T_STATE/team/$2/session.json"; }
FIX="$HH_REPO_ROOT/tests/fixtures/transcript.jsonl"   # reads 50 (window assumed 200000)
echo "$T_STATE" >/dev/null

# outside tmux the hook is out before it reads the library: a copy with no library beside it exits 0 and says nothing
mkdir -p "$T_TMP/alone"; cp "$HH_REPO_ROOT/bin/hh-stop-hook" "$T_TMP/alone/"
out=$(printf '{"session_id":"s1"}' | TMUX= TMUX_PANE= bash "$T_TMP/alone/hh-stop-hook" 2>&1); assert_status "outside tmux: no library is read" $? 0
assert_eq "...and nothing is said" "$out" ""

# the hook is wired
assert_eq "hooks.json wires one Stop hook" "$(jq -r '.hooks.Stop | length' "$HH_REPO_ROOT/hooks/hooks.json")" "1"
assert_contains "...to bin/hh-stop-hook" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$HH_REPO_ROOT/hooks/hooks.json")" "bin/hh-stop-hook"

# outside tmux, and an unregistered pane: nothing
out=$(cd "$other" && printf '{"session_id":"s1"}' | hh-stop-hook); assert_status "outside tmux exits 0" $? 0
assert_eq "...and says nothing" "$out" ""
rm -f "$REGFILE"; out=$(stop "$other"); assert_status "an unregistered pane exits 0" $? 0
assert_eq "...and says nothing" "$out" ""
[ ! -e "$other/$T_STATE" ] && ok "...and writes nothing" || bad "an unregistered pane wrote into the project"

# an agent at the level: told once to update its handoff and say ROTATE READY to its orchestrator
jq -nc '{agents:[{name:"implementer",pane:"%1"}]}' > /dev/null; mkdir -p "$r/$T_STATE"; jq -nc '{agents:[{name:"implementer",pane:"%1"}]}' > "$r/$T_STATE/team.json"
session "$r" implementer sA "$FIX"; reg "$r" implementer
SID=sA
out=$(stop "$r"); assert_status "an agent at the level" $? 0
assert_eq "...is blocked once" "$(printf '%s' "$out" | jq -r .decision)" "block"
assert_contains "...told its level" "$(printf '%s' "$out" | jq -r .reason)" "50%"
assert_contains "...and that the window is an assumed one" "$(printf '%s' "$out" | jq -r .reason)" "50% of an assumed 200000-token window"
assert_contains "...to update its handoff" "$(printf '%s' "$out" | jq -r .reason)" "START HERE"
assert_contains "...and say ROTATE READY to its orchestrator" "$(printf '%s' "$out" | jq -r .reason)" "ROTATE READY"
assert_contains "...named as hivehouse names it" "$(printf '%s' "$out" | jq -r .reason)" "$(hh_orchestrator_name "$r")"
reg "$r" implementer; out=$(stop "$r"); assert_eq "the same crossing is not told twice" "$out" ""
# below the level the marker is dropped: the next crossing is told again
reg "$r" implementer; out=$(stop "$r" 60); assert_eq "below the level: nothing" "$out" ""
reg "$r" implementer; out=$(stop "$r" 40); assert_eq "...and a new crossing is told again" "$(printf '%s' "$out" | jq -r .decision)" "block"
# a new session (after /clear) is told again at its own crossing
session "$r" implementer sB "$FIX"; reg "$r" implementer
SID=sB; out=$(stop "$r"); assert_eq "a new session at the level is told" "$(printf '%s' "$out" | jq -r .decision)" "block"
# a level that cannot be read, a transcript of nothing, a session never recorded: nothing
session "$r" implementer sC "$T_TMP/none.jsonl"; reg "$r" implementer; SID=sC; out=$(stop "$r"); assert_eq "a level that cannot be read: nothing" "$out" ""
rm -f "$r/$T_STATE/team/implementer/session.json"; reg "$r" implementer; SID=sD; out=$(stop "$r"); assert_eq "no session recorded: nothing" "$out" ""
jq -nc '{type:"assistant", isSidechain:false, message:{model:"claude-sonnet-5-5", usage:{input_tokens:300000, cache_read_input_tokens:0, cache_creation_input_tokens:0, output_tokens:0}}}' > "$T_TMP/big.jsonl"
session "$r" implementer sE "$T_TMP/big.jsonl"; reg "$r" implementer; SID=sE; out=$(stop "$r"); assert_eq "tokens over a window that was only assumed are no percent: told, once" "$(printf '%s' "$out" | jq -r .decision)" "block"
assert_contains "...saying the window cannot be read" "$(printf '%s' "$out" | jq -r .reason)" "300000 tokens"
assert_contains "...and that it is past the window hivehouse can measure" "$(printf '%s' "$out" | jq -r .reason)" "window unknown"
reg "$r" implementer; out=$(stop "$r"); assert_eq "...not told twice for that session" "$out" ""

# the orchestrator (registered with --self, so its entry records a Claude) is told to rotate itself
mkdir -p "$T_TMP/o"; o=$(t_repo orch); mkdir -p "$o/$T_STATE"
jq -nc '{agents:[{name:"orchestrator",pane:"%1",claude_pid:"1",claude_started:"x"}]}' > "$o/$T_STATE/team.json"
session "$o" orchestrator sO "$FIX"; reg "$o" orchestrator
SID=sO; out=$(stop "$o"); assert_eq "the orchestrator is blocked" "$(printf '%s' "$out" | jq -r .decision)" "block"
assert_contains "...told to run hh-self-rotate with its name, as its last act" "$(printf '%s' "$out" | jq -r .reason)" "hh-self-rotate orchestrator"
case "$(printf '%s' "$out" | jq -r .reason)" in *"ROTATE READY"*) bad "the orchestrator is told to message itself" ;; *) ok "...and not to say ROTATE READY" ;; esac

# a Claude that is not the recorded one (a nested claude -p from an agent's Bash) is never told
session "$r" implementer sF "$FIX"; jq -nc --arg p "$r" --arg i "$PPID_" --arg s "$PSTART" '{project:$p,agent:"implementer",pane_pid:$i,pane_started:$s,claude_pid:"1",claude_started:"x"}' > "$REGFILE"
SID=sF; out=$(stop "$r"); assert_eq "a Claude that is not the recorded one is not told" "$out" ""
# a stop the hook is already continuing is never blocked again, even at a crossing nobody was told about
session "$r" implementer sH "$FIX"; reg "$r" implementer; SID=sH; out=$(stop "$r" 50 true); assert_eq "a stop this hook already continued is not blocked again" "$out" ""
reg "$r" implementer; out=$(stop "$r"); assert_eq "...and the crossing is still told afterwards" "$(printf '%s' "$out" | jq -r .decision)" "block"
# a record of another session is never read as this one's
session "$r" implementer sG "$FIX"; reg "$r" implementer; SID=other; out=$(stop "$r"); assert_eq "a session whose record is another's is not told" "$out" ""
t_done
