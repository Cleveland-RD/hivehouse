#!/usr/bin/env bash
# Usage: tests/run.sh [test file ...]   (no argument: every tests/test_*.sh)
# A test that exits 128 or more was stopped by a signal, and the suite stops there.
# test_cleanup.sh signals real processes, so it runs only with HM_CLEANUP_TEST=1, named or not: the owner runs it, watching.
set -u
cd "$(dirname "$0")"
files=("$@"); [ ${#files[@]} -eq 0 ] && files=(test_*.sh)
status=0
for f in ${files[@]+"${files[@]}"}; do
  if [ "$(basename "$f")" = test_cleanup.sh ] && [ "${HM_CLEANUP_TEST:-}" != 1 ]; then
    echo "SKIP test_cleanup.sh (run by the owner: HM_CLEANUP_TEST=1)"; continue
  fi
  echo "== $f"
  bash "$(basename "$f")"; s=$?
  [ "$s" -ge 128 ] && exit "$s"
  [ "$s" -eq 0 ] || status=1
done
exit $status
