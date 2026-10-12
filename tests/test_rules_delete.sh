#!/usr/bin/env bash
# R4: the rule for scripts that delete is in RULES.md, read by every agent, and the implementer role names it among what the role never does.
. "$(dirname "$0")/lib.sh"
t_setup
flat() { tr '\n' ' ' < "$1" | sed 's/  */ /g'; }
rules=$(flat "$HH_REPO_ROOT/rules/RULES.md"); role=$(flat "$HH_REPO_ROOT/roles/implementer.md")
assert_contains "RULES.md has a section for scripts that delete" "$rules" "## Scripts that delete"
assert_contains "...a script starts with set -euo pipefail" "$rules" 'A script you write starts with `set -euo pipefail`'
assert_contains "...every rm -r operand built from a variable uses \${VAR:?}" "$rules" 'every `rm -r` operand built from a variable is written `${VAR:?}`'
assert_contains "...deletion is tested only under a scratch fake root" "$rules" "Test deletion only under a scratch fake root"
assert_contains "...and the guards are named the last line, not the rule" "$rules" "the last line, not the rule"
assert_contains "the implementer role never writes such a script without them" "$role" 'write a script that deletes without `set -euo pipefail`'
assert_contains "...nor tests one outside a scratch fake root" "$role" "under a scratch fake root"
cd /; t_teardown; t_done
