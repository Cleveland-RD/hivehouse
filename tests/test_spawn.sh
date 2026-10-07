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
assert_eq "role copied" "$(cat $T_STATE/team/impl/role.md)" "role"
assert_eq "rules copied" "$(cat $T_STATE/team/impl/RULES.md)" "rules"
assert_contains "handoff skeleton" "$(cat $T_STATE/handoffs/impl.md)" "START HERE"
assert_eq "worktree on manifest" "$(hm-manifest list --kind worktree | jq -r .path)" "$T_TMP/proj-impl"
assert_eq "worktree is on its branch" "$(git -C "$T_TMP/proj-impl" rev-parse --abbrev-ref HEAD)" "feat/x"
assert_eq "tmux on manifest" "$(hm-manifest list --kind tmux | jq -r .pane)" "$pane"
assert_eq "registered" "$(jq -r .agent "$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$pane").json")" "impl"
assert_eq "registered project" "$(jq -r .project "$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$pane").json")" "$r"
rf="$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$pane").json"
assert_eq "registered with the pane's process and start time" "$(jq -r '.pane_pid + "|" + .pane_started' "$rf")" "$(hm_pane_identity "$HM_TMUX_SOCKET" "$pane" | tr '\t' '|')"
assert_eq "team.json model" "$(jq -r '.agents[0].model' $T_STATE/team.json)" "sonnet"
assert_eq "team.json window" "$(jq -r '.agents[0].window' $T_STATE/team.json)" "123456"
assert_eq "team.json pane" "$(jq -r '.agents[0].pane' $T_STATE/team.json)" "$pane"
screen=$(hm_tmux capture-pane -p -J -S - -t "$pane")
assert_contains "named for project and agent" "$screen" "ARGV: proj-impl"
assert_contains "model passed" "$screen" "ARGV: sonnet"
assert_contains "mode passed" "$screen" "ARGV: auto"
assert_contains "machine home handed to the pane (A3)" "$screen" "HIVEMIND_HOME=$HIVEMIND_HOME"
assert_contains "agent and project handed to the pane" "$screen" "HM_AGENT=impl HM_PROJECT=$r"
assert_contains "pickup line sent once idle" "$screen" "Read $r/$T_STATE/handoffs/impl.md"
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
[ ! -e "$r/$T_STATE/evil" ] && [ -z "$(hm_tmux list-windows -a -F '#{window_name}' | grep evil)" ] && ok "a refused name wrote and started nothing" || bad "a refused agent name left state behind"
spawn z --no-claude cat >/dev/null 2>&1; assert_status "no --no-claude (A21)" $? 64

# a dialog is never answered: stop with exit 5 and nothing typed
hm_tmux set-environment -g HM_FAKE_CLAUDE dialog
pane=$(spawn dlg 2>/dev/null); assert_status "a dialog stops the spawn" $? 5
assert_eq "no pickup line typed into a dialog" "$(hm_tmux capture-pane -p -J -S - -t "$(jq -r '.agents[]|select(.name=="dlg").pane' $T_STATE/team.json)" | grep -c 'Read .*handoffs')" "0"
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

# a pane whose process cannot be read is never registered: no file without identity (tmux answers the socket, not the pid)
mkdir -p "$T_TMP/shim"; REALTMUX=$(command -v tmux)
printf '#!/bin/sh\ncase "$*" in *pane_pid*) exit 1 ;; esac\nexec %s "$@"\n' "$REALTMUX" > "$T_TMP/shim/tmux"; chmod +x "$T_TMP/shim/tmux"
ghost=$(hm_tmux new-session -d -s ghost -c "$r" -P -F '#{pane_id}' 'sleep 30')
(cd "$r" && PATH="$T_TMP/shim:$PATH" TMUX_PANE="$ghost" hm-spawn --self --agent ghostly --window 1 >/dev/null 2>&1); assert_status "--self on a pane whose process cannot be read fails" $? 1
[ -e "$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$ghost").json" ] && bad "a registry file without identity was written" || ok "...and no registry file was written"

# the pane's own process is claude, whatever shell tmux runs the command with: here a shell that never execs its last command
printf '#!/bin/bash\nif [ "$1" = -c ]; then exec bash -c "$2; :"; fi\nexec bash "$@"\n' > "$T_TMP/forksh"; chmod +x "$T_TMP/forksh"
hm_tmux set-option -g default-shell "$T_TMP/forksh"; fpane=$(spawn fk 2>/dev/null); hm_tmux set-option -gu default-shell
fpid=$(hm_pane_pid "$HM_TMUX_SOCKET" "$fpane"); hm_is_claude "$fpid" && ok "a spawned pane's own process is claude even under a shell that forks" || bad "the pane's process is $(ps -o args= -p "$fpid"), not claude"

