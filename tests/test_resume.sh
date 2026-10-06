#!/usr/bin/env bash
# hm-spawn --respawn <n> --mode <m> (only a stricter mode than the recorded one, A11) and --respawn <n> --resume (the agent's
# recorded session is resumed and it is typed the short restart line, not the pickup line; no recorded session: today's respawn).
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
env -u HIVEMIND_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
S="$r/.hivemind"
spawn() { hm-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode "${2:-auto}" --still 2 --max-wait 15; }
respawn() { hm-spawn --respawn "$@" --still 2 --max-wait 15; }
pane() { jq -r '.agents[]|select(.name=="impl").pane' "$S/team.json"; }
mode() { jq -r '.agents[]|select(.name=="impl").mode' "$S/team.json"; }
stop() { hm_tmux kill-pane -t "$(pane)"; sleep 1; }
screen() { hm_tmux capture-pane -p -J -S - -t "$1"; }
HANDOFF="$S/handoffs/impl.md"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"; : > "$CLAUDE_CONFIG_DIR/projects/p/sess-abc-123.jsonl"
spawn impl auto >/dev/null; assert_status "spawn impl in auto" $? 0
setsession() { jq -nc --arg s "$1" '{session_id:$s}' > "$S/team/impl/session.json"; }

echo "-- --mode: only stricter than the recorded mode"
stop
for m in auto bypassPermissions nonsense; do
  respawn impl --mode "$m" >/dev/null 2>"$T_TMP/e"; assert_status "--mode $m with auto recorded is refused" $? 4
done
assert_contains "the refusal says why" "$(cat "$T_TMP/e")" "stricter"
assert_eq "...nothing was started and the record is unchanged" "$(mode)" "auto"
hm_team_agent_is "$r" impl; assert_status "...the agent is still stopped" $? 1
np=$(respawn impl --mode default); assert_status "--mode default with auto recorded is accepted" $? 0
assert_eq "...recorded as default" "$(mode)" "default"
assert_contains "...and started in it" "$(screen "$np")" "ARGV: default"
stop
respawn impl --mode acceptEdits >/dev/null 2>&1; assert_status "--mode acceptEdits with default recorded (looser) is refused" $? 4
respawn impl --mode default >/dev/null 2>&1; assert_status "the same mode is refused" $? 4
np=$(respawn impl --mode plan); assert_status "--mode plan with default recorded is accepted" $? 0
assert_eq "...recorded as plan" "$(mode)" "plan"
stop
np=$(respawn impl); assert_status "no --mode keeps the recorded one" $? 0
assert_eq "...still plan" "$(mode)" "plan"
assert_contains "...and started in it" "$(screen "$np")" "ARGV: plan"
stop
respawn impl --mode dontAsk >/dev/null 2>&1; assert_status "dontAsk is as strict as plan, so not stricter" $? 4

