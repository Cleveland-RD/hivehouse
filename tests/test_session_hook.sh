#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); other=$(t_repo other)
input='{"session_id":"s1","transcript_path":"/tmp/t.jsonl","source":"startup"}'
hm_tmux new-session -d -s hook 'sleep 300'; P=$(hm_tmux list-panes -t hook -F '#{pane_id}' | head -1)
IDENT=$(hm_pane_identity "$HM_TMUX_SOCKET" "$P"); PPID_=${IDENT%%$'\t'*}; PSTART=${IDENT#*$'\t'}
# reg <project> <agent> [pane_pid] [pane_started]: the registry file hm-spawn writes, with the identity of the real pane unless given
reg() { mkdir -p "$(hm_registry_dir)"; jq -nc --arg p "$1" --arg a "$2" --arg i "${3-$PPID_}" --arg s "${4-$PSTART}" \
  '{project:$p,agent:$a,pane_pid:$i,pane_started:$s}' > "$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$P").json"; }
inpane() { (cd "$1" && printf '%s' "$input" | TMUX="$HM_TMUX_SOCKET,1,0" TMUX_PANE="$2" CLAUDE_PLUGIN_OPTION_MIN_FREE_GB="${3:-0}" hm-session-hook); }
# outside tmux: nothing
(cd "$other" && printf '%s' "$input" | hm-session-hook); assert_status "outside tmux exits 0" $? 0
[ ! -e "$other/.hivemind" ] && [ "$(ls -A "$other" | grep -v "^.git$")" = "README" ] && ok "silent outside tmux" || bad "outside tmux wrote something"
# inside tmux but an unregistered pane: nothing
inpane "$other" %9; assert_status "unregistered pane exits 0" $? 0
[ -d "$other/.hivemind" ] && bad "unregistered pane writes nothing" || ok "unregistered pane writes nothing"
# a registered pane, run from a worktree cwd: writes into the project, found from the registry
git -C "$r" worktree add -q "$T_TMP/proj-wt" -b wt
key=$(hm_pane_key "$HM_TMUX_SOCKET" $P)
reg "$r" implementer
inpane "$T_TMP/proj-wt" $P
assert_eq "session recorded in project" "$(jq -r .session_id "$r/.hivemind/team/implementer/session.json")" "s1"
assert_eq "transcript recorded" "$(jq -r .transcript_path "$r/.hivemind/team/implementer/session.json")" "/tmp/t.jsonl"
assert_contains "time recorded" "$(cat "$r/.hivemind/team/implementer/session.json")" '"at":"'
[ -d "$T_TMP/proj-wt/.hivemind" ] && bad "nothing in the worktree" || ok "nothing in the worktree"
# the disk warning passes through only when low
out=$(inpane "$T_TMP/proj-wt" $P 999999); assert_contains "low disk warns" "$out" '"hookEventName":"SessionStart"'
assert_eq "enough disk is silent" "$(inpane "$T_TMP/proj-wt" $P 0)" ""
# it never fails the session
(cd "$r" && printf 'not json' | TMUX="$HM_TMUX_SOCKET,1,0" TMUX_PANE=$P hm-session-hook); assert_status "bad input exits 0" $? 0
assert_eq "bad input leaves the last record" "$(jq -r .session_id "$r/.hivemind/team/implementer/session.json")" "s1"
reg "$T_TMP/gone" implementer
inpane "$r" $P; assert_status "a vanished project exits 0" $? 0
[ -e "$T_TMP/gone" ] && bad "a vanished project was recreated" || ok "a vanished project is not recreated"
# an agent name that climbs out of team/ is refused
reg "$r" ../escape
inpane "$r" $P; assert_status "a path-like agent exits 0" $? 0
[ -e "$r/.hivemind/escape" ] && bad "a path-like agent name wrote outside team/" || ok "a path-like agent name wrote nothing"
reg "$r" Upper
for loc in C en_US.UTF-8; do
  (export LC_ALL=$loc; inpane "$r" $P); assert_status "a capital agent name exits 0 under $loc" $? 0
  [ -e "$r/.hivemind/team/Upper" ] && bad "a capital agent name wrote under $loc" || ok "a capital agent name wrote nothing under $loc"
done
# a tracked .hivemind is never written to
reg "$r" implementer
echo '{}' > "$r/.hivemind/team/implementer/other.json"; git -C "$r" add -f .hivemind/team/implementer/other.json
rm -f "$r/.hivemind/team/implementer/session.json"; inpane "$r" $P; assert_status "tracked .hivemind exits 0" $? 0
[ -e "$r/.hivemind/team/implementer/session.json" ] && bad "a tracked .hivemind was written to" || ok "a tracked .hivemind is left alone"
git -C "$r" rm -qf --cached .hivemind/team/implementer/other.json   # untrack it again
# a recycled pane id (a restarted tmux server hands the same id to another pane) gets nothing written, and the stale file goes
reg "$r" implementer; rm -f "$r/.hivemind/team/implementer/session.json"
reg "$r" implementer "$((PPID_ + 1))" "$PSTART"; inpane "$r" $P 999999 >"$T_TMP/o1"; assert_status "another pane process exits 0" $? 0
[ -e "$r/.hivemind/team/implementer/session.json" ] && bad "a recycled pane (other pid) was written" || ok "a recycled pane (other pid) writes nothing"
[ ! -s "$T_TMP/o1" ] && ok "...and the disk hook does not run for it" || bad "the disk hook ran for a recycled pane"
[ -e "$(hm_registry_dir)/$key.json" ] && bad "the stale file (other pid) was kept" || ok "the stale file (other pid) is removed"
reg "$r" implementer "$PPID_" "Mon Jan  1 00:00:00 2001"; inpane "$r" $P; assert_status "another start time exits 0" $? 0
[ -e "$r/.hivemind/team/implementer/session.json" ] && bad "a recycled pane (other start time) was written" || ok "a recycled pane (other start time) writes nothing"
[ -e "$(hm_registry_dir)/$key.json" ] && bad "the stale file (other start time) was kept" || ok "the stale file (other start time) is removed"
# an old-format file, with no identity, is stale
jq -nc --arg p "$r" '{project:$p,agent:"implementer"}' > "$(hm_registry_dir)/$key.json"; inpane "$r" $P; assert_status "an old-format file exits 0" $? 0
[ -e "$r/.hivemind/team/implementer/session.json" ] && bad "an old-format file was trusted" || ok "an old-format file writes nothing"
[ -e "$(hm_registry_dir)/$key.json" ] && bad "the old-format file was kept" || ok "the old-format file is removed"
# a tmux that cannot answer proves nothing: nothing written, the file stays
mkdir -p "$T_TMP/shim"; printf '#!/bin/sh\ncase "$*" in *pane_pid*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v tmux)" > "$T_TMP/shim/tmux"; chmod +x "$T_TMP/shim/tmux"
reg "$r" implementer; (cd "$r" && printf '%s' "$input" | PATH="$T_TMP/shim:$PATH" TMUX="$HM_TMUX_SOCKET,1,0" TMUX_PANE="$P" hm-session-hook); assert_status "an unanswering tmux exits 0" $? 0
[ -e "$r/.hivemind/team/implementer/session.json" ] && bad "an unanswering tmux wrote" || ok "an unanswering tmux writes nothing"
[ -e "$(hm_registry_dir)/$key.json" ] && ok "...and the file stays" || bad "an unanswering tmux removed a good file"
reg "$r" implementer
inpane "$r" $P; assert_eq "a valid identity is still written" "$(jq -r .session_id "$r/.hivemind/team/implementer/session.json")" "s1"
# the hook file registers it on the three starts
assert_eq "hooks.json: SessionStart matcher" "$(jq -r '.hooks.SessionStart[0].matcher' "$HM_REPO_ROOT/hooks/hooks.json")" "startup|clear|resume"
assert_contains "hooks.json: command" "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$HM_REPO_ROOT/hooks/hooks.json")" 'hm-session-hook'
cd /; t_teardown; t_done