# a spawned agent's SessionStart hook writes its session (its pane process is Claude), and a nested Claude below it does not
hm_tmux set-environment -g HM_FAKE_CLAUDE hook; hpane=$(spawn hk 2>/dev/null); hm_tmux set-environment -g -u HM_FAKE_CLAUDE
sleep 6
assert_eq "a spawned agent's own Claude records its session" "$(jq -r .session_id $T_STATE/team/hk/session.json 2>/dev/null)" "sp"
hm_tmux set-environment -g HM_FAKE_CLAUDE nested; npane=$(spawn nst 2>/dev/null); hm_tmux set-environment -g -u HM_FAKE_CLAUDE
sleep 6
[ -e $T_STATE/team/nst/session.json ] && bad "a nested Claude overwrote a spawned agent's session" || ok "a nested Claude below a spawned agent writes nothing"
[ -e "$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$(jq -r '.agents[]|select(.name=="nst").pane' $T_STATE/team.json)").json" ] \
  && ok "...and the agent's registry file stays" || bad "a nested Claude removed the agent's registry file"

# --self runs inside a Claude session: a stand-in whose argv reads as one (an interpreter running a script named claude)
mkdir -p "$T_TMP/cl"; printf '#!/usr/bin/env bash\nhm-spawn "$@"; echo rc=$? >>"$SELF_OUT"; sleep 30\n' > "$T_TMP/cl/claude"
noclaude=$(hm_tmux new-session -d -s noclaude -c "$r" -P -F '#{pane_id}' -e "HIVEMIND_HOME=$HIVEMIND_HOME" "hm-spawn --self --agent orchestrator --window 1 >$T_TMP/noclaude.out 2>&1; echo rc=\$? >>$T_TMP/noclaude.out; sleep 30")
sleep 2
assert_contains "--self outside a Claude session is refused" "$(cat "$T_TMP/noclaude.out")" "rc=1"
[ -e "$(hm_registry_dir)/$(hm_pane_key "$HM_TMUX_SOCKET" "$noclaude").json" ] && bad "--self registered without a Claude ancestor" || ok "...and nothing was registered for it"

