#!/usr/bin/env bash
# The name agents report to: the --self orchestrator's session name, read live from Claude Code's own session record.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; mkdir -p .hivemind; echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
env -u HIVEMIND_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
# a Claude stand-in (an interpreter running a script named claude) that stays alive
mkdir -p "$T_TMP/cl" "$CLAUDE_CONFIG_DIR/sessions"; printf '#!/usr/bin/env bash\nexec -a "$0" sleep 600\n' > "$T_TMP/cl/claude"
bash "$T_TMP/cl/claude" & cpid=$!; t_track "$cpid"; sleep 0.3
record() { jq -nc --argjson p "${2:-$cpid}" --arg n "$1" '{pid:$p, name:$n, sessionId:"sid-1"}' > "$CLAUDE_CONFIG_DIR/sessions/$cpid.json"; }
team() {  # team [name_full]: the --self orchestrator's entry, naming the stand-in
  jq -nc --arg c "$cpid" --arg s "$(hm_lstart "$cpid")" --arg f "${1:-}" \
    '{agents:[{name:"orchestrator", pane:"%0", claude_pid:$c, claude_started:$s} + (if $f != "" then {name_full:$f} else {} end)]}' > .hivemind/team.json
}

team; record "acme-orchestrator"
assert_eq "the session's own name" "$(hm_orchestrator_name "$r")" "acme-orchestrator"
record "renamed (2).v_x"
assert_eq "a later /rename is followed" "$(hm_orchestrator_name "$r")" "renamed (2).v_x"
team "at-self"
record 'has"quote'
assert_eq "a name with a quote is not typed: the recorded one" "$(hm_orchestrator_name "$r" 2>"$T_TMP/err")" "at-self"
assert_contains "...and says so" "$(cat "$T_TMP/err")" "not one hivemind will type"
record "$(printf 'two\nlines')"
assert_eq "a name with a newline is not typed" "$(hm_orchestrator_name "$r" 2>/dev/null)" "at-self"
record "$(printf 'x%.0s' $(seq 1 65))"
assert_eq "a name over 64 is not typed" "$(hm_orchestrator_name "$r" 2>/dev/null)" "at-self"
for loc in C en_US.UTF-8; do
  record "orchestré"; assert_eq "a non-ASCII name is not typed under $loc" "$(LC_ALL=$loc hm_orchestrator_name "$r" 2>/dev/null)" "at-self"
done
record "someone-else" 1
assert_eq "a record for another pid: the recorded name, quietly" "$(hm_orchestrator_name "$r" 2>"$T_TMP/err")" "at-self"
assert_eq "...nothing on stderr" "$(cat "$T_TMP/err")" ""
echo 'not json' > "$CLAUDE_CONFIG_DIR/sessions/$cpid.json"
assert_eq "a record that is not JSON: the recorded name, quietly" "$(hm_orchestrator_name "$r" 2>"$T_TMP/err")" "at-self"
assert_eq "...nothing on stderr" "$(cat "$T_TMP/err")" ""
echo "{\"pid\":$cpid}" > "$CLAUDE_CONFIG_DIR/sessions/$cpid.json"
assert_eq "a record with no name: the recorded name" "$(hm_orchestrator_name "$r" 2>/dev/null)" "at-self"
rm "$CLAUDE_CONFIG_DIR/sessions/$cpid.json"; team
assert_eq "nothing recorded anywhere: <project>-orchestrator" "$(hm_orchestrator_name "$r")" "proj-orchestrator"
team 'bad"full'
assert_eq "a recorded name that is not typable is not typed either" "$(hm_orchestrator_name "$r" 2>/dev/null)" "proj-orchestrator"
rm .hivemind/team.json
assert_eq "no team: <project>-orchestrator" "$(hm_orchestrator_name "$r")" "proj-orchestrator"
# a Claude that is gone is not asked, even if its pid's record is still there
bash "$T_TMP/cl/claude" & gone=$!; t_track "$gone"; sleep 0.3; gs=$(hm_lstart "$gone"); kill "$gone"; wait "$gone" 2>/dev/null
jq -nc --argjson p "$gone" '{pid:$p, name:"ghost"}' > "$CLAUDE_CONFIG_DIR/sessions/$gone.json"
jq -nc --arg c "$gone" --arg s "$gs" '{agents:[{name:"orchestrator", claude_pid:$c, claude_started:$s, name_full:"at-self"}]}' > .hivemind/team.json
assert_eq "the orchestrator's Claude is gone: the recorded name" "$(hm_orchestrator_name "$r")" "at-self"

