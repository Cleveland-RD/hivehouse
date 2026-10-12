#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
r=$(t_repo proj); cd "$r" || exit 2; echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
spawn() { hh-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 6 >/dev/null 2>&1; }
paneof() { jq -r --arg a "$1" '.agents[]|select(.name==$a).pane' $T_STATE/team.json; }
screen() { hh_tmux capture-pane -p -J -S - -t "$(paneof "$1")"; }
log() { cat $T_STATE/rotate.log 2>/dev/null; }

spawn impl
hh-rotate impl --still 2 --settle 1 >/dev/null; assert_status "an idle agent is rotated" $? 0
assert_contains "the pane was cleared" "$(screen impl)" "CLEARED"
assert_contains "the pickup line followed the clear" "$(screen impl)" "GOT: You are proj-impl. Read $r/$T_STATE/handoffs/impl.md"
assert_eq "rotate.log has one line" "$(log | wc -l | tr -d ' ')" "1"
assert_contains "the log names the agent and the percents (unknown here)" "$(log)" "rotated impl ? -> ?"
# the percent comes from hh-context when a session is recorded
jq -nc --arg t "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > $T_STATE/team/impl/session.json
hh-rotate impl --still 2 --settle 1 >/dev/null
assert_contains "the log carries the level, and says the window was a guess" "$(log | tail -1)" "rotated impl 10% (window assumed 1000000) -> 10% (window assumed 1000000)"
# a reading over the assumed window is tokens, not a percent: the log must not print "300000%"
jq -nc '{type:"assistant", isSidechain:false, message:{model:"claude-sonnet-5-5", usage:{input_tokens:1500000, cache_read_input_tokens:0, cache_creation_input_tokens:0, output_tokens:0}}}' > "$T_TMP/big.jsonl"
cp $T_STATE/team/impl/session.json "$T_TMP/impl-session.json"
jq -nc --arg t "$T_TMP/big.jsonl" '{session_id:"s",transcript_path:$t}' > $T_STATE/team/impl/session.json
hh-rotate impl --still 2 --settle 1 >/dev/null
assert_contains "a level over the assumed window is logged as tokens, not a percent" "$(log | tail -1)" "rotated impl 1500000 tokens (window unknown) -> 1500000 tokens (window unknown)"
cp "$T_TMP/impl-session.json" $T_STATE/team/impl/session.json
hh-rotate nobody 2>/dev/null; assert_status "an unknown agent" $? 2
hh-rotate 2>/dev/null; assert_status "usage" $? 64

# a /clear the UI leaves on the input line is cleared and typed again, once
hh_tmux set-environment -g HH_FAKE_CLAUDE retryclear; spawn retry; hh_tmux set-environment -g -u HH_FAKE_CLAUDE
hh-rotate retry --still 2 --settle 1 --max 20 >/dev/null; assert_status "a stuck /clear is retried" $? 0
assert_contains "...and cleared in the end" "$(screen retry)" "CLEARED"
assert_contains "...and the pickup line followed" "$(screen retry)" "GOT: You are proj-retry"

# only on idle: a busy pane and a dialog are never typed into
hh_tmux set-environment -g HH_FAKE_CLAUDE busy; spawn busy; hh_tmux set-environment -g -u HH_FAKE_CLAUDE
n=$(log | wc -l | tr -d ' ')
hh-rotate busy --still 2 --max 5 --settle 1 >/dev/null 2>&1; assert_status "a pane that never goes idle exits 1" $? 1
assert_not() { case "$2" in *"$3"*) bad "$1" ;; *) ok "$1" ;; esac; }
assert_not "nothing was sent to the busy pane" "$(screen busy)" "/clear"
assert_contains "the refusal is logged" "$(log | tail -1)" "not-idle busy"
hh_tmux set-environment -g HH_FAKE_CLAUDE dialog; spawn dlg; hh_tmux set-environment -g -u HH_FAKE_CLAUDE
hh-rotate dlg --still 2 --max 5 --settle 1 >/dev/null 2>&1; assert_status "a dialog exits 5" $? 5
assert_not "nothing was typed into the dialog" "$(screen dlg)" "/clear"
assert_contains "the dialog is logged" "$(log | tail -1)" "dialog dlg"

