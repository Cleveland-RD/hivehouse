#!/usr/bin/env bash
# R2: bin/hh-guard-env, the SessionStart hook that puts bin/guard first in PATH for every Bash command of a session through CLAUDE_ENV_FILE
# (appended once, so a resume adds no second copy), and hooks/hooks.json wiring it for every start, clear and resume. hh-spawn and the hub's
# orchestrator start give their panes the same PATH (test_spawn.sh and test_hub.sh read it from the pane): through the command, not tmux -e, since a shell rewrites PATH at startup.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
G="$HH_REPO_ROOT/bin/guard"; E="$T_TMP/env.sh"; HOOK="$HH_REPO_ROOT/bin/hh-guard-env"
LINE="export PATH=\"$G:\$PATH\""
run() { printf '{"session_id":"s","source":"%s"}' "${1:-startup}" | CLAUDE_ENV_FILE="$E" "$HOOK"; }

echo "-- the line"
: > "$E"; run startup; assert_status "the hook exits 0" $? 0
assert_eq "it appends exactly the export line" "$(cat "$E")" "$LINE"
assert_eq "a Bash command that runs the file finds the guard's rm first" "$(PATH=/usr/bin:/bin bash -c ". '$E'; command -v rm")" "$G/rm"
assert_eq "...and find, and rsync" "$(PATH=/usr/bin:/bin bash -c ". '$E'; command -v find rsync" | tr '\n' ' ')" "$G/find $G/rsync "
run resume; run clear; assert_eq "a resume and a clear append nothing more" "$(wc -l < "$E" | tr -d ' ')" "1"
: > "$E"; printf '{}' | PATH="$G:/usr/bin:/bin" CLAUDE_ENV_FILE="$E" "$HOOK"; assert_eq "with the guard already first in PATH it adds nothing" "$(wc -l < "$E" | tr -d ' ')" "0"
printf 'export FOO=1\n' > "$E"; run; assert_eq "another line already there is kept, the guard's added after it" "$(cat "$E")" "export FOO=1
$LINE"
echo "-- it never fails the session"
printf '{}' | env -u CLAUDE_ENV_FILE "$HOOK"; assert_status "no CLAUDE_ENV_FILE: exit 0" $? 0
printf '{}' | CLAUDE_ENV_FILE="$T_TMP/no/such/dir/env.sh" "$HOOK" 2>/dev/null; assert_status "an env file that cannot be written: exit 0" $? 0
"$HOOK" < /dev/null; assert_status "no input: exit 0" $? 0

echo "-- wiring"
assert_eq "hooks.json runs hh-guard-env at SessionStart" "$(jq -r '[.hooks.SessionStart[].hooks[].command | select(contains("hh-guard-env"))] | length' "$HH_REPO_ROOT/hooks/hooks.json")" "1"
assert_eq "...for every source (no matcher)" "$(jq -r '[.hooks.SessionStart[] | select(.hooks[].command | contains("hh-guard-env")) | .matcher // "none"] | .[0]' "$HH_REPO_ROOT/hooks/hooks.json")" "none"
assert_eq "...through the plugin root, like the other hooks" "$(jq -r '.hooks.SessionStart[].hooks[].command | select(contains("hh-guard-env"))' "$HH_REPO_ROOT/hooks/hooks.json")" "\"\${CLAUDE_PLUGIN_ROOT}/bin/hh-guard-env\""
[ -x "$HOOK" ] && ok "the hook is executable" || bad "the hook is not executable"
echo "-- hh_guard_launch"
assert_eq "the prefix a pane's command starts with" "$(hh_guard_launch)" "export PATH=$G:\"\$PATH\"; "
assert_eq "...run by a shell whose startup rewrote PATH, it still puts the guard first" "$(PATH=/usr/bin:/bin sh -c "$(hh_guard_launch)command -v rm")" "$G/rm"
cd /; t_teardown; t_done
