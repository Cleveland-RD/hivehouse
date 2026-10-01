#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
out=$(hm-disk --path "$T_TMP" --min-gb 0); assert_status "above zero is fine" $? 0
assert_contains "prints free" "$out" "free_gb="
hm-disk --path "$T_TMP" --min-gb 999999 >/dev/null; assert_status "below is exit 1" $? 1
h=$(hm-disk --path "$T_TMP" --min-gb 999999 --hook); assert_eq "hook json" "$(printf '%s' "$h" | jq -r .hookSpecificOutput.hookEventName)" "SessionStart"
assert_eq "hook silent when fine" "$(hm-disk --path "$T_TMP" --min-gb 0 --hook)" ""
hm-disk --bogus >/dev/null 2>&1; assert_status "unknown flag is usage error" $? 64
hm-disk --path "$T_TMP/no/such/dir" --min-gb 1 >/dev/null 2>&1; assert_status "a missing path is a usage error, not low disk" $? 4
hm-disk --path "$T_TMP" --min-gb abc >/dev/null 2>&1; assert_status "a non-numeric --min-gb is refused" $? 4
hm-disk --path "$T_TMP" --min-gb 1.5 >/dev/null 2>&1; assert_status "a fractional --min-gb is accepted" $? 0
hm-disk --path "$T_TMP" --min-gb -3 >/dev/null 2>&1; assert_status "a negative --min-gb is refused" $? 4
t_teardown; t_done