# a pane that clears but never goes idle again is not sent the pickup line
hh_tmux set-environment -g HH_FAKE_CLAUDE clearbusy; spawn cb; hh_tmux set-environment -g -u HH_FAKE_CLAUDE
hh-rotate cb --still 2 --max 5 --settle 1 >/dev/null 2>&1; assert_status "cleared but never idle exits 1" $? 1
assert_not "no pickup line after a clear that never settled" "$(screen cb | sed -n '/CLEARED/,$p')" "You are proj-cb"
assert_contains "it is logged" "$(log | tail -1)" "cleared-but-not-idle cb"

# only into the pane and process that were recorded: a recycled pane id, an older record and a dead Claude get nothing typed
spawn rec
setteam() { jq --arg a "$1" "(.agents[] | select(.name == \$a)) |= ($2)" $T_STATE/team.json > $T_STATE/team.json.n && mv $T_STATE/team.json.n $T_STATE/team.json; }
getteam() { jq -r --arg a "$1" ".agents[] | select(.name == \$a) | $2" $T_STATE/team.json; }
cleared() { screen rec | grep -c CLEARED; }
good=$(jq -c --arg a rec '.agents[] | select(.name == $a)' $T_STATE/team.json); c0=$(cleared); n=$(log | wc -l | tr -d ' ')
setteam rec '.pane_pid = "1"'
hh-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "another pane process (a recycled id) exits 6" $? 6
assert_eq "...and nothing was typed" "$(cleared)" "$c0"
assert_contains "...and it is logged" "$(log | tail -1)" "identity rec"
setteam rec ".pane_pid = $(printf '%s' "$good" | jq -r .pane_pid | jq -R .) | .pane_started = \"Mon Jan  1 00:00:00 2001\""
hh-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "another start time exits 6" $? 6
assert_eq "...and nothing was typed (start time)" "$(cleared)" "$c0"
setteam rec 'del(.pane_pid, .pane_started)'
hh-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "an older record with no identity exits 6" $? 6
assert_eq "...and nothing was typed (older record)" "$(cleared)" "$c0"
setteam rec ". + {pane_pid: $(printf '%s' "$good" | jq -r .pane_pid | jq -R .), pane_started: $(printf '%s' "$good" | jq -r .pane_started | jq -R .), claude_pid: \"99999\", claude_started: \"Mon Jan  1 00:00:00 2001\"}"
hh-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "a recorded Claude that is gone exits 6" $? 6
assert_eq "...and nothing was typed (no Claude)" "$(cleared)" "$c0"
# the registered Claude process, still alive in the pane, is rotated (the fake Claude is the pane's own process)
setteam rec ". + {claude_pid: $(printf '%s' "$good" | jq -r .pane_pid | jq -R .), claude_started: $(printf '%s' "$good" | jq -r .pane_started | jq -R .)}"
hh-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "the recorded pane and Claude are rotated" $? 0
setteam rec '.pane_pid = "1"'
hh-self-rotate rec --still 2 --settle 1 >/dev/null 2>&1; assert_status "self-rotate forks" $? 0
t=0; while ! grep -q "not the one recorded" $T_STATE/rotate.out 2>/dev/null && [ $t -lt 20 ]; do sleep 1; t=$((t + 1)); done
assert_contains "self-rotate refuses a mismatched pane, nothing typed" "$(cat $T_STATE/rotate.out 2>/dev/null)" "not the one recorded"
rm -f $T_STATE/rotate.out

# the identity is checked again just before each send: a pane that changed during the wait for an idle prompt gets nothing
spawn mid; mpane=$(paneof mid)
( hh-rotate mid --still 4 --settle 1 --max 30 >/dev/null 2>&1; echo $? > "$T_TMP/mid.rc" ) & midjob=$!
sleep 1; setteam mid '.pane_pid = "1"'; wait "$midjob"
assert_eq "an identity that changed during the wait exits 6" "$(cat "$T_TMP/mid.rc")" "6"
assert_eq "...and nothing was typed" "$(hh_tmux capture-pane -p -J -S - -t "$mpane" | grep -c CLEARED)" "0"
assert_contains "...and it is logged" "$(log | tail -1)" "identity mid"

