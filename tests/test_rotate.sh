#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
env -u HIVEMIND_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
spawn() { hm-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 6 >/dev/null 2>&1; }
paneof() { jq -r --arg a "$1" '.agents[]|select(.name==$a).pane' .hivemind/team.json; }
screen() { hm_tmux capture-pane -p -J -S - -t "$(paneof "$1")"; }
log() { cat .hivemind/rotate.log 2>/dev/null; }

spawn impl
hm-rotate impl --still 2 --settle 1 >/dev/null; assert_status "an idle agent is rotated" $? 0
assert_contains "the pane was cleared" "$(screen impl)" "CLEARED"
assert_contains "the pickup line followed the clear" "$(screen impl)" "GOT: You are proj-impl. Read $r/.hivemind/handoffs/impl.md"
assert_eq "rotate.log has one line" "$(log | wc -l | tr -d ' ')" "1"
assert_contains "the log names the agent and the percents (unknown here)" "$(log)" "rotated impl ? -> ?"
# the percent comes from hm-context when a session is recorded
jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > .hivemind/team/impl/session.json
hm-rotate impl --still 2 --settle 1 >/dev/null
assert_contains "the log carries the level before" "$(log | tail -1)" "rotated impl 50% -> 50%"
hm-rotate nobody 2>/dev/null; assert_status "an unknown agent" $? 2
hm-rotate 2>/dev/null; assert_status "usage" $? 64

# a /clear the UI leaves on the input line is cleared and typed again, once
hm_tmux set-environment -g HM_FAKE_CLAUDE retryclear; spawn retry; hm_tmux set-environment -g -u HM_FAKE_CLAUDE
hm-rotate retry --still 2 --settle 1 --max 20 >/dev/null; assert_status "a stuck /clear is retried" $? 0
assert_contains "...and cleared in the end" "$(screen retry)" "CLEARED"
assert_contains "...and the pickup line followed" "$(screen retry)" "GOT: You are proj-retry"

# only on idle: a busy pane and a dialog are never typed into
hm_tmux set-environment -g HM_FAKE_CLAUDE busy; spawn busy; hm_tmux set-environment -g -u HM_FAKE_CLAUDE
n=$(log | wc -l | tr -d ' ')
hm-rotate busy --still 2 --max 5 --settle 1 >/dev/null 2>&1; assert_status "a pane that never goes idle exits 1" $? 1
assert_not() { case "$2" in *"$3"*) bad "$1" ;; *) ok "$1" ;; esac; }
assert_not "nothing was sent to the busy pane" "$(screen busy)" "/clear"
assert_contains "the refusal is logged" "$(log | tail -1)" "not-idle busy"
hm_tmux set-environment -g HM_FAKE_CLAUDE dialog; spawn dlg; hm_tmux set-environment -g -u HM_FAKE_CLAUDE
hm-rotate dlg --still 2 --max 5 --settle 1 >/dev/null 2>&1; assert_status "a dialog exits 5" $? 5
assert_not "nothing was typed into the dialog" "$(screen dlg)" "/clear"
assert_contains "the dialog is logged" "$(log | tail -1)" "dialog dlg"

# a pane that clears but never goes idle again is not sent the pickup line
hm_tmux set-environment -g HM_FAKE_CLAUDE clearbusy; spawn cb; hm_tmux set-environment -g -u HM_FAKE_CLAUDE
hm-rotate cb --still 2 --max 5 --settle 1 >/dev/null 2>&1; assert_status "cleared but never idle exits 1" $? 1
assert_not "no pickup line after a clear that never settled" "$(screen cb | sed -n '/CLEARED/,$p')" "You are proj-cb"
assert_contains "it is logged" "$(log | tail -1)" "cleared-but-not-idle cb"

# only into the pane and process that were recorded: a recycled pane id, an older record and a dead Claude get nothing typed
spawn rec
setteam() { jq --arg a "$1" "(.agents[] | select(.name == \$a)) |= ($2)" .hivemind/team.json > .hivemind/team.json.n && mv .hivemind/team.json.n .hivemind/team.json; }
getteam() { jq -r --arg a "$1" ".agents[] | select(.name == \$a) | $2" .hivemind/team.json; }
cleared() { screen rec | grep -c CLEARED; }
good=$(jq -c --arg a rec '.agents[] | select(.name == $a)' .hivemind/team.json); c0=$(cleared); n=$(log | wc -l | tr -d ' ')
setteam rec '.pane_pid = "1"'
hm-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "another pane process (a recycled id) exits 6" $? 6
assert_eq "...and nothing was typed" "$(cleared)" "$c0"
assert_contains "...and it is logged" "$(log | tail -1)" "identity rec"
setteam rec ".pane_pid = $(printf '%s' "$good" | jq -r .pane_pid | jq -R .) | .pane_started = \"Mon Jan  1 00:00:00 2001\""
hm-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "another start time exits 6" $? 6
assert_eq "...and nothing was typed (start time)" "$(cleared)" "$c0"
setteam rec 'del(.pane_pid, .pane_started)'
hm-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "an older record with no identity exits 6" $? 6
assert_eq "...and nothing was typed (older record)" "$(cleared)" "$c0"
setteam rec ". + {pane_pid: $(printf '%s' "$good" | jq -r .pane_pid | jq -R .), pane_started: $(printf '%s' "$good" | jq -r .pane_started | jq -R .), claude_pid: \"99999\", claude_started: \"Mon Jan  1 00:00:00 2001\"}"
hm-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "a recorded Claude that is gone exits 6" $? 6
assert_eq "...and nothing was typed (no Claude)" "$(cleared)" "$c0"
# the registered Claude process, still alive in the pane, is rotated (the fake Claude is the pane's own process)
setteam rec ". + {claude_pid: $(printf '%s' "$good" | jq -r .pane_pid | jq -R .), claude_started: $(printf '%s' "$good" | jq -r .pane_started | jq -R .)}"
hm-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "the recorded pane and Claude are rotated" $? 0
setteam rec '.pane_pid = "1"'
hm-self-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "self-rotate forks" $? 0
t=0; while ! grep -q "not the one recorded" .hivemind/rotate.out 2>/dev/null && [ $t -lt 20 ]; do sleep 1; t=$((t + 1)); done
assert_contains "self-rotate refuses a mismatched pane, nothing typed" "$(cat .hivemind/rotate.out 2>/dev/null)" "not the one recorded"
rm -f .hivemind/rotate.out

