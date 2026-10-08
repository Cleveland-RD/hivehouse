#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; mkdir -p $T_STATE/team/impl $T_STATE/team/rev
jq -nc --arg t "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > $T_STATE/team/impl/session.json
echo '{"agents":[{"name":"impl","model":"sonnet"},{"name":"rev","model":"opus","window":1000000}]}' > $T_STATE/team.json
# the last real assistant line with usage is the one that counts: after it come a sidechain's line, a synthetic line with
# usage and a real line with none, all skipped
assert_eq "latest usage over the default window, marked as a guess" "$(hh-context impl)" "10 (window assumed 1000000)"
assert_eq "explicit window" "$(hh-context impl --window 1000000)" "10"
echo '{"agents":[{"name":"impl","model":"claude-sonnet-5-5[1m]"}]}' > $T_STATE/team.json
assert_eq "a [1m] in the model name does not set the window (A9)" "$(hh-context impl)" "10 (window assumed 1000000)"
echo '{"agents":[{"name":"impl","model":"sonnet","window":1000000}]}' > $T_STATE/team.json
assert_eq "the window comes from team.json, still a guess" "$(hh-context impl)" "10 (window assumed 1000000)"
# Claude Code's own window (hh-statusline's context.json) counts when it was read in the agent's current session
echo '{"agents":[{"name":"impl","model":"sonnet"}]}' > $T_STATE/team.json
echo '{"window":1000000,"used_percentage":9,"session_id":"s","at":"t"}' > $T_STATE/team/impl/context.json
assert_eq "the measured window, unmarked" "$(hh-context impl)" "10"
assert_eq "...and it beats --window" "$(hh-context impl --window 200000)" "10"
echo '{"window":1000000,"used_percentage":9,"session_id":"an-older-session","at":"t"}' > $T_STATE/team/impl/context.json
assert_eq "a reading from another session is stale: the default, marked" "$(hh-context impl)" "10 (window assumed 1000000)"
echo '{"window":0,"session_id":"s"}' > $T_STATE/team/impl/context.json
assert_eq "a zero window read is no window" "$(hh-context impl)" "10 (window assumed 1000000)"
echo 'not json' > $T_STATE/team/impl/context.json
assert_eq "an unreadable context.json is no window" "$(hh-context impl)" "10 (window assumed 1000000)"
rm $T_STATE/team/impl/context.json
# a reading over the window that is only assumed is not a percent: Claude Code's window may be larger (a 1M session read 158-188)
jq -nc '{type:"assistant", isSidechain:false, message:{model:"claude-sonnet-5-5", usage:{input_tokens:1500000, cache_read_input_tokens:0, cache_creation_input_tokens:0, output_tokens:0}}}' > "$T_TMP/big.jsonl"
jq -nc --arg t "$T_TMP/big.jsonl" '{session_id:"s",transcript_path:$t}' > $T_STATE/team/impl/session.json
echo '{"agents":[{"name":"impl","model":"sonnet"}]}' > $T_STATE/team.json
assert_eq "tokens over the assumed window print as tokens, never a percent" "$(hh-context impl)" "1500000 tokens (window unknown)"
assert_eq "...in --all too" "$(hh-context --all | head -1)" "impl 1500000 tokens (window unknown)"
echo '{"agents":[{"name":"impl","model":"sonnet","window":200000}]}' > $T_STATE/team.json
assert_eq "...also against a window team.json recorded (a default, not a measure)" "$(hh-context impl)" "1500000 tokens (window unknown)"
echo '{"agents":[{"name":"impl","model":"sonnet","window":2000000}]}' > $T_STATE/team.json
assert_eq "a recorded window that holds the tokens: a percent, still marked a guess" "$(hh-context impl)" "75 (window assumed 2000000)"
assert_eq "an explicit --window is the caller's own word" "$(hh-context impl --window 5000000)" "30"
echo '{"window":5000000,"used_percentage":30,"session_id":"s","at":"t"}' > $T_STATE/team/impl/context.json
echo '{"agents":[{"name":"impl","model":"sonnet"}]}' > $T_STATE/team.json
assert_eq "a measured window holds them too" "$(hh-context impl)" "30"
rm $T_STATE/team/impl/context.json
jq -nc --arg t "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > $T_STATE/team/impl/session.json
echo '{"agents":[{"name":"impl","model":"sonnet"},{"name":"rev","model":"opus","window":1000000}]}' > $T_STATE/team.json
hh-context nobody 2>/dev/null; assert_status "unknown agent" $? 2
hh-context rev 2>/dev/null; assert_status "an agent with no session record" $? 2
hh-context impl --window abc 2>/dev/null; assert_status "a bad window is refused" $? 4
hh-context impl --window 0 2>/dev/null; assert_status "a zero window is refused" $? 4
hh-context 2>/dev/null; assert_status "usage" $? 64
cp "$r/$T_STATE/team/impl/session.json" "$T_TMP/s.json"
echo '{"agents":[{"name":"impl","model":"sonnet"},{"name":"rev","model":"opus"}]}' > $T_STATE/team.json
assert_eq "--all lists every team member, ? when unknown" "$(hh-context --all | tr '\n' ' ')" "impl 10 (window assumed 1000000) rev ? "
printf '%s\n' '{"type":"assistant","isSidechain":false,"message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}' > "$T_TMP/only-synthetic.jsonl"
jq -nc --arg t "$T_TMP/only-synthetic.jsonl" '{session_id:"s",transcript_path:$t}' > $T_STATE/team/rev/session.json
hh-context rev 2>/dev/null; assert_status "a transcript with no real usage line is unknown" $? 2
# where the window came from, for the Stop hook: measured by Claude Code, recorded (spawn, --self, hh-hub window), or the default guess
jq -nc --arg t "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > $T_STATE/team/impl/session.json
echo '{"agents":[{"name":"impl","model":"sonnet"}]}' > $T_STATE/team.json
assert_eq "--source: no window anywhere is a guess" "$(hh-context impl --source)" "guess"
echo '{"agents":[{"name":"impl","model":"sonnet","window":1000000}]}' > $T_STATE/team.json
assert_eq "--source: a recorded window is given" "$(hh-context impl --source)" "given"
echo '{"window":1000000,"used_percentage":9,"session_id":"s","at":"t"}' > $T_STATE/team/impl/context.json
assert_eq "--source: Claude Code's reading is measured" "$(hh-context impl --source)" "measured"
echo '{"window":1000000,"used_percentage":9,"session_id":"older","at":"t"}' > $T_STATE/team/impl/context.json
assert_eq "--source: another session's reading is not (given again)" "$(hh-context impl --source)" "given"
rm $T_STATE/team/impl/context.json
hh-context nobody --source 2>/dev/null; assert_status "--source of an unknown agent" $? 2
assert_eq "the reading itself is unchanged by all this" "$(hh-context impl)" "10 (window assumed 1000000)"
# a tracked .hivehouse is refused; outside a repo nothing is written
echo x > $T_STATE/leak; git add -f $T_STATE/leak
hh-context impl >/dev/null 2>&1; assert_status "tracked $T_STATE refused" $? 3
git rm -qf --cached $T_STATE/leak
mkdir "$T_TMP/norepo"; cd "$T_TMP/norepo"
hh-context impl >/dev/null 2>&1; assert_status "outside a repo" $? 2
[ ! -e "$T_TMP/norepo/$T_STATE" ] && ok "nothing written outside a repo" || bad "wrote $T_STATE outside a repo"
# what the start skill says hh-context prints when the window is not recorded: the assumed window, until the tokens pass it
SK="$HH_REPO_ROOT/skills/start/SKILL.md"
tr '\n' ' ' < "$SK" | tr -s ' ' | grep -q "window assumed $T_WINDOW" && ok "the start skill says the reading is (window assumed $T_WINDOW)" || bad "the start skill does not name (window assumed $T_WINDOW)"
tr '\n' ' ' < "$SK" | tr -s ' ' | grep -q 'then says "window unknown" for a reading it cannot place' && bad "the start skill still says hh-context says window unknown for a reading it cannot place" || ok "...and no longer says unknown for every reading"
cd /; t_teardown; t_done
