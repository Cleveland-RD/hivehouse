#!/usr/bin/env bash
# Usage: tests/run.sh [test file ...]   (no argument: every tests/test_*.sh)
set -u
cd "$(dirname "$0")"
files=("$@"); [ ${#files[@]} -eq 0 ] && files=(test_*.sh)
status=0
for f in ${files[@]+"${files[@]}"}; do
  echo "== $f"
  bash "$(basename "$f")" || status=1
done
exit $status
