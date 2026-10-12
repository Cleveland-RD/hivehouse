#!/usr/bin/env bash
# R7: the harness never removes a folder it did not make. t_setup stops (exit 2, with a hint) when TMPDIR cannot hold its run folder, instead of
# taking the current folder for it; t_teardown removes only a real, owned folder named hhtest.?????? that holds run.owner. Every run below starts
# in a scratch folder inside this test's own T_TMP, with a sentinel in it: a harness that deleted its current folder would show here, not in the repo.
. "$(dirname "$0")/lib.sh"
t_setup
SCR="$T_TMP/scr"; mkdir -p "$SCR"; : > "$SCR/sentinel"
case "$SCR" in "$T_TMP"/*) ok "the scratch folder is inside this test's T_TMP" ;; *) bad "the scratch folder is outside T_TMP: stopping"; exit 2 ;; esac
LIB="$HH_REPO_ROOT/tests/lib.sh"
cat > "$T_TMP/tiny.sh" <<T
. "$LIB"
t_setup
echo started
t_teardown
T

echo "-- t_setup with a TMPDIR that cannot hold the run folder"
SHORT=$(t_outside_tmp); MISSING="$SHORT/not-made"   # a short place: the socket path limit is checked after the folder exists
out=$(cd "$SCR" && TMPDIR="$MISSING" bash "$T_TMP/tiny.sh" 2>&1 </dev/null); rc=$?
assert_eq "a TMPDIR folder that does not exist: exit 2" "$rc" "2"
assert_contains "...with the hint" "$out" "TMPDIR=$MISSING does not exist: mkdir -p it first"
case "$out" in *started*) bad "...the test ran anyway" ;; *) ok "...and the test did not run" ;; esac
[ -d "$SCR" ] && [ -e "$SCR/sentinel" ] && ok "...and the current folder and its sentinel survive" || bad "the current folder (or its sentinel) was removed"
if [ "$(id -u)" != 0 ]; then
  RO=$(t_outside_tmp); chmod 555 "$RO"
  out=$(cd "$SCR" && TMPDIR="$RO" bash "$T_TMP/tiny.sh" 2>&1 </dev/null); rc=$?
  assert_eq "a TMPDIR folder that cannot be written: exit 2" "$rc" "2"
  assert_contains "...with a hint" "$out" "TMPDIR=$RO cannot be written"
  [ -d "$SCR" ] && [ -e "$SCR/sentinel" ] && ok "...and the current folder survives" || bad "the current folder was removed"
  chmod 755 "$RO"
fi
out=$(cd "$SCR" && TMPDIR="$SHORT" bash "$T_TMP/tiny.sh" 2>&1 </dev/null); rc=$?
assert_eq "a TMPDIR that exists: the run starts and ends: exit 0" "$rc" "0"
assert_contains "...and says started" "$out" "started"
[ -e "$SCR/sentinel" ] && ok "...and leaves the current folder alone" || bad "the current folder was removed"

echo "-- the tests that make their own scratch folder"
for t in test_testlib.sh test_run.sh; do
  out=$(cd "$SCR" && TMPDIR="$MISSING" bash "$HH_REPO_ROOT/tests/$t" 2>&1 </dev/null); rc=$?
  assert_eq "$t with a TMPDIR that does not exist: exit 2" "$rc" "2"
  assert_contains "...and says why" "$out" "mkdir -p it first"
  [ -d "$SCR" ] && [ -e "$SCR/sentinel" ] && ok "...and the current folder survives" || bad "$t removed the current folder"
done

echo "-- t_teardown removes only a harness folder"
td() {  # td <folder>: a teardown whose T_TMP is that folder, in a shell of its own, started from the scratch folder; sets ERR
  ERR=$(cd "$SCR" && HH_TMUX_SOCKET="$SCR/none.sock" bash -c '. "$1"; T_TMP="$2"; t_teardown; echo "T_TMP=[$T_TMP]"' _ "$LIB" "$1" 2>&1 </dev/null)
}
PLAIN="$T_TMP/plain"; mkdir -p "$PLAIN"; : > "$PLAIN/keep"; : > "$PLAIN/run.owner"   # even one that holds a run.owner
td "$PLAIN"; [ -e "$PLAIN/keep" ] && ok "a folder not named hhtest.?????? is not removed" || bad "a plain folder was removed"
assert_contains "...and the refusal is said on stderr" "$ERR" "not removing"
NOOWN="$T_TMP/hhtest.AAAAAA"; mkdir -p "$NOOWN"; : > "$NOOWN/keep"
td "$NOOWN"; [ -e "$NOOWN/keep" ] && ok "a folder named hhtest.?????? with no run.owner is not removed" || bad "a folder with no run.owner was removed"
REAL="$T_TMP/realdir"; mkdir -p "$REAL"; : > "$REAL/keep"; : > "$REAL/run.owner"; ln -s "$REAL" "$T_TMP/hhtest.BBBBBB"
td "$T_TMP/hhtest.BBBBBB"; [ -e "$REAL/keep" ] && [ -L "$T_TMP/hhtest.BBBBBB" ] && ok "a link named hhtest.?????? is not followed or removed" || bad "a link was followed or removed"
td ""; [ -d "$SCR" ] && ok "an empty T_TMP removes nothing" || bad "an empty T_TMP removed the current folder"
GOOD="$T_TMP/hhtest.CCCCCC"; mkdir -p "$GOOD"; : > "$GOOD/run.owner"; : > "$GOOD/keep"
td "$GOOD"; [ ! -e "$GOOD" ] && ok "a harness folder (named hhtest.??????, holding run.owner) is removed" || bad "a harness folder was not removed"
[ -d "$SCR" ] && [ -e "$SCR/sentinel" ] && ok "...and the current folder is untouched" || bad "the current folder was removed"
cd /; t_teardown; t_done
