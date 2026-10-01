#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
# set-environment -g (below) is how a test hands the fake claude its behaviour: hm-spawn passes a pane only what it names
# (A22), so the server's global environment is the one channel that is not production code.
# the server starts WITHOUT the machine home, so a pane that has it got it from hm-spawn (A3)
env -u HIVEMIND_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
spawn() { hm-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 15 "${@:2}"; }

pane=$(spawn impl --worktree "$T_TMP/proj-impl" --branch feat/x --base main --window 123456)
assert_status "spawn ok" $? 0
assert_contains "pane id" "$pane" "%"
assert_eq "role copied" "$(cat .hivemind/team/impl/role.md)" "role"
assert_eq "rules copied" "$(cat .hivemind/team/impl/RULES.md)" "rules"
assert_contains "handoff skeleton" "$(cat .hivemind/handoffs/impl.md)" "START HERE"
assert_eq "worktree on manifest" "$(hm-manifest list --kind worktree | jq -r .path)" "$T_TMP/proj-impl"
assert_eq "worktree is on its branch" "$(git -C "$T_TMP/proj-impl" rev-parse --abbrev-ref HEAD)" "feat/x"
assert_eq "tmux on manifest" "$(hm-manifest list --kind tmux | jq -r .pane)" "$pane"
assert_eq "registered" "$(jq -r .agent "$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$pane").json")" "impl"
assert_eq "registered project" "$(jq -r .project "$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$pane").json")" "$r"
assert_eq "team.json model" "$(jq -r '.agents[0].model' .hivemind/team.json)" "sonnet"
assert_eq "team.json window" "$(jq -r '.agents[0].window' .hivemind/team.json)" "123456"
assert_eq "team.json pane" "$(jq -r '.agents[0].pane' .hivemind/team.json)" "$pane"
screen=$(hm_tmux capture-pane -p -J -S - -t "$pane")
assert_contains "named for project and agent" "$screen" "ARGV: proj-impl"
assert_contains "model passed" "$screen" "ARGV: sonnet"
assert_contains "mode passed" "$screen" "ARGV: auto"
assert_contains "machine home handed to the pane (A3)" "$screen" "HIVEMIND_HOME=$HIVEMIND_HOME"
assert_contains "agent and project handed to the pane" "$screen" "HM_AGENT=impl HM_PROJECT=$r"
assert_contains "pickup line sent once idle" "$screen" "Read $r/.hivemind/handoffs/impl.md"
assert_contains "pickup line names the orchestrator" "$screen" "Report to proj-orchestrator"
allowed=$(printf '%s\n' "$screen" | grep -A0 'ARGV: Bash(hm-slot status)' | sed 's/^ARGV: //')
assert_eq "allowed tools are exactly the A16 list" "$allowed" "Bash(hm-slot status) Bash(hm-slot release *) Bash(hm-context *) Bash(hm-gate-verify *) Bash(hm-settings resolve *) Bash(hm-disk *)"
for banned in hm-spawn hm-rotate hm-self-rotate hm-push hm-cleanup "hm-gate " "hm-slot run" "hm-slot acquire" hm-remote-sync "Bash(*" "Read" "Write" "Bash(git" "hm-manifest"; do
  case "$allowed" in *"$banned"*) bad "allowed tools must not name $banned" ;; *) ok "allowed tools do not name $banned" ;; esac
done

spawn x --mode yolo >/dev/null 2>&1; assert_status "unknown mode refused" $? 4
hm-spawn --agent x --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model m --effort e --mode bypassPermissions >/dev/null 2>&1
assert_status "bypassPermissions refused" $? 4
spawn x --worktree "$T_TMP/proj-x" --branch -evil --base main >/dev/null 2>&1; assert_status "branch starting with - refused" $? 4
spawn x --worktree "$T_TMP/proj-x" --branch b --base -evil >/dev/null 2>&1; assert_status "base starting with - refused" $? 4
[ ! -e "$T_TMP/proj-x" ] && ok "refusals created nothing" || bad "a refused spawn created a worktree"
mkdir "$T_TMP/taken"
spawn y --worktree "$T_TMP/taken" --branch b --base main >/dev/null 2>&1; assert_status "existing unlisted path refused" $? 4
spawn "../evil" >/dev/null 2>&1; assert_status "bad agent name refused" $? 4
for loc in C en_US.UTF-8; do   # and é, ß and a fullwidth letter, in a model, an effort or a branch
  (export LC_ALL=$loc; spawn x --model sonné >/dev/null 2>&1); assert_status "a non-ASCII model is refused under $loc" $? 4
  (export LC_ALL=$loc; spawn x --effort ｈigh >/dev/null 2>&1); assert_status "a non-ASCII effort is refused under $loc" $? 4
  (export LC_ALL=$loc; spawn x --worktree "$T_TMP/proj-loc" --branch feat/é --base main >/dev/null 2>&1); assert_status "a non-ASCII branch is refused under $loc" $? 4
  (export LC_ALL=$loc; spawn x --worktree "$T_TMP/proj-loc" --branch b --base maiß >/dev/null 2>&1); assert_status "a non-ASCII base is refused under $loc" $? 4
