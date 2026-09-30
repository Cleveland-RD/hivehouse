#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo a)
assert_eq "repo has a commit" "$(git -C "$r" rev-list --count HEAD)" "1"
( FAILS=0; assert_eq "a failing assert fails" "1" "2" >/dev/null; [ "$FAILS" -eq 1 ] ) && ok "harness counts failures" || bad "harness counts failures"
d="$T_TMP"; ( t_teardown ); [ -e "$d" ] && bad "teardown removes the scratch dir" || ok "teardown removes the scratch dir"
T_TMP="$d"; t_done
