#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; mkdir -p .hivemind/team/impl .hivemind/team/rev
jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"s",transcript_path:$t}' > .hivemind/team/impl/session.json
echo '{"agents":[{"name":"impl","model":"sonnet"},{"name":"rev","model":"opus","window":1000000}]}' > .hivemind/team.json
# the last real assistant line with usage is the one that counts: after it come a sidechain's line, a synthetic line with
# usage and a real line with none, all skipped
assert_eq "latest usage over the default window" "$(hm-context impl)" "50"
assert_eq "explicit window" "$(hm-context impl --window 1000000)" "10"
echo '{"agents":[{"name":"impl","model":"claude-sonnet-5-5[1m]"}]}' > .hivemind/team.json
assert_eq "a [1m] in the model name does not set the window (A9)" "$(hm-context impl)" "50"
echo '{"agents":[{"name":"impl","model":"sonnet","window":1000000}]}' > .hivemind/team.json
assert_eq "the window comes from team.json" "$(hm-context impl)" "10"
hm-context nobody 2>/dev/null; assert_status "unknown agent" $? 2
hm-context rev 2>/dev/null; assert_status "an agent with no session record" $? 2
hm-context impl --window abc 2>/dev/null; assert_status "a bad window is refused" $? 4
hm-context impl --window 0 2>/dev/null; assert_status "a zero window is refused" $? 4
hm-context 2>/dev/null; assert_status "usage" $? 64
cp "$r/.hivemind/team/impl/session.json" "$T_TMP/s.json"
echo '{"agents":[{"name":"impl","model":"sonnet"},{"name":"rev","model":"opus"}]}' > .hivemind/team.json
assert_eq "--all lists every team member, ? when unknown" "$(hm-context --all | tr '\n' ' ')" "impl 50 rev ? "
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
cd /; t_teardown; t_done
