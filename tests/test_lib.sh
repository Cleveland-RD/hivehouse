#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj)
assert_eq "home is HIVEMIND_HOME" "$(hm_home)" "$HIVEMIND_HOME"
( unset HIVEMIND_HOME; assert_eq "home defaults" "$(hm_home)" "$HOME/.hivemind" )
assert_eq "root from repo" "$(cd "$r" && hm_project_root)" "$r"
git -C "$r" worktree add -q "$T_TMP/proj-wt" -b wt
assert_eq "root from a worktree is the main repo" "$(cd "$T_TMP/proj-wt" && hm_project_root)" "$r"
assert_eq "HM_PROJECT wins" "$(cd "$T_TMP" && HM_PROJECT="$r" hm_project_root)" "$r"
# A1: a missing HM_PROJECT or no repo fails with 2, and the failure propagates through a substitution
(cd "$T_TMP" && HM_PROJECT="$T_TMP/nope" hm_project_root >/dev/null 2>&1); assert_status "missing HM_PROJECT dir is exit 2" $? 2
mkdir "$T_TMP/norepo"; (cd "$T_TMP/norepo" && hm_project_root >/dev/null 2>&1); assert_status "outside a repo is exit 2" $? 2
(cd "$T_TMP/norepo" && x=$(hm_state) || exit $?; echo "reached" >"$T_TMP/reached") >/dev/null 2>&1; assert_status "hm_state failure propagates" $? 2
[ -e "$T_TMP/reached" ] && bad "caller stopped after a failed substitution" || ok "caller stopped after a failed substitution"
(cd "$T_TMP/norepo" && hm_ensure_state >/dev/null 2>&1); assert_status "ensure_state outside a repo is exit 2" $? 2
[ -e "$T_TMP/norepo/.hivemind" ] || [ -e /.hivemind ] && bad "no state written outside a repo" || ok "no state written outside a repo"
(cd "$r" && hm_ensure_state) ; assert_contains "state excluded" "$(cat "$r/.git/info/exclude")" "/.hivemind/"
(cd "$T_TMP/proj-wt" && hm_ensure_state); assert_eq "exclude written once" "$(grep -c '/.hivemind/' "$r/.git/info/exclude")" "1"
assert_eq "state dir path" "$(cd "$T_TMP/proj-wt" && hm_state)" "$r/.hivemind"
mkdir -p "$r/.hivemind"; echo x > "$r/.hivemind/leak"; git -C "$r" add -f .hivemind/leak
(cd "$r" && hm_ensure_state 2>/dev/null); assert_status "refuses tracked .hivemind" $? 3
k1=$(hm_project_key "$r"); k2=$(hm_project_key "$T_TMP/proj2")
[ "$k1" != "$k2" ] && ok "project keys differ by path" || bad "project keys differ by path"
assert_eq "pane key is stable" "$(hm_pane_key /s %1)" "$(hm_pane_key /s %1)"
[ "$(hm_pane_key /s %1)" != "$(hm_pane_key /s %2)" ] && ok "pane keys differ by pane" || bad "pane keys differ by pane"
assert_eq "json_get reads a field" "$(echo '{"a":{"b":7}}' > "$T_TMP/j"; hm_json_get "$T_TMP/j" .a.b)" "7"
assert_eq "json_get empty when absent" "$(hm_json_get "$T_TMP/j" .zz)" ""
# wait_idle: still, an empty prompt and no dialog; a pane that is still but not idle is never reported idle
new_pane() {  # new_pane <fake claude behaviour> -> pane id running the fake claude
  hm_tmux new-session -d -s "t$RANDOM" -x 200 -y 50 -P -F '#{pane_id}' -e "HM_FAKE_CLAUDE=$1" "claude --name probe"
}
pane=$(new_pane idle); wait_idle "$pane" 2 20; assert_status "idle pane is idle" $? 0
assert_contains "fake claude printed its argv" "$(hm_tmux capture-pane -p -t "$pane")" "ARGV: --name"
pane=$(new_pane dialog); wait_idle "$pane" 2 6; assert_status "a dialog is never idle, and is told apart" $? 3
pane=$(new_pane bare); wait_idle "$pane" 2 6; assert_status "still with no prompt is not idle" $? 1
pane=$(new_pane dialogprompt); wait_idle "$pane" 2 6; assert_status "a dialog above an empty prompt is not idle" $? 3
pane=$(new_pane ticking); wait_idle "$pane" 2 5; assert_status "an empty prompt that keeps changing is not idle" $? 1
pane=$(new_pane busy); wait_idle "$pane" 2 5; assert_status "a busy pane is not idle" $? 1
t_done
