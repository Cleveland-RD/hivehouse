#!/usr/bin/env bash
# hh-cleanup --dry-run reads every manifest entry through fd 3, newest first, and changes nothing. It starts no process and deletes nothing,
# so unlike test_cleanup.sh it runs without the owner. It pins the loop that reads the entries: a line dropped from what is fed to it is a missing line here.
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo dry); cd "$r" || exit 2
mkdir -p "$T_TMP/out/a" "$T_TMP/out/b" "$T_TMP/out/c"
hh-manifest add dir path="$T_TMP/out/a" >/dev/null
hh-manifest add dir path="$T_TMP/out/b" >/dev/null
hh-manifest add dir path="$T_TMP/out/c" >/dev/null
before=$(cat "$T_STATE/manifest.jsonl")
out=$(hh-cleanup --finish --dry-run); assert_status "dry run" $? 0
for d in a b c; do assert_contains "a line for $d" "$out" "dir $T_TMP/out/$d by=owner"; done
assert_eq "one line per entry, newest first" "$(printf '%s\n' "$out" | grep -o "out/[abc] " | tr -d ' \n')" "out/cout/bout/a"
for d in a b c; do [ -d "$T_TMP/out/$d" ] && ok "dry run leaves $d" || bad "dry run removed $d"; done
assert_eq "dry run leaves the manifest as it was" "$(cat "$T_STATE/manifest.jsonl")" "$before"
t_done