# register-self (F1): the orchestrator's own pane, no window, no claude, and never on the manifest
tmux_o=$(hm_tmux new-session -d -s orch -c "$r" -P -F '#{pane_id}' -e "HIVEMIND_HOME=$HIVEMIND_HOME" -e "SELF_OUT=$T_TMP/self.out" "bash $T_TMP/cl/claude --self --agent orchestrator --window 200000 >$T_TMP/self.out 2>&1")
sleep 2
k=$(hm_pane_key "$HM_TMUX_SOCKET" "$tmux_o")
assert_eq "self: registered" "$(jq -r .agent "$(hm_registry_dir)/$k.json")" "orchestrator"
assert_eq "self: registered with the pane's identity" "$(jq -r '.pane_pid + "|" + .pane_started' "$(hm_registry_dir)/$k.json")" "$(hm_pane_identity "$HM_TMUX_SOCKET" "$tmux_o" | tr '\t' '|')"
assert_eq "self: the Claude process is recorded in the registry and team.json alike" "$(jq -r '.claude_pid + "|" + .claude_started' "$(hm_registry_dir)/$k.json")" "$(jq -r '.agents[]|select(.name=="orchestrator")|.claude_pid + "|" + .claude_started' $T_STATE/team.json)"
cpid=$(jq -r .claude_pid "$(hm_registry_dir)/$k.json"); hm_claude_is "$cpid" "$(jq -r .claude_started "$(hm_registry_dir)/$k.json")" && ok "...and it is that live Claude process" || bad "the recorded Claude process is not live Claude"
assert_eq "a spawned agent records no Claude process (its pane lives as long as its command)" "$(jq -r 'select(.agent=="impl")|.claude_pid // "none"' "$rf")" "none"
assert_eq "self: team.json" "$(jq -r '.agents[]|select(.name=="orchestrator")|.pane' $T_STATE/team.json)" "$tmux_o"
assert_eq "self: window" "$(jq -r '.agents[]|select(.name=="orchestrator")|.window' $T_STATE/team.json)" "200000"
assert_eq "self: not on the manifest (cleanup would kill the owner's pane)" "$(hm-manifest list --kind tmux | jq -r --arg p "$tmux_o" 'select(.pane==$p)|.pane')" ""
hm_tmux send-keys -t "$tmux_o" C-c 2>/dev/null
n1=$(jq '.agents|length' $T_STATE/team.json)
tmux_o2=$(hm_tmux new-session -d -s orch2 -c "$r" -P -F '#{pane_id}' -e "HIVEMIND_HOME=$HIVEMIND_HOME" -e "SELF_OUT=$T_TMP/self2.out" "bash $T_TMP/cl/claude --self --agent orchestrator --window 200000 >$T_TMP/self2.out 2>&1")
sleep 2
assert_eq "self: idempotent per agent (one orchestrator entry)" "$(jq '[.agents[]|select(.name=="orchestrator")]|length' $T_STATE/team.json)" "1"
assert_eq "self: second call moves the entry to the calling pane" "$(jq -r '.agents[]|select(.name=="orchestrator")|.pane' $T_STATE/team.json)" "$tmux_o2"
hm-spawn --self --agent orchestrator --window 1 >/dev/null 2>&1; assert_status "self outside tmux refused" $? 2
hm-spawn --self --agent orchestrator --window 1 --model m >/dev/null 2>&1; assert_status "self takes no spawn arguments" $? 64
# --self for a name that belongs to a spawned pane is refused (it would re-point a managed agent at the caller)
hm_tmux new-session -d -s orchx -c "$r" -e "HIVEMIND_HOME=$HIVEMIND_HOME" "hm-spawn --self --agent impl --window 1 >$T_TMP/selfx.out 2>&1; echo rc=\$? >>$T_TMP/selfx.out; sleep 30"
sleep 2
assert_contains "self refused for a managed agent's name" "$(cat "$T_TMP/selfx.out")" "rc=4"
assert_eq "...and impl's pane is unchanged" "$(jq -r '.agents[]|select(.name=="impl").pane' $T_STATE/team.json)" "$(hm-manifest list --kind tmux | jq -r 'select(.agent=="impl")|.pane')"
# with no --session an agent goes beside the pane that spawns it, when that pane is on the server it is spawned on
assert_eq "outside tmux: the project's own session" "$(jq -r '.agents[]|select(.name=="impl").session' $T_STATE/team.json)" "hm-$(hm_project_key "$r")"
orchpane=$(hm_tmux new-session -d -s myorch -c "$r" -P -F '#{pane_id}' 'sleep 600')
TMUX="$HM_TMUX_SOCKET,1,0" TMUX_PANE="$orchpane" spawn beside >/dev/null; assert_status "spawn from inside a pane" $? 0
assert_eq "...lands in that pane's own session" "$(hm_tmux display-message -p -t "$(jq -r '.agents[]|select(.name=="beside").pane' $T_STATE/team.json)" '#{session_name}')" "myorch"
assert_eq "...and team.json says so" "$(jq -r '.agents[]|select(.name=="beside").session' $T_STATE/team.json)" "myorch"
TMUX="/nonexistent/other-server,1,0" TMUX_PANE="$orchpane" spawn elsewhere >/dev/null; assert_status "spawn from a pane on another server" $? 0
assert_eq "...goes to the project's own session" "$(jq -r '.agents[]|select(.name=="elsewhere").session' $T_STATE/team.json)" "hm-$(hm_project_key "$r")"
TMUX="$HM_TMUX_SOCKET,1,0" TMUX_PANE="$orchpane" spawn named --session chosen >/dev/null; assert_status "spawn with --session from inside a pane" $? 0
assert_eq "...--session still wins" "$(jq -r '.agents[]|select(.name=="named").session' $T_STATE/team.json)" "chosen"
# the agent's statusLine is hm-statusline (Claude Code's window for hm-context), which runs the owner's own; the plugin's path
# and the project's are quoted, so a space in either works
echo '{"statusLine":{"type":"command","command":"echo OWNER; exit 4","padding":2}}' > "$CLAUDE_CONFIG_DIR/settings.json"
mkdir -p "$T_TMP/plug in"; cp -R "$HM_REPO_ROOT/bin" "$T_TMP/plug in/"; t_plugin_beside "$T_TMP/plug in/bin"
sp=$(t_repo "my proj"); cd "$sp"
spane=$("$T_TMP/plug in/bin/hm-spawn" --agent sl --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 15)
assert_status "spawn with spaces in the plugin's and the project's paths" $? 0
sset=$(hm_tmux capture-pane -p -J -S - -t "$spane" | grep '^ARGV: {"statusLine"' | sed 's/^ARGV: //')
assert_eq "--settings carries one statusLine" "$(printf '%s' "$sset" | jq -r '.statusLine.type')" "command"
assert_eq "...keeping the owner's other keys" "$(printf '%s' "$sset" | jq -r '.statusLine.padding')" "2"
assert_eq "the owner's statusLine is recorded for the agent" "$(jq -r .command "$sp/$T_STATE/team/sl/statusline.json")" "echo OWNER; exit 4"
scmd=$(printf '%s' "$sset" | jq -r '.statusLine.command')
out=$(printf '%s' '{"session_id":"q","context_window":{"context_window_size":1000000,"used_percentage":1}}' | /bin/sh -c "$scmd"); rc=$?
assert_eq "run as Claude Code runs it, it shows the owner's line" "$out" "OWNER"
assert_status "...with the owner's status" "$rc" 4
assert_eq "...and keeps the window in the agent's dir" "$(jq -r .window "$sp/$T_STATE/team/sl/context.json")" "1000000"
rm "$CLAUDE_CONFIG_DIR/settings.json"
"$T_TMP/plug in/bin/hm-spawn" --agent sl2 --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 15 >/dev/null
[ ! -e "$sp/$T_STATE/team/sl2/statusline.json" ] && ok "no owner statusLine: none recorded" || bad "an owner statusLine was recorded from nowhere"
cd /; t_teardown; t_done
