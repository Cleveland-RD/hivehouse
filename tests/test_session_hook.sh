#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); other=$(t_repo other)
input='{"session_id":"s1","transcript_path":"/tmp/t.jsonl","source":"startup"}'
inpane() { (cd "$1" && printf '%s' "$input" | TMUX="$HM_TMUX_SOCKET,1,0" TMUX_PANE="$2" CLAUDE_PLUGIN_OPTION_MIN_FREE_GB="${3:-0}" hm-session-hook); }
# outside tmux: nothing
(cd "$other" && printf '%s' "$input" | hm-session-hook); assert_status "outside tmux exits 0" $? 0
[ ! -e "$other/.hivemind" ] && [ "$(ls -A "$other" | grep -v "^.git$")" = "README" ] && ok "silent outside tmux" || bad "outside tmux wrote something"
# inside tmux but an unregistered pane: nothing
inpane "$other" %9; assert_status "unregistered pane exits 0" $? 0
[ -d "$other/.hivemind" ] && bad "unregistered pane writes nothing" || ok "unregistered pane writes nothing"
# a registered pane, run from a worktree cwd: writes into the project, found from the registry
git -C "$r" worktree add -q "$T_TMP/proj-wt" -b wt
mkdir -p "$(hm_registry_dir)"; key=$(hm_pane_key "$HM_TMUX_SOCKET" %7)
jq -nc --arg p "$r" '{project:$p,agent:"implementer"}' > "$(hm_registry_dir)/$key.json"
inpane "$T_TMP/proj-wt" %7
assert_eq "session recorded in project" "$(jq -r .session_id "$r/.hivemind/team/implementer/session.json")" "s1"
assert_eq "transcript recorded" "$(jq -r .transcript_path "$r/.hivemind/team/implementer/session.json")" "/tmp/t.jsonl"
assert_contains "time recorded" "$(cat "$r/.hivemind/team/implementer/session.json")" '"at":"'
[ -d "$T_TMP/proj-wt/.hivemind" ] && bad "nothing in the worktree" || ok "nothing in the worktree"
# the disk warning passes through only when low
out=$(inpane "$T_TMP/proj-wt" %7 999999); assert_contains "low disk warns" "$out" '"hookEventName":"SessionStart"'
assert_eq "enough disk is silent" "$(inpane "$T_TMP/proj-wt" %7 0)" ""
# it never fails the session
(cd "$r" && printf 'not json' | TMUX="$HM_TMUX_SOCKET,1,0" TMUX_PANE=%7 hm-session-hook); assert_status "bad input exits 0" $? 0
assert_eq "bad input leaves the last record" "$(jq -r .session_id "$r/.hivemind/team/implementer/session.json")" "s1"
jq -nc --arg p "$T_TMP/gone" '{project:$p,agent:"implementer"}' > "$(hm_registry_dir)/$key.json"
inpane "$r" %7; assert_status "a vanished project exits 0" $? 0
[ -e "$T_TMP/gone" ] && bad "a vanished project was recreated" || ok "a vanished project is not recreated"
# an agent name that climbs out of team/ is refused
jq -nc --arg p "$r" '{project:$p,agent:"../escape"}' > "$(hm_registry_dir)/$key.json"
inpane "$r" %7; assert_status "a path-like agent exits 0" $? 0
[ -e "$r/.hivemind/escape" ] && bad "a path-like agent name wrote outside team/" || ok "a path-like agent name wrote nothing"
# a tracked .hivemind is never written to
jq -nc --arg p "$r" '{project:$p,agent:"implementer"}' > "$(hm_registry_dir)/$key.json"
echo '{}' > "$r/.hivemind/team/implementer/other.json"; git -C "$r" add -f .hivemind/team/implementer/other.json
rm -f "$r/.hivemind/team/implementer/session.json"; inpane "$r" %7; assert_status "tracked .hivemind exits 0" $? 0
[ -e "$r/.hivemind/team/implementer/session.json" ] && bad "a tracked .hivemind was written to" || ok "a tracked .hivemind is left alone"
# the hook file registers it on the three starts
assert_eq "hooks.json: SessionStart matcher" "$(jq -r '.hooks.SessionStart[0].matcher' "$HM_REPO_ROOT/hooks/hooks.json")" "startup|clear|resume"
assert_contains "hooks.json: command" "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$HM_REPO_ROOT/hooks/hooks.json")" 'hm-session-hook'
cd /; t_teardown; t_done
