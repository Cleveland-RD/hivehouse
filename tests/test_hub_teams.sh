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
# status reads each team root's levels once per project (the home and the worktree: two), not once for the orchestrator and again for the agents
CB="$T_TMP/ctxbin"; rm -rf "$CB"; mkdir -p "$CB"; cp -R "$HM_REPO_ROOT/bin/." "$CB/"; mv "$CB/hm-context" "$CB/hm-context.real"
printf '#!/bin/bash\necho "$HM_PROJECT" >> "%s/ctx.calls"\nexec "%s/hm-context.real" "$@"\n' "$T_TMP" "$CB" > "$CB/hm-context"; chmod +x "$CB/hm-context"
: > "$T_TMP/ctx.calls"; (cd "$H" && "$CB/hm-hub" status app --json >/dev/null)
assert_eq "hm-context ran once for each team root in one status call" "$(sort "$T_TMP/ctx.calls" | uniq -c | awk '{print $1}' | tr '\n' ' ')" "1 1 "
assert_eq "...for the home and the worktree" "$(wc -l < "$T_TMP/ctx.calls" | tr -d ' ')" "2"
# an orchestrator whose tokens exceed the window that is only assumed shows as unknown, never as a percent over 100
jq -nc '{type:"assistant", isSidechain:false, message:{model:"claude-sonnet-5-5", usage:{input_tokens:300000, cache_read_input_tokens:0, cache_creation_input_tokens:0, output_tokens:0}}}' > "$T_TMP/big.jsonl"
jq -nc --arg t "$T_TMP/big.jsonl" '{session_id:"sess-big", transcript_path:$t}' > "$WT/.hivemind/team/orchestrator/session.json"
assert_eq "the status carries no context number when the window is unknown" "$(proj '.projects[0].orchestrator | has("context")')" "false"
assert_eq "...it says the window is unknown, with the tokens" "$(proj '.projects[0].orchestrator | [.context_unknown, .context_tokens] | map(tostring) | join(" ")')" "true 300000"
assert_eq "...and no context in the whole status is over 100" "$(hub status app --json | jq '[.. | .context? | numbers | select(. > 100)] | length')" "0"
rm "$WT/.hivemind/team/orchestrator/session.json"
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