done
[ ! -e "$T_TMP/proj-loc" ] && ok "and none of them made a worktree" || bad "a non-ASCII refusal made a worktree"
for loc in C en_US.UTF-8; do   # bash 3.2's [a-z] takes capitals in en_US.UTF-8, so the rule is checked under both
  (export LC_ALL=$loc; spawn Upper >/dev/null 2>&1); assert_status "a capital in an agent name is refused under $loc" $? 4
done
[ ! -e "$r/.hivemind/evil" ] && [ -z "$(hm_tmux list-windows -a -F '#{window_name}' | grep evil)" ] && ok "a refused name wrote and started nothing" || bad "a refused agent name left state behind"
spawn z --no-claude cat >/dev/null 2>&1; assert_status "no --no-claude (A21)" $? 64

# a dialog is never answered: stop with exit 5 and nothing typed
hm_tmux set-environment -g HM_FAKE_CLAUDE dialog
pane=$(spawn dlg 2>/dev/null); assert_status "a dialog stops the spawn" $? 5
assert_eq "no pickup line typed into a dialog" "$(hm_tmux capture-pane -p -J -S - -t "$(jq -r '.agents[]|select(.name=="dlg").pane' .hivemind/team.json)" | grep -c 'Read .*handoffs')" "0"
hm_tmux set-environment -g -u HM_FAKE_CLAUDE

# model and effort are not options to claude
spawn m1 --model -x >/dev/null 2>&1; assert_status "a model starting with - refused" $? 4
hm-spawn --agent m2 --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort --dangerous --mode auto >/dev/null 2>&1; assert_status "an effort starting with - refused" $? 4

# the manifest is written before the registry, so a failed registry write still leaves the pane cleanable
mkdir -p "$(hm_registry_dir)"; chmod 555 "$(hm_registry_dir)"
spawn late >/dev/null 2>&1; late_rc=$?
chmod 755 "$(hm_registry_dir)"
[ "$late_rc" -ne 0 ] && ok "a failed registry write fails the spawn" || bad "a failed registry write was ignored"
assert_eq "...and the pane is on the manifest" "$(hm-manifest list --kind tmux | jq -r 'select(.agent=="late")|.agent')" "late"

# register-self (F1): the orchestrator's own pane, no window, no claude, and never on the manifest
tmux_o=$(hm_tmux new-session -d -s orch -c "$r" -P -F '#{pane_id}' -e "HIVEMIND_HOME=$HIVEMIND_HOME" "hm-spawn --self --agent orchestrator --window 200000 >$T_TMP/self.out 2>&1; sleep 30")
sleep 2
k=$(hm_pane_key "$HM_TMUX_SOCKET" "$tmux_o")
assert_eq "self: registered" "$(jq -r .agent "$(hm_registry_dir)/$k.json")" "orchestrator"
assert_eq "self: team.json" "$(jq -r '.agents[]|select(.name=="orchestrator")|.pane' .hivemind/team.json)" "$tmux_o"
assert_eq "self: window" "$(jq -r '.agents[]|select(.name=="orchestrator")|.window' .hivemind/team.json)" "200000"
assert_eq "self: not on the manifest (cleanup would kill the owner's pane)" "$(hm-manifest list --kind tmux | jq -r --arg p "$tmux_o" 'select(.pane==$p)|.pane')" ""
hm_tmux send-keys -t "$tmux_o" C-c 2>/dev/null
n1=$(jq '.agents|length' .hivemind/team.json)
tmux_o2=$(hm_tmux new-session -d -s orch2 -c "$r" -P -F '#{pane_id}' -e "HIVEMIND_HOME=$HIVEMIND_HOME" "hm-spawn --self --agent orchestrator --window 200000 >$T_TMP/self2.out 2>&1; sleep 30")
sleep 2
assert_eq "self: idempotent per agent (one orchestrator entry)" "$(jq '[.agents[]|select(.name=="orchestrator")]|length' .hivemind/team.json)" "1"
assert_eq "self: second call moves the entry to the calling pane" "$(jq -r '.agents[]|select(.name=="orchestrator")|.pane' .hivemind/team.json)" "$tmux_o2"
hm-spawn --self --agent orchestrator --window 1 >/dev/null 2>&1; assert_status "self outside tmux refused" $? 2
hm-spawn --self --agent orchestrator --window 1 --model m >/dev/null 2>&1; assert_status "self takes no spawn arguments" $? 64
# --self for a name that belongs to a spawned pane is refused (it would re-point a managed agent at the caller)
hm_tmux new-session -d -s orchx -c "$r" -e "HIVEMIND_HOME=$HIVEMIND_HOME" "hm-spawn --self --agent impl --window 1 >$T_TMP/selfx.out 2>&1; echo rc=\$? >>$T_TMP/selfx.out; sleep 30"
sleep 2
assert_contains "self refused for a managed agent's name" "$(cat "$T_TMP/selfx.out")" "rc=4"
assert_eq "...and impl's pane is unchanged" "$(jq -r '.agents[]|select(.name=="impl").pane' .hivemind/team.json)" "$(hm-manifest list --kind tmux | jq -r 'select(.agent=="impl")|.pane')"
cd /; t_teardown; t_done