# ...also between the clear and its pickup line, and before the retried /clear
hh_tmux set-environment -g HH_FAKE_CLAUDE idle; spawn mid2; hh_tmux set-environment -g -u HH_FAKE_CLAUDE; m2=$(paneof mid2)
( hh-rotate mid2 --still 2 --settle 5 --max 30 >/dev/null 2>&1; echo $? > "$T_TMP/mid2.rc" ) & job=$!
t=0; until hh_tmux capture-pane -p -J -S - -t "$m2" | grep -q CLEARED || [ $t -ge 100 ]; do sleep 0.2; t=$((t + 1)); done
setteam mid2 '.pane_pid = "1"'; wait "$job"
assert_eq "an identity that changed after the clear exits 6" "$(cat "$T_TMP/mid2.rc")" "6"
assert_not "...and the pickup line was not typed after the clear" "$(hh_tmux capture-pane -p -J -S - -t "$m2" | sed -n '/^CLEARED/,$p')" "GOT: You are"
hh_tmux set-environment -g HH_FAKE_CLAUDE retryclear; spawn mid3; hh_tmux set-environment -g -u HH_FAKE_CLAUDE; m3=$(paneof mid3)
( hh-rotate mid3 --still 2 --settle 5 --max 30 >/dev/null 2>&1; echo $? > "$T_TMP/mid3.rc" ) & job=$!
t=0; until hh_tmux capture-pane -p -J -S - -t "$m3" | grep -q '❯.*/clear' || [ $t -ge 100 ]; do sleep 0.2; t=$((t + 1)); done
setteam mid3 '.pane_pid = "1"'; wait "$job"
assert_eq "an identity that changed before the retried /clear exits 6" "$(cat "$T_TMP/mid3.rc")" "6"
assert_eq "...and no second /clear was typed" "$(hh_tmux capture-pane -p -J -S - -t "$m3" | grep -c CLEARED)" "0"

# a tracked .hivehouse is refused
echo x > $T_STATE/leak; git add -f $T_STATE/leak
hh-rotate impl --still 2 --settle 1 >/dev/null 2>&1; assert_status "tracked $T_STATE refused" $? 3
hh-self-rotate impl --still 2 --settle 1 >/dev/null 2>&1; assert_status "self-rotate refuses a tracked $T_STATE before forking" $? 3
[ -e $T_STATE/rotate.out ] && bad "self-rotate wrote rotate.out into a tracked $T_STATE" || ok "...and wrote nothing"
git rm -qf --cached $T_STATE/leak

# hh-self-rotate returns at once and the rotation finishes detached
spawn selfy
t0=$(date +%s)
hh-self-rotate selfy --still 2 --settle 1; assert_status "self-rotate returns" $? 0
t1=$(date +%s); [ $((t1 - t0)) -le 2 ] && ok "self-rotate returned within 2 s" || bad "self-rotate took $((t1 - t0)) s"
for i in $(seq 1 25); do case "$(log)" in *"rotated selfy"*) break ;; esac; sleep 1; done
assert_contains "the detached rotation cleared the pane" "$(screen selfy)" "CLEARED"
assert_eq "...and sent the pickup line a second time" "$(screen selfy | grep -c "GOT: You are proj-selfy")" "2"
assert_contains "...and logged it" "$(log)" "rotated selfy"
# a fresh repo: self-rotate sets .hivehouse up through hh_ensure_state, so it is excluded and a `git add -A` cannot track it
fresh=$(t_repo fresh); (cd "$fresh" && hh-self-rotate nobody --still 1 --settle 1 >/dev/null 2>&1)
grep -qx '/'"$T_STATE"'/' "$fresh/.git/info/exclude" && ok "self-rotate excludes $T_STATE in a fresh repo" || bad "self-rotate left $T_STATE unexcluded in a fresh repo"
[ -z "$(git -C "$fresh" status --porcelain)" ] && ok "...so the repo stays clean" || bad "the fresh repo shows untracked files: $(git -C "$fresh" status --porcelain)"
cd /; t_teardown; t_done