# spawn and rotate: the pickup line and the handoff skeleton name it, read when each is sent
team "at-self"; record "acme-orchestrator"
spawn() { hm-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 15 >/dev/null; }
spawn impl; assert_status "spawn" $? 0
pane=$(jq -r '.agents[]|select(.name=="impl").pane' .hivemind/team.json)
assert_contains "the pickup line names the orchestrator's session" "$(hm_tmux capture-pane -p -J -S - -t "$pane")" "Report to acme-orchestrator."
assert_contains "...and so does the handoff skeleton" "$(cat .hivemind/handoffs/impl.md)" "Report only to acme-orchestrator."
record "acme-orch-2"
hm-rotate impl --still 2 --settle 1 >/dev/null; assert_status "rotate" $? 0
assert_contains "a rename before a rotation is followed" "$(hm_tmux capture-pane -p -J -S - -t "$pane")" "Report to acme-orch-2."

# the orchestrator's own pickup line (hm-self-rotate): its own name, its handoff, and no report, wait or role dir
own=$(hm_pickup_line proj "$r" orchestrator)
assert_eq "the --self entry's line" "$own" "You are acme-orch-2. Read $r/.hivemind/handoffs/orchestrator.md from the top: its START HERE block is your prompt."
for w in "Report" "Wait" ".hivemind/team/"; do
  case "$own" in *"$w"*) bad "the --self entry's line names $w" ;; *) ok "the --self entry's line has no $w" ;; esac
done
assert_contains "a spawned agent's line is unchanged" "$(hm_pickup_line proj "$r" impl)" "holds your role and the rules. Report to acme-orch-2. Wait for its first message before any work."
# hm-self-rotate of the --self entry types the short line: impl's pane stands in for the orchestrator's own (a Claude there)
jq '.agents |= map(if .name == "impl" then . + {claude_pid: .pane_pid, claude_started: .pane_started} else select(.name != "orchestrator") end)' .hivemind/team.json > "$T_TMP/t.json" && mv "$T_TMP/t.json" .hivemind/team.json
hm-self-rotate impl --still 2 --settle 1; assert_status "hm-self-rotate returns at once" $? 0
for i in $(seq 1 40); do grep -q "rotated impl" .hivemind/rotate.log 2>/dev/null && [ "$(grep -c 'rotated impl' .hivemind/rotate.log)" -ge 2 ] && break; sleep 0.5; done
assert_contains "...and the orchestrator gets its own short line" "$(hm_tmux capture-pane -p -J -S - -t "$pane")" "GOT: You are proj-orchestrator. Read $r/.hivemind/handoffs/impl.md from the top: its START HERE block is your prompt."

# --self records the name: --name, else the session's own, else none
# a Claude stand-in that writes its own session record, as Claude Code does, then runs hm-spawn --self below itself
rm -f .hivemind/team.json; mkdir -p "$T_TMP/cl2"
printf '#!/usr/bin/env bash\njq -nc --argjson p $$ --arg n "$SELF_NAME" '"'"'{pid:$p,name:$n}'"'"' > "$CLAUDE_CONFIG_DIR/sessions/$$.json"\nhm-spawn "$@"; echo rc=$? >>"$SELF_OUT"; sleep 30\n' > "$T_TMP/cl2/claude"
selfrun() { local o="$1"; shift; hm_tmux new-session -d -c "$r" -e "HIVEMIND_HOME=$HIVEMIND_HOME" -e "SELF_OUT=$o" -e "SELF_NAME=$SELF_NAME" "bash $T_TMP/cl2/claude $(printf '%q ' "$@") >>$o 2>&1"; sleep 2; }
SELF_NAME="owner-orch" selfrun "$T_TMP/s1.out" --self --agent orchestrator
assert_contains "--self ran" "$(cat "$T_TMP/s1.out")" "rc=0"
assert_eq "--self records the session's own name" "$(jq -r '.agents[]|select(.name=="orchestrator").name_full' .hivemind/team.json)" "owner-orch"
SELF_NAME="owner-orch" selfrun "$T_TMP/s2.out" --self --agent orchestrator --name "given name"
assert_eq "--name is recorded instead" "$(jq -r '.agents[]|select(.name=="orchestrator").name_full' .hivemind/team.json)" "given name"
SELF_NAME='bad"name' selfrun "$T_TMP/s3.out" --self --agent orchestrator
assert_eq "a session name that is not typable is not recorded" "$(jq -r '.agents[]|select(.name=="orchestrator").name_full // "none"' .hivemind/team.json)" "none"
SELF_NAME="x" selfrun "$T_TMP/s4.out" --self --agent orchestrator --name 'bad"name'
assert_contains "a --name that is not typable is refused" "$(cat "$T_TMP/s4.out")" "rc=4"
hm-spawn --agent x --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model m --effort e --mode auto --name n >/dev/null 2>&1
assert_status "--name without --self is a usage error" $? 64
cd /; t_teardown; t_done
