#!/usr/bin/env bash
# The reaper's own guard in tests/lib.sh (t_guard): what teardown must never signal. It only reads ps, so this test
# starts no process it signals and calls no t_setup (whose sweep could).
. "$(dirname "$0")/lib.sh"
f=$(mktemp "${TMPDIR:-/tmp}/hmguard.XXXXXX"); trap 'rm -f "$f"' EXIT
t_guard
assert_eq "this shell's own group" "$T_OWN_PG" "$(ps -o pgid= -p $$ | tr -d ' ')"
assert_contains "this shell is above" "$T_ABOVE" " $$ "
assert_contains "...and its parent" "$T_ABOVE" " $PPID "
set -m
( t_guard; printf '%s\n%s\n' "$T_OWN_PG" "$T_ABOVE" > "$f" ) & s=$!
set +m
wait $s
assert_eq "a subshell in its own group: that group" "$(sed -n 1p "$f")" "$s"
assert_contains "...the subshell itself is above" "$(sed -n 2p "$f")" " $s "
assert_contains "...and so is the shell that started it" "$(sed -n 2p "$f")" " $$ "
# under bash -c, a command substitution forks a child that sh then reports as its parent and that is gone afterwards
out=$(bash -c '. "$1"; t_guard; printf "%s %s" "$T_OWN_PG" "$(ps -o pgid= -p $$ | tr -d " ")"' _ "$HM_REPO_ROOT/tests/lib.sh")
assert_eq "under bash -c: that shell's own group" "${out% *}" "${out#* }"
[ -n "${out% *}" ] && ok "...and it is not empty" || bad "under bash -c: no group read"
[ "$FAILS" -eq 0 ] || exit 1
