#!/usr/bin/env bash
# hh-spawn --close <agent>: an agent the orchestrator has ended leaves the team (team.json, the pane registry, the manifest's pane entry)
# so nothing lists it as "not running" again; its worktree, branch, handoff and role stay. Refused while its pane is live.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
spawn() { hh-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 6 "${@:2}" 2>&1; }
paneof() { jq -r --arg a "$1" '.agents[]|select(.name==$a).pane' $T_STATE/team.json; }
inteam() { jq -r --arg a "$1" '[.agents[]? | select(.name == $a)] | length' $T_STATE/team.json; }
regfiles() { local f n=0; for f in "$(hh_registry_dir)"/*.json; do [ -f "$f" ] && [ "$(jq -r '.agent + "@" + .project' "$f")" = "$1@$r" ] && n=$((n + 1)); done; echo $n; }
inmanifest() { hh-manifest list --kind tmux | jq -r --arg a "$1" 'select(.agent == $a) | .agent' | wc -l | tr -d ' '; }

spawn gone >/dev/null; spawn live >/dev/null
spawn wtagent --worktree "$T_TMP/proj-wt" --branch feat-wt --base main >/dev/null
assert_eq "an agent is in the team" "$(inteam gone)" "1"
assert_eq "...in the pane registry" "$(regfiles gone)" "1"
assert_eq "...and on the manifest" "$(inmanifest gone)" "1"
hh-spawn --close live >/dev/null 2>"$T_TMP/e"; assert_status "a live pane is not closed" $? 4
assert_contains "...it says to end the agent first" "$(cat "$T_TMP/e")" "end it first"
assert_eq "...and it is still in the team" "$(inteam live)" "1"

hh_tmux kill-pane -t "$(paneof gone)"; sleep 1
out=$(hh-spawn --close gone 2>&1); assert_status "an agent whose pane is gone is closed" $? 0
assert_contains "...and says so" "$out" "closed gone"
assert_eq "...it is out of team.json" "$(inteam gone)" "0"
assert_eq "...out of the pane registry" "$(regfiles gone)" "0"
assert_eq "...and off the manifest" "$(inmanifest gone)" "0"
assert_eq "...the others stay" "$(inteam live)$(inmanifest live)$(regfiles live)" "111"
assert_contains "...its handoff stays" "$(cat $T_STATE/handoffs/gone.md)" "START HERE"
[ -f $T_STATE/team/gone/role.md ] && ok "...and its role copy" || bad "the role copy was removed"
assert_contains "hh-context --all no longer lists it" "$(hh-context --all)" "live"
case "$(hh-context --all)" in *gone*) bad "hh-context still lists the closed agent" ;; *) ok "...and not the closed one" ;; esac
hh-spawn --respawn gone >/dev/null 2>&1; assert_status "a closed agent is not respawned (it is not on the team)" $? 2
hh-spawn --close gone >/dev/null 2>&1; assert_status "closing it again: no such agent" $? 2
hh-spawn --close nobody >/dev/null 2>&1; assert_status "an unknown name" $? 2
hh-spawn --close 'bad name;' >/dev/null 2>&1; assert_status "a bad name" $? 4

# a worktree agent: the worktree and the branch stay
hh_tmux kill-pane -t "$(paneof wtagent)"; sleep 1
hh-spawn --close wtagent >/dev/null 2>&1; assert_status "an agent with a worktree is closed" $? 0
[ -d "$T_TMP/proj-wt" ] && ok "...its worktree stays" || bad "the worktree was removed"
git -C "$r" rev-parse --verify -q feat-wt >/dev/null && ok "...and its branch" || bad "the branch was removed"
assert_eq "...its worktree is still on the manifest (cleanup owns it)" "$(hh-manifest list --kind worktree | jq -r 'select(.path == "'"$T_TMP/proj-wt"'") | .path' | wc -l | tr -d ' ')" "1"

# another project's registry file for an agent of the same name is not touched
other=$(t_repo other)
jq -nc --arg p "$other" '{project:$p, agent:"live", pane:"%77", socket:"/nonexistent", pane_pid:"1", pane_started:"x"}' > "$(hh_registry_dir)/other-project-live.json"
hh_tmux kill-pane -t "$(paneof live)"; sleep 1
hh-spawn --close live >/dev/null 2>&1; assert_status "an agent of the same name as another project's is closed" $? 0
[ -f "$(hh_registry_dir)/other-project-live.json" ] && ok "...and the other project's registry file for its own is left alone" || bad "--close removed another project's registry file"
rm -f "$(hh_registry_dir)/other-project-live.json"

# the orchestrator is never closed, and a record with no identity proves nothing
jq '.agents += [{name:"orchestrator",pane:"%1",pane_pid:"1",pane_started:"x",claude_pid:"1",claude_started:"x"}, {name:"noid",pane:"%9"}]' $T_STATE/team.json > $T_TMP/t.json && mv $T_TMP/t.json $T_STATE/team.json
hh-spawn --close orchestrator >/dev/null 2>"$T_TMP/e"; assert_status "the orchestrator is refused" $? 4
assert_contains "...saying why" "$(cat "$T_TMP/e")" "orchestrator"
assert_eq "...and stays" "$(inteam orchestrator)" "1"
hh-spawn --close noid >/dev/null 2>&1; assert_status "a record with no identity is refused: nothing proves it stopped" $? 4
# usage
hh-spawn --close >/dev/null 2>&1; assert_status "--close needs a name" $? 64
hh-spawn --close live --model x >/dev/null 2>&1; assert_status "--close takes nothing else" $? 64
# the orchestrator's guidance and the docs
assert_contains "the start skill tells the orchestrator to close an agent it ends" "$(cat "$HH_REPO_ROOT/skills/start/SKILL.md")" "hh-spawn --close"
assert_contains "the docs describe it" "$(cat "$HH_REPO_ROOT/docs/state-and-restarts.md")" "hh-spawn --close"
t_done
