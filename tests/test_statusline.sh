#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
d="$T_TMP/agent dir"; mkdir -p "$d"
in='{"session_id":"s1","context_window":{"context_window_size":1000000,"used_percentage":9.2},"model":{"id":"m"}}'
own='cat > "$OWNER_IN"; echo OWNER LINE; exit 3'   # the owner's command arrives as the second argument, quoted into --settings by hh-spawn
export OWNER_IN="$T_TMP/owner.in"

out=$(printf '%s' "$in" | hh-statusline "$d" "$own"); rc=$?
assert_eq "the owner's statusLine prints what the pane shows" "$out" "OWNER LINE"
assert_status "...and its exit status is passed through" "$rc" 3
assert_eq "...and it got the same input" "$(jq -r .session_id "$OWNER_IN")" "s1"
assert_eq "Claude Code's window is kept" "$(jq -r .window "$d/context.json")" "1000000"
assert_eq "...with its percent and session" "$(jq -r '"\(.used_percentage) \(.session_id)"' "$d/context.json")" "9.2 s1"
assert_contains "...and when it was read" "$(jq -r .at "$d/context.json")" "T"
[ -z "$(ls "$d" | grep tmp)" ] && ok "no temporary file is left" || bad "a temporary file was left: $(ls "$d")"

# a write that fails costs the owner nothing: same line, same status, no file
rm -f "$d/context.json"; chmod 555 "$d"
out=$(printf '%s' "$in" | hh-statusline "$d" "$own" 2>"$T_TMP/err"); rc=$?
chmod 755 "$d"
assert_eq "an unwritable agent dir: the owner's line still shows" "$out" "OWNER LINE"
assert_status "...with its own status" "$rc" 3
assert_eq "...and nothing on stderr" "$(cat "$T_TMP/err")" ""
[ ! -e "$d/context.json" ] && ok "...and no context.json" || bad "context.json written into an unwritable dir"
out=$(printf '%s' "$in" | hh-statusline "$T_TMP/no such dir"); rc=$?
assert_status "a missing agent dir is no error" "$rc" 0
assert_eq "...and prints nothing (no owner recorded there)" "$out" ""

# input that carries no window (before the first reply, or another shape) keeps nothing and still runs the owner's line
printf '%s\n' '{"session_id":"old","window":5,"at":"x"}' > "$d/context.json"
out=$(printf '%s' '{"session_id":"s2","context_window":{"context_window_size":null}}' | hh-statusline "$d" "$own")
assert_eq "no window: the owner's line still shows" "$out" "OWNER LINE"
assert_eq "...and the last good reading stays" "$(jq -r .session_id "$d/context.json")" "old"
out=$(printf 'not json' | hh-statusline "$d" "$own"); rc=$?
assert_eq "input that is not JSON: the owner's line still shows" "$out" "OWNER LINE"
printf '%s' '{"session_id":"s3","context_window":{"context_window_size":200000,"used_percentage":null}}' | hh-statusline "$d" "$own" >/dev/null
assert_eq "a null percent (no reply yet) still keeps the window" "$(jq -r '"\(.window) \(.used_percentage)"' "$d/context.json")" "200000 null"

# no owner statusLine: nothing printed, status 0
out=$(printf '%s' "$in" | hh-statusline "$d"); rc=$?
assert_eq "no owner statusLine prints nothing" "$out" ""
assert_status "...and exits 0" "$rc" 0
assert_eq "...and still keeps the window" "$(jq -r .session_id "$d/context.json")" "s1"

# the owner's statusLine, in Claude Code's order: managed, then the project's local file, then the project's, then the user's
p="$T_TMP/proj"; mkdir -p "$p/.claude"
assert_eq "none anywhere: nothing" "$(hh_owner_statusline "$p")" ""
echo '{"statusLine":{"type":"command","command":"user"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
assert_eq "the user's" "$(hh_owner_statusline "$p" | jq -r .command)" "user"
echo '{"statusLine":{"type":"command","command":"project"}}' > "$p/.claude/settings.json"
assert_eq "the project's beats the user's" "$(hh_owner_statusline "$p" | jq -r .command)" "project"
echo '{"statusLine":{"type":"command","command":"local"}}' > "$p/.claude/settings.local.json"
assert_eq "the local file beats the project's" "$(hh_owner_statusline "$p" | jq -r .command)" "local"
echo '{"statusLine":{"type":"command","command":"managed"}}' > "$HH_MANAGED_SETTINGS"
assert_eq "managed beats them all" "$(hh_owner_statusline "$p" | jq -r .command)" "managed"
echo '{"model":"x"}' > "$HH_MANAGED_SETTINGS"; echo 'not json' > "$p/.claude/settings.local.json"
assert_eq "a file with no statusLine, or not JSON, is passed over" "$(hh_owner_statusline "$p" | jq -r .command)" "project"
# A12: a statusline.json in the agent's folder is never read, never run: that file is writable by an away session, so a command found there
# would run as the owner outside every hook
printf '%s\n' '{"type":"command","command":"echo PLANTED"}' > "$d/statusline.json"
out=$(printf '%s' "$in" | hh-statusline "$d"); assert_eq "a planted statusline.json is not run (no owner given)" "$out" ""
out=$(printf '%s' "$in" | hh-statusline "$d" "$own"); assert_eq "...nor beside an owner's command" "$out" "OWNER LINE"
cd /; t_teardown; t_done