# the identity is checked again just before each send: a pane that changed during the wait for an idle prompt gets nothing
spawn mid; mpane=$(paneof mid)
( hm-rotate mid --still 4 --settle 1 --max 30 >/dev/null 2>&1; echo $? > "$T_TMP/mid.rc" ) & midjob=$!
sleep 1; setteam mid '.pane_pid = "1"'; wait "$midjob"
assert_eq "an identity that changed during the wait exits 6" "$(cat "$T_TMP/mid.rc")" "6"
assert_eq "...and nothing was typed" "$(hm_tmux capture-pane -p -J -S - -t "$mpane" | grep -c CLEARED)" "0"
assert_contains "...and it is logged" "$(log | tail -1)" "identity mid"

# ...also between the clear and its pickup line, and before the retried /clear
hm_tmux set-environment -g HM_FAKE_CLAUDE idle; spawn mid2; hm_tmux set-environment -g -u HM_FAKE_CLAUDE; m2=$(paneof mid2)
( hm-rotate mid2 --still 2 --settle 5 --max 30 >/dev/null 2>&1; echo $? > "$T_TMP/mid2.rc" ) & job=$!
t=0; until hm_tmux capture-pane -p -J -S - -t "$m2" | grep -q CLEARED || [ $t -ge 100 ]; do sleep 0.2; t=$((t + 1)); done
setteam mid2 '.pane_pid = "1"'; wait "$job"
assert_eq "an identity that changed after the clear exits 6" "$(cat "$T_TMP/mid2.rc")" "6"
assert_not "...and the pickup line was not typed after the clear" "$(hm_tmux capture-pane -p -J -S - -t "$m2" | sed -n '/^CLEARED/,$p')" "GOT: You are"
hm_tmux set-environment -g HM_FAKE_CLAUDE retryclear; spawn mid3; hm_tmux set-environment -g -u HM_FAKE_CLAUDE; m3=$(paneof mid3)
( hm-rotate mid3 --still 2 --settle 5 --max 30 >/dev/null 2>&1; echo $? > "$T_TMP/mid3.rc" ) & job=$!
t=0; until hm_tmux capture-pane -p -J -S - -t "$m3" | grep -q '❯.*/clear' || [ $t -ge 100 ]; do sleep 0.2; t=$((t + 1)); done
setteam mid3 '.pane_pid = "1"'; wait "$job"
assert_eq "an identity that changed before the retried /clear exits 6" "$(cat "$T_TMP/mid3.rc")" "6"
assert_eq "...and no second /clear was typed" "$(hm_tmux capture-pane -p -J -S - -t "$m3" | grep -c CLEARED)" "0"

# a tracked .hivemind is refused
echo x > .hivemind/leak; git add -f .hivemind/leak
hm-rotate impl --still 2 --settle 1 >/dev/null 2>&1; assert_status "tracked .hivemind refused" $? 3
hm-self-rotate impl --still 2 --settle 1 >/dev/null 2>&1; assert_status "self-rotate refuses a tracked .hivemind before forking" $? 3
[ -e .hivemind/rotate.out ] && bad "self-rotate wrote rotate.out into a tracked .hivemind" || ok "...and wrote nothing"
git rm -qf --cached .hivemind/leak

# hm-self-rotate returns at once and the rotation finishes detached
spawn selfy
t0=$(date +%s)
hm-self-rotate selfy --still 2 --settle 1; assert_status "self-rotate returns" $? 0
t1=$(date +%s); [ $((t1 - t0)) -le 2 ] && ok "self-rotate returned within 2 s" || bad "self-rotate took $((t1 - t0)) s"
for i in $(seq 1 25); do case "$(log)" in *"rotated selfy"*) break ;; esac; sleep 1; done
assert_contains "the detached rotation cleared the pane" "$(screen selfy)" "CLEARED"
assert_eq "...and sent the pickup line a second time" "$(screen selfy | grep -c "GOT: You are proj-selfy")" "2"
assert_contains "...and logged it" "$(log)" "rotated selfy"
# a fresh repo: self-rotate sets .hivemind up through hm_ensure_state, so it is excluded and a `git add -A` cannot track it
fresh=$(t_repo fresh); (cd "$fresh" && hm-self-rotate nobody --still 1 --settle 1 >/dev/null 2>&1)
grep -qx '/.hivemind/' "$fresh/.git/info/exclude" && ok "self-rotate excludes .hivemind in a fresh repo" || bad "self-rotate left .hivemind unexcluded in a fresh repo"
[ -z "$(git -C "$fresh" status --porcelain)" ] && ok "...so the repo stays clean" || bad "the fresh repo shows untracked files: $(git -C "$fresh" status --porcelain)"
cd /; t_teardown; t_done
