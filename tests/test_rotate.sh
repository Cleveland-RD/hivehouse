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
cd /; t_teardown; t_done