# ---- an orchestrator that ended unregistered is resumed from Claude Code's transcript ----
# Nothing is recorded (no team.json entry, no session.json): the transcript under the folder key of a team root, whose last custom-title is
# <project>-orchestrator and whose records all carry that root as cwd, is the conversation. Its key is the path with / . _ & and space as '-'.
mk res; hub add res --home res >/dev/null
RT="$H/res-wt"; git -C "$H/res" worktree add -q "$RT" -b rteam; RT=$(cd "$RT" && pwd -P); mkdir -p "$RT/.hivemind"; echo '{"agents":[]}' > "$RT/.hivemind/team.json"
key() { printf '%s' "$1" | tr '/._& ' '-----'; }
# tr_file <root> <session id> <title> <cwd in records> <touch -t stamp>: a transcript under <root>'s key folder
tr_file() {
  local d="$CLAUDE_CONFIG_DIR/projects/$(key "$1")"; mkdir -p "$d"
  { jq -nc --arg t "$3" --arg s "$2" '{type:"custom-title", customTitle:"old", sessionId:$s}'
    jq -nc --arg c "$4" --arg s "$2" '{type:"attachment", cwd:$c, sessionId:$s}'
    jq -nc --arg t "$3" --arg s "$2" '{type:"custom-title", customTitle:$t, sessionId:$s}'; } > "$d/$2.jsonl"
  touch -t "$5" "$d/$2.jsonl"
}
rs() { hub status res --json | jq -r "$1"; }
HOME_RES="$H/res"
assert_eq "no transcript: none" "$(rs '.projects[0].orchestrator.state')" "none"
hub wake res >/dev/null 2>"$T_TMP/w.err"; assert_status "...and wake has nothing to resume" $? 2
tr_file "$HOME_RES" aaaa1111-0000-0000-0000-000000000001 res-orchestrator "$HOME_RES" 202601010101
assert_eq "a transcript titled <project>-orchestrator in the home's key folder is resumable" "$(rs '.projects[0].orchestrator.state')" "resumable"
assert_eq "...with its session id" "$(rs '.projects[0].orchestrator.session_id')" "aaaa1111-0000-0000-0000-000000000001"
assert_contains "...the plain status says so" "$(hub status res)" "stopped, not registered (resumable)"
tr_file "$HOME_RES" bbbb2222-0000-0000-0000-000000000002 res-orchestrator "$HOME_RES" 202602020202
assert_eq "the newest transcript wins" "$(rs '.projects[0].orchestrator.session_id')" "bbbb2222-0000-0000-0000-000000000002"
tr_file "$HOME_RES" cccc3333-0000-0000-0000-000000000003 res-builder "$HOME_RES" 202603030303
assert_eq "a newer transcript with another last title is not taken" "$(rs '.projects[0].orchestrator.session_id')" "bbbb2222-0000-0000-0000-000000000002"
tr_file "$HOME_RES" dddd4444-0000-0000-0000-000000000004 res-orchestrator "$H/elsewhere" 202604040404
assert_eq "...nor one whose records carry another cwd" "$(rs '.projects[0].orchestrator.session_id')" "bbbb2222-0000-0000-0000-000000000002"
# two folders that share a key: a/b, a_b and a-b
mkdir -p "$H/x/y" "$H/x_y" "$H/x-y"; assert_eq "(the key does not tell x/y, x_y and x-y apart)" "$(key "$H/x/y")" "$(key "$H/x_y")"
tr_file "$RT" eeee5555-0000-0000-0000-000000000005 res-orchestrator "$RT" 202605050505
assert_eq "a team root that is a worktree has its own key folder, and the newer transcript there wins" "$(rs '.projects[0].orchestrator.session_id')" "eeee5555-0000-0000-0000-000000000005"
touch -t 202501010101 "$CLAUDE_CONFIG_DIR/projects/$(key "$RT")/eeee5555-0000-0000-0000-000000000005.jsonl"
assert_eq "...and an older one there loses to the home's (the newest across roots, whichever root is read last)" "$(rs '.projects[0].orchestrator.session_id')" "bbbb2222-0000-0000-0000-000000000002"
rm -rf "$CLAUDE_CONFIG_DIR/projects/$(key "$RT")"
for i in $(seq 1 20); do tr_file "$HOME_RES" "ffff$(printf %04d $i)-0000-0000-0000-000000000000" res-builder "$HOME_RES" 20271010$(printf %02d $i)00; done
assert_eq "only the newest 20 transcripts of a root are read: a match older than those is not found" "$(rs '.projects[0].orchestrator.state')" "none"
rm -f "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")"/ffff*.jsonl
mv "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")" "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")-short"
assert_eq "a root whose key folder is not found: no guess" "$(rs '.projects[0].orchestrator.state')" "none"
mv "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")-short" "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")"
rm -f "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")/dddd4444-0000-0000-0000-000000000004.jsonl" "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")/cccc3333-0000-0000-0000-000000000003.jsonl"
# status polls: a project's transcripts are read again only when the newest 20 of a root have changed (name, time or size)
CJ="$T_TMP/countjq"; mkdir -p "$CJ"
printf '#!/bin/sh\ncase "$*" in *customTitle*|*".cwd // empty"*) echo x >> "%s/jq.calls" ;; esac\nexec /usr/bin/jq "$@"\n' "$T_TMP" > "$CJ/jq"; chmod +x "$CJ/jq"
reads() { : > "$T_TMP/jq.calls"; (cd "$H" && PATH="$CJ:$PATH" hm-hub status res --json >/dev/null); wc -l < "$T_TMP/jq.calls" | tr -d ' '; }
assert_eq "the first status reads the transcripts" "$([ "$(reads)" -gt 0 ] && echo yes || echo no)" "yes"
assert_eq "the second reads none: nothing changed" "$(reads)" "0"
assert_eq "...and still says resumable, from what it kept" "$(rs '.projects[0].orchestrator.session_id')" "bbbb2222-0000-0000-0000-000000000002"
{ jq -nc '{type:"custom-title", customTitle:"res-builder", sessionId:"bbbb2222-0000-0000-0000-000000000002"}'; } >> "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")/bbbb2222-0000-0000-0000-000000000002.jsonl"
assert_eq "a transcript that grew is read again" "$([ "$(reads)" -gt 0 ] && echo yes || echo no)" "yes"
assert_eq "...and its new last title counts: it is no orchestrator's now, so the next older match is taken" "$(rs '.projects[0].orchestrator.session_id')" "aaaa1111-0000-0000-0000-000000000001"
{ jq -nc '{type:"custom-title", customTitle:"res-orchestrator", sessionId:"bbbb2222-0000-0000-0000-000000000002"}'; } >> "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME_RES")/bbbb2222-0000-0000-0000-000000000002.jsonl"
assert_eq "...and a later rename back counts again" "$(rs '.projects[0].orchestrator.session_id')" "bbbb2222-0000-0000-0000-000000000002"
# a kept answer is checked like a fresh one: a bad id or a non-numeric time is a miss, read again; and a miss prints nothing on stderr
RCK=$(grep -l 'bbbb2222-0000-0000-0000-000000000002' "$HIVEMIND_HOME"/cache/resume-* | head -1)
assert_status "(the kept answer is on disk)" $([ -n "$RCK" ] && echo 0 || echo 1) 0
RFP=$(cut -f1 "$RCK")
printf '%s\t%s\t%s\n' "$RFP" 'not an id; $(x)' 123 > "$RCK"
assert_eq "a kept line with a bad id is not printed: the transcripts are read again" "$(rs '.projects[0].orchestrator.session_id')" "bbbb2222-0000-0000-0000-000000000002"
printf '%s\t%s\t%s\n' "$RFP" bbbb2222-0000-0000-0000-000000000002 'not a time' > "$RCK"
assert_eq "a kept line with a non-numeric time is not printed either" "$(rs '.projects[0].orchestrator.session_id')" "bbbb2222-0000-0000-0000-000000000002"
assert_eq "...and the kept line is whole again" "$(cut -f3 "$RCK" | grep -Ec '^[0-9]+$')" "1"
rm -f "$RCK"; (cd "$H" && hm-hub status res --json 2>"$T_TMP/miss.err" >/dev/null)
assert_eq "a cache miss leaves stderr empty" "$(wc -c < "$T_TMP/miss.err" | tr -d ' ')" "0"
# wake
wp=$(umask 077; hub wake res --mode auto --still 2 --max-wait 15 2>"$T_TMP/w.err"); assert_status "wake resumes it" $? 0
screen=$(hm_tmux capture-pane -p -J -S - -t "$wp")
assert_contains "...the session has the caller's umask (077), not the hub's 022" "$screen" "UMASK: 0077"
assert_contains "...by session id" "$screen" "ARGV: bbbb2222-0000-0000-0000-000000000002"
assert_contains "...named <project>-orchestrator" "$screen" "ARGV: res-orchestrator"
assert_contains "...the wake line carries --agent orchestrator" "$screen" "hm-spawn --self --agent orchestrator"
assert_eq "...in the root whose transcript it was" "$(hm_tmux display-message -p -t "$wp" '#{pane_current_path}')" "$HOME_RES"
hub wake res --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "a second wake while the first is coming up is refused" $? 4
hm_tmux kill-pane -t "$wp"; rm -f "$P/panes/res.json"
hp2=$(jq -nc --argjson p 1 '$p' >/dev/null; live res-orchestrator "$H/elsewhere")
jq -nc --argjson p "$hp2" --arg s "bbbb2222-0000-0000-0000-000000000002" --arg c "$H/elsewhere" '{pid:$p, name:"zzz", cwd:$c, sessionId:$s, kind:"interactive"}' > "$CLAUDE_CONFIG_DIR/sessions/$hp2.json"
hub wake res --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/w.err"; assert_status "a live Claude already holding that conversation refuses the wake" $? 4
assert_contains "...and says so" "$(cat "$T_TMP/w.err")" "already open in a live session"
kill "$hp2" 2>/dev/null

