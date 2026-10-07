#!/usr/bin/env bash
# tests/run.sh skips test_cleanup.sh unless HH_CLEANUP_TEST=1. Run against a copy of run.sh beside stub tests that
# only print, so nothing here starts or signals a process of its own (no t_setup: its sweep could).
. "$(dirname "$0")/lib.sh"
stub=$(mktemp -d "${TMPDIR:-/tmp}/hmrun.XXXXXX"); trap 'rm -rf "$stub"' EXIT
cp "$HH_REPO_ROOT/tests/run.sh" "$stub/run.sh"
for n in a cleanup z; do printf 'echo "RAN %s"\n' "$n" > "$stub/test_$n.sh"; done
SKIP="SKIP test_cleanup.sh (run by the owner: HH_CLEANUP_TEST=1)"
out=$(env -u HH_CLEANUP_TEST bash "$stub/run.sh"); assert_status "the whole suite passes with the skip" $? 0
assert_contains "the whole suite says it skips test_cleanup.sh" "$out" "$SKIP"
case "$out" in *"RAN cleanup"*) bad "the whole suite ran test_cleanup.sh";; *) ok "the whole suite does not run test_cleanup.sh";; esac
assert_contains "...and runs the others" "$out" "RAN a"
assert_contains "...all of them" "$out" "RAN z"
for arg in test_cleanup.sh "$stub/test_cleanup.sh" ./test_cleanup.sh; do
  out=$(env -u HH_CLEANUP_TEST bash "$stub/run.sh" "$arg")
  case "$out" in *"RAN cleanup"*) bad "named as $arg, test_cleanup.sh ran";; *) ok "named as $arg, test_cleanup.sh is skipped";; esac
  assert_contains "...and says so" "$out" "$SKIP"
done
for v in 0 yes true ""; do
  out=$(env HH_CLEANUP_TEST="$v" bash "$stub/run.sh" test_cleanup.sh)
  case "$out" in *"RAN cleanup"*) bad "HH_CLEANUP_TEST=[$v] ran test_cleanup.sh";; *) ok "HH_CLEANUP_TEST=[$v] still skips";; esac
done
out=$(env HH_CLEANUP_TEST=1 bash "$stub/run.sh"); assert_status "HH_CLEANUP_TEST=1: the whole suite" $? 0
assert_contains "HH_CLEANUP_TEST=1 runs test_cleanup.sh in the whole suite" "$out" "RAN cleanup"
case "$out" in *SKIP*) bad "HH_CLEANUP_TEST=1 still printed a skip";; *) ok "HH_CLEANUP_TEST=1 prints no skip";; esac
out=$(env HH_CLEANUP_TEST=1 bash "$stub/run.sh" test_cleanup.sh)
assert_contains "HH_CLEANUP_TEST=1 runs it when named" "$out" "RAN cleanup"
# a test stopped by a signal (its trap exits 128+n) stops the suite; a failing one does not
mkdir "$stub/stop" "$stub/fail"; cp "$HH_REPO_ROOT/tests/run.sh" "$stub/stop/run.sh"; cp "$HH_REPO_ROOT/tests/run.sh" "$stub/fail/run.sh"
printf 'echo "RAN a"\n' > "$stub/stop/test_a.sh"; printf 'exit 130\n' > "$stub/stop/test_b.sh"; printf 'echo "RAN c"\n' > "$stub/stop/test_c.sh"
out=$(bash "$stub/stop/run.sh"); assert_status "a test that exits 130 stops the suite with 130" $? 130
case "$out" in *"RAN c"*) bad "the suite went on after a stopped test";; *) ok "...and no test after it runs";; esac
printf 'echo "RAN a"\n' > "$stub/fail/test_a.sh"; printf 'exit 1\n' > "$stub/fail/test_b.sh"; printf 'echo "RAN c"\n' > "$stub/fail/test_c.sh"
out=$(bash "$stub/fail/run.sh"); assert_status "a failing test fails the suite" $? 1
assert_contains "...which goes on to the next" "$out" "RAN c"
# test_cleanup.sh guards itself too, before it sources anything: read its first command and run that line alone
guard='[ "${HH_CLEANUP_TEST:-}" = 1 ] || { echo "SKIP test_cleanup.sh (run by the owner: HH_CLEANUP_TEST=1)"; exit 0; }'
first=$(grep -v '^#' "$HH_REPO_ROOT/tests/test_cleanup.sh" | grep -v '^[[:space:]]*$' | head -1)
assert_eq "test_cleanup.sh's first command is its own guard" "$first" "$guard"
if [ "$first" = "$guard" ]; then   # run the line only when it is the guard, so a broken file runs nothing of its own
  out=$(env -u HH_CLEANUP_TEST bash -c "$first; echo PAST"); assert_status "...which exits 0 unasked" $? 0
  assert_eq "...says so and goes no further" "$out" "$SKIP"
  out=$(env HH_CLEANUP_TEST=1 bash -c "$first; echo PAST"); assert_eq "...and lets HH_CLEANUP_TEST=1 through" "$out" "PAST"
fi
[ "$FAILS" -eq 0 ] || exit 1
