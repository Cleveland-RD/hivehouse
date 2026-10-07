#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; mkdir -p .hivemind/team/impl .hivemind/team/rev
jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > .hivemind/team/impl/session.json
echo '{"agents":[{"name":"impl","model":"sonnet"},{"name":"rev","model":"opus","window":1000000}]}' > .hivemind/team.json
# the last real assistant line with usage is the one that counts: after it come a sidechain's line, a synthetic line with
# usage and a real line with none, all skipped
assert_eq "latest usage over the default window, marked as a guess" "$(hm-context impl)" "50 (window assumed 200000)"
assert_eq "explicit window" "$(hm-context impl --window 1000000)" "10"
echo '{"agents":[{"name":"impl","model":"claude-sonnet-5-5[1m]"}]}' > .hivemind/team.json
assert_eq "a [1m] in the model name does not set the window (A9)" "$(hm-context impl)" "50 (window assumed 200000)"
echo '{"agents":[{"name":"impl","model":"sonnet","window":1000000}]}' > .hivemind/team.json
assert_eq "the window comes from team.json, still a guess" "$(hm-context impl)" "10 (window assumed 1000000)"
# Claude Code's own window (hm-statusline's context.json) counts when it was read in the agent's current session
echo '{"agents":[{"name":"impl","model":"sonnet"}]}' > .hivemind/team.json
echo '{"window":1000000,"used_percentage":9,"session_id":"s","at":"t"}' > .hivemind/team/impl/context.json
assert_eq "the measured window, unmarked" "$(hm-context impl)" "10"
assert_eq "...and it beats --window" "$(hm-context impl --window 200000)" "10"
echo '{"window":1000000,"used_percentage":9,"session_id":"an-older-session","at":"t"}' > .hivemind/team/impl/context.json
assert_eq "a reading from another session is stale: the default, marked" "$(hm-context impl)" "50 (window assumed 200000)"
echo '{"window":0,"session_id":"s"}' > .hivemind/team/impl/context.json
assert_eq "a zero window read is no window" "$(hm-context impl)" "50 (window assumed 200000)"
echo 'not json' > .hivemind/team/impl/context.json
assert_eq "an unreadable context.json is no window" "$(hm-context impl)" "50 (window assumed 200000)"
rm .hivemind/team/impl/context.json
# a reading over the window that is only assumed is not a percent: Claude Code's window may be larger (a 1M session read 158-188)
jq -nc '{type:"assistant", isSidechain:false, message:{model:"claude-sonnet-5-5", usage:{input_tokens:300000, cache_read_input_tokens:0, cache_creation_input_tokens:0, output_tokens:0}}}' > "$T_TMP/big.jsonl"
jq -nc --arg t "$T_TMP/big.jsonl" '{session_id:"s",transcript_path:$t}' > .hivemind/team/impl/session.json
echo '{"agents":[{"name":"impl","model":"sonnet"}]}' > .hivemind/team.json
assert_eq "tokens over the assumed window print as tokens, never a percent" "$(hm-context impl)" "300000 tokens (window unknown)"
assert_eq "...in --all too" "$(hm-context --all | head -1)" "impl 300000 tokens (window unknown)"
echo '{"agents":[{"name":"impl","model":"sonnet","window":200000}]}' > .hivemind/team.json
assert_eq "...also against a window team.json recorded (a default, not a measure)" "$(hm-context impl)" "300000 tokens (window unknown)"
echo '{"agents":[{"name":"impl","model":"sonnet","window":1000000}]}' > .hivemind/team.json
assert_eq "a recorded window that holds the tokens: a percent, still marked a guess" "$(hm-context impl)" "30 (window assumed 1000000)"
assert_eq "an explicit --window is the caller's own word" "$(hm-context impl --window 1000000)" "30"
echo '{"window":1000000,"used_percentage":30,"session_id":"s","at":"t"}' > .hivemind/team/impl/context.json
echo '{"agents":[{"name":"impl","model":"sonnet"}]}' > .hivemind/team.json
assert_eq "a measured window holds them too" "$(hm-context impl)" "30"
rm .hivemind/team/impl/context.json
jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > .hivemind/team/impl/session.json
echo '{"agents":[{"name":"impl","model":"sonnet"},{"name":"rev","model":"opus","window":1000000}]}' > .hivemind/team.json
hm-context nobody 2>/dev/null; assert_status "unknown agent" $? 2
hm-context rev 2>/dev/null; assert_status "an agent with no session record" $? 2
hm-context impl --window abc 2>/dev/null; assert_status "a bad window is refused" $? 4
hm-context impl --window 0 2>/dev/null; assert_status "a zero window is refused" $? 4
hm-context 2>/dev/null; assert_status "usage" $? 64
cp "$r/.hivemind/team/impl/session.json" "$T_TMP/s.json"
echo '{"agents":[{"name":"impl","model":"sonnet"},{"name":"rev","model":"opus"}]}' > .hivemind/team.json
assert_eq "--all lists every team member, ? when unknown" "$(hm-context --all | tr '\n' ' ')" "impl 50 (window assumed 200000) rev ? "
printf '%s\n' '{"type":"assistant","isSidechain":false,"message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}' > "$T_TMP/only-synthetic.jsonl"
jq -nc --arg t "$T_TMP/only-synthetic.jsonl" '{session_id:"s",transcript_path:$t}' > .hivemind/team/rev/session.json
hm-context rev 2>/dev/null; assert_status "a transcript with no real usage line is unknown" $? 2
# a tracked .hivemind is refused; outside a repo nothing is written
echo x > .hivemind/leak; git add -f .hivemind/leak
hm-context impl >/dev/null 2>&1; assert_status "tracked .hivemind refused" $? 3
git rm -qf --cached .hivemind/leak
mkdir "$T_TMP/norepo"; cd "$T_TMP/norepo"
hm-context impl >/dev/null 2>&1; assert_status "outside a repo" $? 2
[ ! -e "$T_TMP/norepo/.hivemind" ] && ok "nothing written outside a repo" || bad "wrote .hivemind outside a repo"
# what the start skill says hm-context prints when the window is not recorded: the assumed window, until the tokens pass it
SK="$HM_REPO_ROOT/skills/start/SKILL.md"
tr '\n' ' ' < "$SK" | tr -s ' ' | grep -q 'window assumed 200000' && ok "the start skill says the reading is (window assumed 200000)" || bad "the start skill does not name (window assumed 200000)"
tr '\n' ' ' < "$SK" | tr -s ' ' | grep -q 'then says "window unknown" for a reading it cannot place' && bad "the start skill still says hm-context says window unknown for a reading it cannot place" || ok "...and no longer says unknown for every reading"
cd /; t_teardown; t_done
