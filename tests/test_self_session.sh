#!/usr/bin/env bash
# hh-spawn --self records the orchestrator's session: its SessionStart hook ran before the registration existed.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
mkdir -p "$CLAUDE_CONFIG_DIR/sessions" "$CLAUDE_CONFIG_DIR/projects/-a-proj" "$CLAUDE_CONFIG_DIR/projects/-b-other"
cp "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" "$CLAUDE_CONFIG_DIR/projects/-a-proj/sid-a.jsonl"
# a Claude stand-in: writes its own session record as Claude Code does, runs hh-spawn --self below itself, then, once told
# to, runs the SessionStart hook as a /clear would
mkdir -p "$T_TMP/cl"
cat > "$T_TMP/cl/claude" <<'EOF'
#!/usr/bin/env bash
jq -nc --argjson p $$ --arg s "$SID" '{pid:$p, name:"orch", sessionId:$s}' > "$CLAUDE_CONFIG_DIR/sessions/$$.json"
hh-spawn "$@" 2>"$OUT.err"; echo "rc=$?" >> "$OUT"
while [ ! -e "$OUT.go" ]; do sleep 0.2; done
printf '%s' "$HOOK_IN" | hh-session-hook; echo hooked >> "$OUT"
exec sleep 30
EOF
selfrun() {  # selfrun <out> <session id> [hook input]
  hh_tmux new-session -d -c "$r" -e "HIVEHOUSE_HOME=$HIVEHOUSE_HOME" -e "OUT=$1" -e "SID=$2" -e "HOOK_IN=${3:-}" \
    "bash $T_TMP/cl/claude --self --agent orchestrator >/dev/null"
  sleep 2
}
sj=$T_STATE/team/orchestrator/session.json
hookin=$(jq -nc --arg t "$T_TMP/after.jsonl" '{session_id:"after-clear", transcript_path:$t, source:"clear"}')
selfrun "$T_TMP/a.out" sid-a "$hookin"
assert_contains "--self ran" "$(cat "$T_TMP/a.out")" "rc=0"
assert_eq "--self records its session" "$(jq -r .session_id $sj)" "sid-a"
assert_eq "...with the one transcript of that name" "$(jq -r .transcript_path $sj)" "$CLAUDE_CONFIG_DIR/projects/-a-proj/sid-a.jsonl"
assert_eq "...from --self" "$(jq -r .source $sj)" "self"
assert_eq "...and nothing on stderr" "$(cat "$T_TMP/a.out.err")" ""
assert_eq "--self with no --window and no reading records no window" "$(jq -r '.agents[] | select(.name == "orchestrator") | has("window")' $T_STATE/team.json)" "false"
assert_eq "hh-context now reads the orchestrator" "$(hh-context orchestrator)" "10 (window assumed 1000000)"
assert_eq "...and so does --all" "$(hh-context --all)" "orchestrator 10 (window assumed 1000000)"
# a later /clear: the hook writes it again, as for any agent
cp "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" "$T_TMP/after.jsonl"
touch "$T_TMP/a.out.go"; sleep 2
assert_contains "the hook ran in the registered Claude" "$(cat "$T_TMP/a.out")" "hooked"
assert_eq "...and replaced the --self record" "$(jq -r '.session_id + " " + .source' $sj)" "after-clear clear"

