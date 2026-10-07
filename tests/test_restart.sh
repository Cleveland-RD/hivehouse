#!/usr/bin/env bash
# After a restart (the machine's, or tmux's): an agent whose recorded process is gone reads as not running, its last
# level kept, and comes back from its own record with hm-spawn --respawn, resuming from its handoff.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
env -u HIVEHOUSE_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
# the repository is trusted in this run's own Claude config, so hm-spawn's folder-trust warning (a worktree stops at the dialog until its main repository is trusted) is not on stderr here
jq -nc --arg p "$(cd "$r" && pwd -P)" '{projects:{($p):{hasTrustDialogAccepted:true}}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
spawn() { hm-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 15 "${@:2}"; }
S="$r/$T_STATE"
addteam() { jq --argjson a "$1" '.agents += [$a]' "$S/team.json" > "$S/team.json.t" && mv "$S/team.json.t" "$S/team.json"; }
me_started=$(hm_lstart $$)

pane=$(spawn impl --worktree "$T_TMP/proj-impl" --branch feat/x --base main --window 123456); assert_status "spawn impl" $? 0
pane2=$(spawn rev); assert_status "spawn rev, no worktree" $? 0
jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > "$S/team/impl/session.json"

# ---- the one check: is the agent still running as recorded? ----
hm_team_agent_is "$r" impl; assert_status "a spawned agent runs as recorded" $? 0
hm_team_agent_is "$r" nobody; assert_status "an agent not on the team" $? 3
addteam '{"name":"old","pane":"%3"}'
hm_team_agent_is "$r" old; assert_status "a record without identity proves nothing" $? 3
# its process alive, but no tmux answers at the recorded socket: nothing can be told
addteam "$(jq -nc --arg p "$$" --arg s "$me_started" '{name:"ghost", pane:"%9", socket:"/nonexistent/tmux.sock", pane_pid:$p, pane_started:$s}')"
hm_team_agent_is "$r" ghost; assert_status "a live process tmux cannot vouch for: cannot tell" $? 2
# the orchestrator's pane is the owner's shell, which outlives it: its own Claude is what counts
addteam "$(jq -nc --arg p "$$" --arg s "$me_started" --arg k "$HM_TMUX_SOCKET" '{name:"orchestrator", pane:"%0", socket:$k, pane_pid:$p, pane_started:$s, claude_pid:"99999", claude_started:"Mon Jan  1 00:00:00 2001"}')"
hm_team_agent_is "$r" orchestrator; assert_status "an orchestrator whose Claude is gone is not running" $? 1

before=$(hm-context impl)
case "$before" in *"not running"*) bad "a running agent is marked: $before" ;; *) ok "a running agent is not marked" ;; esac

# ---- the restart: the agents' processes are gone ----
hm_tmux kill-pane -t "$pane"; hm_tmux kill-pane -t "$pane2"; sleep 1
hm_team_agent_is "$r" impl; assert_status "its process gone: not running" $? 1
assert_eq "hm-context keeps the last level and marks it" "$(hm-context impl)" "$before (not running)"
all=$(hm-context --all)
assert_contains "--all marks it too" "$all" "impl $before (not running)"
assert_contains "...and an agent with no level" "$all" "rev ? (not running)"
assert_contains "...and the orchestrator whose Claude is gone" "$all" "orchestrator ? (not running)"
assert_contains "...and lists the one it cannot tell about" "$all" "ghost ?"
case "$all" in *"ghost ? (not running)"*) bad "ghost was marked although tmux could not answer" ;; *) ok "ghost unmarked" ;; esac

# ---- refusals ----
hm-spawn --respawn nobody >/dev/null 2>&1; assert_status "respawn of an agent not on the team" $? 2
hm-spawn --respawn impl --model opus >/dev/null 2>&1; assert_status "--respawn takes nothing but --still and --max-wait" $? 64
hm-spawn --respawn orchestrator >/dev/null 2>"$T_TMP/o.err"; assert_status "the orchestrator is never respawned" $? 4
assert_contains "...it is told to register again" "$(cat "$T_TMP/o.err")" "hm-spawn --self"
hm-spawn --respawn ghost >/dev/null 2>&1; assert_status "an agent that cannot be told about is not respawned" $? 4
hm-spawn --respawn old >/dev/null 2>&1; assert_status "an agent with no recorded identity is not respawned" $? 4

# ---- respawn: from its own record, into its worktree, back to its handoff ----
printf '# impl handoff\n\n## START HERE\n\nmid-task: keep going\n' > "$S/handoffs/impl.md"
np=$(hm-spawn --respawn impl --still 2 --max-wait 15 2>"$T_TMP/respawn.err"); assert_status "respawn of a stopped agent" $? 0
[ -n "$np" ] && [ "$np" != "$pane" ] && ok "it has a new pane" || bad "no new pane: '$np'"
[ ! -s "$T_TMP/respawn.err" ] && ok "nothing on stderr" || bad "stderr: $(cat "$T_TMP/respawn.err")"
assert_eq "team.json names the new pane" "$(jq -r '.agents[]|select(.name=="impl").pane' "$S/team.json")" "$np"
assert_eq "...one entry for it" "$(jq '[.agents[]|select(.name=="impl")] | length' "$S/team.json")" "1"
assert_eq "...its recorded settings" "$(jq -r '.agents[]|select(.name=="impl") | [.model,.effort,.mode,.window,.worktree,.branch] | map(tostring) | join("|")' "$S/team.json")" "sonnet|medium|auto|123456|$T_TMP/proj-impl|feat/x"
assert_eq "the handoff is kept" "$(tail -1 "$S/handoffs/impl.md")" "mid-task: keep going"
assert_eq "its role is kept" "$(cat "$S/team/impl/role.md")" "role"
assert_eq "it starts in its worktree" "$(hm_tmux display-message -p -t "$np" '#{pane_current_path}')" "$(cd "$T_TMP/proj-impl" && pwd -P)"
screen=$(hm_tmux capture-pane -p -J -S - -t "$np")
assert_contains "with its recorded model" "$screen" "ARGV: sonnet"
assert_contains "and is sent its pickup line" "$screen" "GOT: You are proj-impl. Read $r/$T_STATE/handoffs/impl.md"
hm_team_agent_is "$r" impl; assert_status "it runs as recorded again" $? 0
case "$(hm-context impl)" in *"not running"*) bad "still marked after the respawn" ;; *) ok "no longer marked" ;; esac
hm-spawn --respawn impl --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "a running agent is not respawned" $? 4
np2=$(hm-spawn --respawn rev --still 2 --max-wait 15 2>/dev/null); assert_status "an agent without a worktree is respawned" $? 0
assert_eq "...in the project" "$(hm_tmux display-message -p -t "$np2" '#{pane_current_path}')" "$(cd "$r" && pwd -P)"
assert_eq "the worktree is still the one hivehouse made" "$(hm-manifest list --kind worktree | jq -r .path)" "$T_TMP/proj-impl"
cd /; t_teardown; t_done
