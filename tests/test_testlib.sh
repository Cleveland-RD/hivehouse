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
out=$(bash -c '. "$1"; t_guard; printf "%s %s" "$T_OWN_PG" "$(ps -o pgid= -p $$ | tr -d " ")"' _ "$HH_REPO_ROOT/tests/lib.sh")
assert_eq "under bash -c: that shell's own group" "${out% *}" "${out#* }"
[ -n "${out% *}" ] && ok "...and it is not empty" || bad "under bash -c: no group read"
# ---- KI-28: the sweep never deletes the folder of a run whose process is alive, whatever language its start time was written in ----
SW=$(mktemp -d "${TMPDIR:-/tmp}/hmsweep.XXXXXX"); SW=$(cd "$SW" && pwd -P); trap 'rm -f "$f"; rm -rf "$SW"' EXIT
sleep 60 & live=$!
mkrun() {  # mkrun <name> <start time as the run recorded it>: a run folder owned by the live process
  mkdir "$SW/$1" && printf '%s\t%s\n' "$live" "$2" > "$SW/$1/run.owner"
}
mkruns() { rm -rf "$SW"/hhtest.c "$SW"/hhtest.gb "$SW"/hhtest.fr "$SW"/hhtest.dead
  mkrun hhtest.c "$(LC_ALL=C /bin/ps -o lstart= -p $live | sed 's/^ *//;s/ *$//')"
  mkrun hhtest.gb "$(LC_ALL=en_GB.UTF-8 /bin/ps -o lstart= -p $live | sed 's/^ *//;s/ *$//')"
  mkrun hhtest.fr "$(LC_ALL=fr_FR.UTF-8 /bin/ps -o lstart= -p $live | sed 's/^ *//;s/ *$//')"
  mkrun hhtest.dead "Mon Jan  1 00:00:00 2001"; }
for lc in C en_GB.UTF-8 de_DE.UTF-8; do
  mkruns
  ( . "$HH_REPO_ROOT/tests/lib.sh"; TMPDIR="$SW" LC_ALL=$lc t_sweep_stale ) >/dev/null 2>&1
  for n in c gb fr; do [ -d "$SW/hhtest.$n" ] && ok "a live run's folder ($n) survives a sweep under $lc" || bad "a live run's folder ($n) was swept under $lc"; done
  [ ! -d "$SW/hhtest.dead" ] && ok "...and a run whose recorded start time is another process's is finished" || bad "a stale run (start time of another process) was kept under $lc"
done
kill $live 2>/dev/null; wait $live 2>/dev/null

# ---- KI-30: a TMPDIR that would put the test tmux socket over the macOS limit is refused at the start ----
LONG="$SW"; while [ ${#LONG} -lt 100 ]; do LONG="$LONG/x"; done; mkdir -p "$LONG"
out=$(TMPDIR="$LONG" bash -c '. "$1"; t_setup; echo started' _ "$HH_REPO_ROOT/tests/lib.sh" 2>&1 </dev/null); rc=$?
[ "$rc" -ne 0 ] && ok "a long TMPDIR stops t_setup" || bad "a long TMPDIR was accepted"
assert_contains "...saying why and what to set" "$out" "TMPDIR"
case "$out" in *started*) bad "...nothing runs after the refusal" ;; *) ok "...nothing runs after the refusal" ;; esac
[ -z "$(ls -A "$LONG")" ] && ok "...and no folder was made there" || bad "the refused run left files in $LONG"
SHORT="$SW/s"; mkdir -p "$SHORT"
out=$(TMPDIR="$SHORT" bash -c '. "$1"; t_setup; echo started; t_teardown' _ "$HH_REPO_ROOT/tests/lib.sh" 2>&1 </dev/null)
assert_contains "a short TMPDIR starts" "$out" "started"

[ "$FAILS" -eq 0 ] || exit 1