# a recorded bypass is the loosest: any local mode is stricter, bypass itself is not (the record is edited here: bypass is not started by this test)
setmode() { jq --arg m "$1" '(.agents[]|select(.name=="impl").mode) = $m' "$S/team.json" > "$S/team.json.t" && mv "$S/team.json.t" "$S/team.json"; }
setmode bypassPermissions
respawn impl --mode bypassPermissions >/dev/null 2>&1; assert_status "--mode bypassPermissions with bypass recorded is not stricter" $? 4
np=$(respawn impl --mode auto); assert_status "--mode auto with bypass recorded is stricter" $? 0
assert_eq "...recorded as auto" "$(mode)" "auto"
stop
# plan and dontAsk are the same strictness; default is stricter than acceptEdits, which is stricter than auto; an unknown recorded mode cannot be judged
setmode dontAsk; respawn impl --mode plan >/dev/null 2>&1; assert_status "--mode plan with dontAsk recorded (the same strictness) is refused" $? 4
setmode acceptEdits; np=$(respawn impl --mode default); assert_status "--mode default with acceptEdits recorded is accepted" $? 0
stop; setmode auto; np=$(respawn impl --mode acceptEdits); assert_status "--mode acceptEdits with auto recorded is accepted" $? 0
stop; setmode weird; respawn impl --mode auto >/dev/null 2>&1; assert_status "an unknown recorded mode cannot be judged: refused" $? 4
setmode auto
echo "-- --resume"
printf '# impl handoff\n\n## START HERE\n\nmid-task\n' > "$HANDOFF"
setsession sess-abc-123
np=$(respawn impl); assert_status "no --resume: a recorded session is not resumed" $? 0
sc=$(screen "$np"); case "$sc" in *"ARGV: --resume"*) bad "resumed without --resume" ;; *) ok "...started without --resume" ;; esac
assert_contains "...and typed the pickup line" "$sc" "GOT: You are proj-impl. Read $HANDOFF"
stop
np=$(hm-spawn --respawn impl --still 2 --max-wait 15 --resume); assert_status "--resume as the last argument" $? 0
stop
np=$(respawn impl --resume); assert_status "--resume with a recorded session" $? 0
sc=$(screen "$np")
assert_contains "claude is started with --resume" "$sc" "ARGV: --resume"
assert_contains "...and the recorded session id" "$sc" "ARGV: sess-abc-123"
assert_contains "the agent is typed the short restart line" "$sc" "GOT: You were restarted by hivemind after your session stopped responding. Carry on where you were; your handoff is $HANDOFF."
case "$sc" in *"You are proj-impl. Read"*) bad "the pickup line was typed too" ;; *) ok "...not the pickup line" ;; esac
assert_eq "it is registered again as recorded" "$(pane)" "$np"
hm_team_agent_is "$r" impl; assert_status "...and runs as recorded" $? 0

echo "-- --resume falls back to today's respawn"
stop; rm -f "$S/team/impl/session.json"
np=$(respawn impl --resume); assert_status "no session record" $? 0
sc=$(screen "$np")
case "$sc" in *"ARGV: --resume"*) bad "resumed with no session" ;; *) ok "no session record: started without --resume" ;; esac
assert_contains "...and typed the pickup line" "$sc" "GOT: You are proj-impl. Read $HANDOFF"
stop; setsession sess-missing-999
np=$(respawn impl --resume); assert_status "a session whose transcript is gone" $? 0
sc=$(screen "$np"); case "$sc" in *"ARGV: --resume"*) bad "resumed a session with no transcript" ;; *) ok "no transcript: started without --resume" ;; esac
assert_contains "...and typed the pickup line" "$sc" "GOT: You are proj-impl. Read $HANDOFF"
stop; setsession '../../x'
np=$(respawn impl --resume); assert_status "a session id that is not an id" $? 0
sc=$(screen "$np"); case "$sc" in *"ARGV: --resume"*) bad "resumed a path-like id" ;; *) ok "a path-like id: started without --resume" ;; esac
stop; printf 'not json' > "$S/team/impl/session.json"
np=$(respawn impl --resume); assert_status "a session file that is not JSON" $? 0
sc=$(screen "$np"); case "$sc" in *"ARGV: --resume"*) bad "resumed from a broken record" ;; *) ok "a broken record: started without --resume" ;; esac

echo "-- both together, and the usage"
stop; setsession sess-abc-123
jq '(.agents[]|select(.name=="impl").mode) = "auto"' "$S/team.json" > "$S/team.json.t" && mv "$S/team.json.t" "$S/team.json"   # back to auto, so default is stricter
np=$(respawn impl --resume --mode default); assert_status "--resume with a stricter --mode" $? 0
sc=$(screen "$np")
assert_contains "...resumed" "$sc" "ARGV: sess-abc-123"
assert_contains "...in the stricter mode" "$sc" "ARGV: default"
hm-spawn --agent x --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --resume >/dev/null 2>&1; assert_status "--resume without --respawn" $? 64
hm-spawn --self --agent x --resume >/dev/null 2>&1; assert_status "--resume with --self" $? 64
hm-spawn --respawn impl --mode >/dev/null 2>&1; assert_status "--mode with no value" $? 64
hm-spawn --respawn impl --model opus >/dev/null 2>&1; assert_status "--respawn still takes no --model" $? 64
respawn impl --resume >/dev/null 2>&1; assert_status "a running agent is not respawned with --resume either" $? 4
cd /; t_teardown; t_done