# ---- two different orchestrators: a stale one in the home, a live one in a worktree. The live one is the orchestrator ----
mk two; hub add two --home two >/dev/null
T2="$H/two-wt"; git -C "$H/two" worktree add -q "$T2" -b two-team; T2=$(cd "$T2" && pwd -P); mkdir -p "$T2/.hivemind/team/orchestrator" "$H/two/.hivemind/team/orchestrator"
T3="$H/two-wt3"; git -C "$H/two" worktree add -q "$T3" -b two-team3; T3=$(cd "$T3" && pwd -P); mkdir -p "$T3/.hivemind"
DEAD=$( ( exec -a claude sleep 0.1 ) >/dev/null 2>&1 & echo $! ); sleep 0.4
jq -nc --arg k "$HM_TMUX_SOCKET" --arg kp "$kp" --arg p "${ki%%$'\t'*}" --arg c "$DEAD" \
  '{agents:[{name:"orchestrator", pane:$kp, socket:$k, pane_pid:$p, pane_started:"Mon Jan  1 00:00:00 2001", claude_pid:$c, claude_started:"Mon Jan  1 00:00:00 2001", name_full:"two-orchestrator"}]}' > "$H/two/.hivemind/team.json"
jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"sess-home-old", transcript_path:$t}' > "$H/two/.hivemind/team/orchestrator/session.json"
TP=$(live two-orchestrator "$T2")
rm -f "$CLAUDE_CONFIG_DIR/sessions/$TP.json"   # Claude Code records nothing of it: only team.json says it runs
jq -nc --arg k "$HM_TMUX_SOCKET" --arg kp "$kp" --arg p "${ki%%$'\t'*}" --arg s "${ki#*$'\t'}" --arg c "$TP" --arg cs "$(hm_lstart "$TP")" \
  '{agents:[{name:"orchestrator", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s, claude_pid:$c, claude_started:$cs, name_full:"two-orchestrator"},
            {name:"impl", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s}]}' > "$T2/.hivemind/team.json"
