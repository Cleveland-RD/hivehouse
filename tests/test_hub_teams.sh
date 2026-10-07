#!/usr/bin/env bash
# The hub sees every orchestrator and team of a project: the team roots (its home, then each worktree of its repository that has a
# team.json), not only the home. A session named after the project counts as its orchestrator when it runs in the home.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
env -u HIVEMIND_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/.hivemind-hub"
hub() { (cd "$H" && hm-hub "$@"); }
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
live() {  # live <name> <cwd>: a running process named claude, with Claude Code's record of it; prints its pid
  ( exec -a claude sleep 60 ) >/dev/null 2>&1 & local p=$!; disown "$p"; t_track "$p"; sleep 0.2
  mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
  jq -nc --argjson p "$p" --arg n "$1" --arg c "$2" '{pid:$p, name:$n, cwd:$c, tmux:"work:@3.%77", kind:"interactive"}' > "$CLAUDE_CONFIG_DIR/sessions/$p.json"
  echo "$p"
}
proj() { hub status app --json | jq -r "$1"; }
mk app; mk other
hub init >/dev/null; hub add app --home app >/dev/null; hub add other --home other >/dev/null
mkdir -p "$T_TMP/cl"; printf '#!/usr/bin/env bash\ncd "%s" && hm-hub self "$@"\n' "$H" > "$T_TMP/cl/claude"; bash "$T_TMP/cl/claude" --name hub >/dev/null
WT="$H/app-wt"; git -C "$H/app" worktree add -q "$WT" -b team; WT=$(cd "$WT" && pwd -P)
mkdir -p "$WT/.hivemind/team/orchestrator"
kp=$(hm_tmux list-panes -t keep -F '#{pane_id}' | head -1); ki=$(hm_pane_identity "$HM_TMUX_SOCKET" "$kp")

# ---- a team registered in a worktree of the home is seen ----
assert_eq "no team anywhere: none" "$(proj '.projects[0].orchestrator.state')" "none"
CP=$(live app-orchestrator "$WT")
jq -nc --arg k "$HM_TMUX_SOCKET" --arg kp "$kp" --arg p "${ki%%$'\t'*}" --arg s "${ki#*$'\t'}" --arg c "$CP" --arg cs "$(hm_lstart "$CP")" \
  '{agents:[{name:"orchestrator", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s, claude_pid:$c, claude_started:$cs, name_full:"app-orchestrator"},
            {name:"impl", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s}]}' > "$WT/.hivemind/team.json"
assert_eq "an orchestrator registered in a worktree of the home runs" "$(proj '.projects[0].orchestrator.state')" "running"
assert_eq "...its agents are listed, each with its worktree" "$(proj '.projects[0].agents | map([.name, .worktree] | join("@")) | join(",")')" "impl@$WT"
assert_contains "...the plain status names it" "$(hub status app)" "running"
mkdir -p "$H/app/.hivemind"
jq -c '{agents: [.agents[] | select(.name == "orchestrator")]}' "$WT/.hivemind/team.json" > "$H/app/.hivemind/team.json"
assert_eq "registered in both roots (same process): it counts once, as running" "$(proj '.projects[0].orchestrator.state')" "running"
assert_eq "...and is not listed among the agents" "$(proj '.projects[0].agents | map(.name) | sort | join(",")')" "impl"
rm "$H/app/.hivemind/team.json"
assert_eq "a team in a worktree of another project's home is not this project's" "$(hub status other --json | jq -r '.projects[0].orchestrator.state')" "none"
hub dialog app impl >/dev/null 2>"$T_TMP/d.err"; rc=$?
case "$(cat "$T_TMP/d.err")" in *"no agent named"*) bad "an agent in a worktree's team is not found by dialog" ;; *) ok "an agent in a worktree's team is found by hm-hub dialog (exit $rc)" ;; esac
hub dialog app nobody >/dev/null 2>"$T_TMP/d.err"; assert_status "...and one on no team is not" $? 2
kill "$CP" 2>/dev/null; sleep 0.3
assert_eq "its Claude gone: stopped" "$(proj '.projects[0].orchestrator.state')" "stopped"

# ---- wake resumes from the root the orchestrator was found in ----
jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"sess-wt", transcript_path:$t}' > "$WT/.hivemind/team/orchestrator/session.json"
wp=$(hub wake app --mode auto --still 2 --max-wait 15 2>"$T_TMP/wake.err"); assert_status "wake of a worktree orchestrator" $? 0
screen=$(hm_tmux capture-pane -p -J -S - -t "$wp")
assert_contains "...resumes the session recorded in the worktree" "$screen" "ARGV: sess-wt"
assert_eq "...in the worktree it was found in" "$(hm_tmux display-message -p -t "$wp" '#{pane_current_path}')" "$WT"
hm_tmux kill-pane -t "$wp"; rm -f "$P/panes/app.json"

# ---- a session named after the project, in the home, is its orchestrator ----
rm -rf "$WT/.hivemind/team.json"
assert_eq "no team.json and no session: none" "$(proj '.projects[0].orchestrator.state')" "none"
lp=$(live app "$H/app")
assert_eq "a live session named just <project>, running in the home, counts" "$(proj '.projects[0].orchestrator.state')" "unregistered"
kill "$lp" 2>/dev/null; sleep 0.3
lp=$(live app "$H/other")
assert_eq "...one named <project> in another folder does not" "$(proj '.projects[0].orchestrator.state')" "none"
kill "$lp" 2>/dev/null; sleep 0.3
lp=$(live app-builder "$H/app")
assert_eq "...and a home session with another name does not" "$(proj '.projects[0].orchestrator.state')" "none"
kill "$lp" 2>/dev/null
t_done