# no transcript by that name, or two: nothing written, one warning, and an older session's record is not kept
selfrun "$T_TMP/b.out" sid-none
assert_contains "no transcript: --self still registers" "$(cat "$T_TMP/b.out")" "rc=0"
[ ! -e $sj ] && ok "...the earlier session's record is removed" || bad "a record of another session was kept: $(cat $sj)"
assert_eq "...and it warns once" "$(grep -c 'no single transcript' "$T_TMP/b.out.err")" "1"
assert_eq "hh-context: unknown, not another session's level" "$(hh-context --all)" "orchestrator ?"
cp "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" "$CLAUDE_CONFIG_DIR/projects/-a-proj/sid-two.jsonl"
cp "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" "$CLAUDE_CONFIG_DIR/projects/-b-other/sid-two.jsonl"
selfrun "$T_TMP/c.out" sid-two
[ ! -e $sj ] && ok "two transcripts of that name: nothing written" || bad "wrote a record from two transcripts"
assert_eq "...and it warns once" "$(grep -c 'no single transcript' "$T_TMP/c.out.err")" "1"
cp "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" "$CLAUDE_CONFIG_DIR/projects/-a-proj/x.jsonl"
selfrun "$T_TMP/d.out" '*'
[ ! -e $sj ] && ok "a session id that is a pattern finds nothing" || bad "a pattern session id matched: $(cat $sj)"

# the one writer keeps its guards for both callers
hh_write_session "$r" "../evil" s t self; assert_status "a bad agent name is not written" $? 1
hh_write_session "$r" orchestrator "" t self; assert_status "no session id is not written" $? 1
mkdir -p $T_STATE; echo x > $T_STATE/leak; git add -f $T_STATE/leak
hh_write_session "$r" orchestrator s t self; assert_status "a tracked $T_STATE is not written to" $? 1
git rm -qf --cached $T_STATE/leak
hh_write_session "$r" orchestrator s t self; assert_status "otherwise written" $? 0
[ -z "$(ls $T_STATE/team/orchestrator | grep tmp)" ] && ok "...with no temporary file left" || bad "a temporary file was left"
# the window Claude Code reported for this very session (hh-statusline's context.json), when there is one, is what --self records
echo '{"window":1000000,"used_percentage":9,"session_id":"sid-m","at":"t"}' > $T_STATE/team/orchestrator/context.json
selfrun "$T_TMP/m.out" sid-m
assert_contains "--self with a reading of this session" "$(cat "$T_TMP/m.out")" "rc=0"
assert_eq "...records the window Claude Code reported" "$(jq -r '.agents[] | select(.name == "orchestrator") | .window // "none"' $T_STATE/team.json)" "1000000"
echo '{"window":1000000,"used_percentage":9,"session_id":"an-older-session","at":"t"}' > $T_STATE/team/orchestrator/context.json
selfrun "$T_TMP/n.out" sid-n
assert_eq "a reading of another session is stale: the window this agent's record held is kept" "$(jq -r '.agents[] | select(.name == "orchestrator") | .window // "none"' $T_STATE/team.json)" "1000000"
rm -f $T_STATE/team/orchestrator/context.json
selfrun "$T_TMP/w.out" sid-w
assert_eq "no reading at all: the recorded window is kept, as the handoff is" "$(jq -r '.agents[] | select(.name == "orchestrator") | .window // "none"' $T_STATE/team.json)" "1000000"
jq '(.agents[] | select(.name == "orchestrator")) |= . + {window: 400000}' $T_STATE/team.json > "$T_TMP/t.json" && mv "$T_TMP/t.json" $T_STATE/team.json
echo '{"window":1000000,"used_percentage":9,"session_id":"sid-m2","at":"t"}' > $T_STATE/team/orchestrator/context.json
selfrun "$T_TMP/m2.out" sid-m2
assert_eq "a measured window beats the recorded one" "$(jq -r '.agents[] | select(.name == "orchestrator") | .window' $T_STATE/team.json)" "1000000"
rm -f $T_STATE/team/orchestrator/context.json
jq '(.agents[] | select(.name == "orchestrator")) |= del(.window)' $T_STATE/team.json > "$T_TMP/t.json" && mv "$T_TMP/t.json" $T_STATE/team.json
selfrun "$T_TMP/w2.out" sid-w2
assert_eq "nothing recorded, nothing measured: no window" "$(jq -r '.agents[] | select(.name == "orchestrator") | .window // "none"' $T_STATE/team.json)" "none"
cd /; t_teardown; t_done