jq -nc --arg k "$HM_TMUX_SOCKET" --arg kp "$kp" --arg p "${ki%%$'\t'*}" --arg s "${ki#*$'\t'}" \
  '{agents:[{name:"orchestrator", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s}]}' > "$T3/.hivemind/team.json"
ts() { hub status two --json | jq -r "$1"; }
assert_eq "a live orchestrator in a worktree wins over a stale one in the home: running" "$(ts '.projects[0].orchestrator.state')" "running"
assert_eq "...the agents are the impl alone, plus the spawned agent that only shares the orchestrator's name in a third root" "$(ts '.projects[0].agents | map([.name, (.worktree | sub(".*/"; ""))] | join("@")) | join(",")')" "impl@two-wt,orchestrator@two-wt3"
hub wake two --mode auto --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/w2.err"; assert_status "wake refuses: the live orchestrator is running" $? 4
assert_contains "...saying so" "$(cat "$T_TMP/w2.err")" "running"
assert_eq "...and no pane was started for it" "$(ls "$P/panes" 2>/dev/null | grep -c '^two\.json$')" "0"
kill "$TP" 2>/dev/null

# ---- an agent name used in two team roots of one project: told apart by the root ----
mk dup; hub add dup --home dup >/dev/null
DW="$H/dup-wt"; git -C "$H/dup" worktree add -q "$DW" -b dup-team; DW=$(cd "$DW" && pwd -P); mkdir -p "$DW/.hivemind" "$H/dup/.hivemind"
pb=$(hm_tmux new-window -d -P -F '#{pane_id}' -t keep: -n twin 'sleep 600'); pbi=$(hm_pane_identity "$HM_TMUX_SOCKET" "$pb")
for pair in "$H/dup:$kp:${ki%%$'\t'*}:${ki#*$'\t'}" "$DW:$pb:${pbi%%$'\t'*}:${pbi#*$'\t'}"; do
  IFS=: read -r droot dpane dpp dps <<< "$pair"
  jq -nc --arg k "$HM_TMUX_SOCKET" --arg p "$dpane" --arg pp "$dpp" --arg ps "$dps" '{agents:[{name:"impl", pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps}]}' > "$droot/.hivemind/team.json"
done
ds() { hub status dup --json | jq -r "$1"; }
assert_eq "the name is listed once per root, each with its root" "$(ds '.projects[0].agents | map(.worktree) | sort | join(",")')" "$(printf '%s\n%s' "$H/dup" "$DW" | sort | tr '\n' ',' | sed 's/,$//')"
assert_eq "...and a ref that tells them apart" "$(ds '.projects[0].agents | map(.ref) | sort | join(",")')" "$(printf '%s\n%s' "impl@$H/dup" "impl@$DW" | sort | tr '\n' ',' | sed 's/,$//')"
assert_eq "a name used once keeps its bare name as the ref" "$(hub status app --json | jq -r '.projects[0].agents[0].ref')" "$(hub status app --json | jq -r '.projects[0].agents[0].name')"
hub dialog dup impl >/dev/null 2>"$T_TMP/amb.err"; assert_status "a dialog for the ambiguous name is refused" $? 4
assert_contains "...naming each root" "$(cat "$T_TMP/amb.err")" "impl@$DW"
assert_contains "...both of them" "$(cat "$T_TMP/amb.err")" "impl@$H/dup"
hub dialog dup "impl@$DW" >/dev/null 2>"$T_TMP/d1.err"
assert_contains "a dialog for name@root reads that root's pane" "$(cat "$T_TMP/d1.err")" "pane $pb"
hub dialog dup "impl@$H/dup" >/dev/null 2>"$T_TMP/d2.err"
assert_contains "...and the other root's pane for the other" "$(cat "$T_TMP/d2.err")" "pane $kp"
hub dialog dup "impl@$H/nowhere" >/dev/null 2>"$T_TMP/d3.err"; assert_status "a root the name is not in is not found" $? 2
hm_tmux kill-pane -t "$pb" 2>/dev/null; sleep 0.5
assert_contains "the plain status names the root of a stopped one of two same-named agents" "$(hub status dup)" "impl@$DW stopped"

# ---- hm-hub run reaches an orchestrator registered only in a worktree: its pane is read from that root's team.json ----
mk wr; hub add wr --home wr >/dev/null
WR="$H/wr-wt"; git -C "$H/wr" worktree add -q "$WR" -b wr-team; WR=$(cd "$WR" && pwd -P); mkdir -p "$WR/.hivemind/team/orchestrator"
SB="$T_TMP/b.sock"
WRPANE=$(env -u HIVEMIND_HOME tmux -S "$SB" new-session -d -x 200 -y 56 -P -F '#{pane_id}' -s wrb -c "$WR" -e "HM_FAKE_CLAUDE=idle" 'exec claude --name wr-orchestrator') || WRPANE=""
t_track "$(tmux -S "$SB" display -p '#{pid}')"
( exec -a claude sleep 300 ) >/dev/null 2>&1 & WRC=$!; disown "$WRC"; t_track "$WRC"; sleep 0.3
wi=$(hm_pane_identity "$SB" "$WRPANE")
jq -nc --arg k "$SB" --arg p "$WRPANE" --arg pp "${wi%%$'\t'*}" --arg ps "${wi#*$'\t'}" --arg c "$WRC" --arg cs "$(hm_lstart "$WRC")" \
  '{agents:[{name:"orchestrator", pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps, claude_pid:$c, claude_started:$cs, name_full:"wr-orchestrator"}]}' > "$WR/.hivemind/team.json"
jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"sess-wr", transcript_path:$t}' > "$WR/.hivemind/team/orchestrator/session.json"
wt1=$(hub task wr --text "Work the queue"); wt1=${wt1%%$'\t'*}
rp=$(hub run wr overnight "$wt1" --still 2 --max-wait 15 2>"$T_TMP/r.err"); assert_status "run overnight for an orchestrator registered in a worktree" $? 0
assert_eq "...typed into its pane, on its own server" "$rp" "$WRPANE"
assert_contains "...the fixed line" "$(tmux -S "$SB" capture-pane -p -J -S - -t "$WRPANE")" "GOT: /hivemind:overnight Task $wt1"
t_done
