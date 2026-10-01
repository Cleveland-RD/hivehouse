#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
LOG="$T_TMP/gate.log"

# ---- hm-gate ------------------------------------------------------------------------------------------------------
hm-gate --log "$LOG" -- a true b 'echo out; echo err >&2; false' c 'touch ran-c'; assert_status "a failing step fails the gate" $? 1
assert_eq "one line per step, in order" "$(cat "$LOG")" "$(printf 'a exit 0\nb exit 1\nc exit 0')"
[ -f ran-c ] && ok "every step runs after a failure" || bad "every step runs after a failure"
assert_eq "a step's output goes to its own log" "$(cat "$LOG.d/b.log")" "$(printf 'out\nerr')"
assert_eq "the slot is released after the gate" "$(hm-slot status)" "free"
hm-gate --log "$LOG" -- only true; assert_status "all green is exit 0" $? 0
assert_eq "a rerun leaves no line of the earlier run" "$(cat "$LOG")" "only exit 0"
[ ! -e "$LOG.d/b.log" ] && ok "a rerun leaves no step log of the earlier run" || bad "a rerun leaves no step log of the earlier run"
hm-gate --log "$LOG" -- s 'hm-slot status'; assert_contains "the gate holds the slot under its label" "$(cat "$LOG.d/s.log")" '"label":"gate"'
# every argument is checked before anything runs: a first step that touches a file must not have run
T="touch '$T_TMP/touched'"
for args in "-- first \"$T\" a" "-- first \"$T\" ../x true" "-- first \"$T\" a..b true" "-- first \"$T\" 'a b' true" "-- first \"$T\" a true a true" "--" "first \"$T\""; do
  rm -f "$T_TMP/touched"
  eval "hm-gate --log \"$LOG\" $args 2>/dev/null"; s=$?
  label=${args//"$T_TMP"/T}
  assert_status "refused: $label" $s 64
  [ ! -e "$T_TMP/touched" ] && ok "nothing ran: $label" || bad "nothing ran: $label"
done
hm-gate -- x true 2>/dev/null; assert_status "no --log is a usage error" $? 64
# a busy slot: nothing runs and no log is written
sleep 30 & holder=$!; hm-slot acquire other --pid $holder
rm -f "$LOG"; hm-gate --log "$LOG" -- t "touch '$T_TMP/busy-ran'" 2>/dev/null; assert_status "a busy slot is exit 75" $? 75
[ ! -e "$T_TMP/busy-ran" ] && [ ! -e "$LOG" ] && ok "a busy slot runs nothing and writes no log" || bad "a busy slot runs nothing and writes no log"
hm-slot release --pid $holder; kill $holder; wait $holder 2>/dev/null
# an interrupted gate stops now, writes no line for the step it stopped, and frees the slot
hm-gate --log "$LOG" -- done true slow 'sleep 20' never true & g=$!; sleep 2
t0=$SECONDS; kill -TERM $g; wait $g; assert_status "a TERM stops the gate with 143" $? 143
[ $((SECONDS - t0)) -lt 5 ] && ok "at once, not when the step ends" || bad "at once, not when the step ends: $((SECONDS - t0)) s"
assert_eq "no line for the step it stopped, none after" "$(cat "$LOG")" "done exit 0"
assert_eq "the slot is freed" "$(hm-slot status)" "free"

# ---- hm-gate-verify log --------------------------------------------------------------------------------------------
printf 'a exit 0\nb exit 0\n' > "$T_TMP/g.log"
out=$(hm-gate-verify log "$T_TMP/g.log"); assert_status "green log" $? 0; assert_eq "green says its step count" "$out" "GREEN (2 steps)"
hm-gate --log "$LOG" -- a true b false c true >/dev/null 2>&1
out=$(hm-gate-verify log "$LOG" 2>&1); assert_status "a red step is red" $? 1; assert_contains "red names the failing step" "$out" "b exit 1"
printf 'nothing ran here\n' > "$T_TMP/none.log"
out=$(hm-gate-verify log "$T_TMP/none.log" 2>&1); assert_status "no step lines is red" $? 1; assert_contains "and says so" "$out" "no steps"
: > "$T_TMP/empty.log"; hm-gate-verify log "$T_TMP/empty.log" >/dev/null 2>&1; assert_status "an empty log is red" $? 1
hm-gate-verify log "$T_TMP/missing.log" >/dev/null 2>&1; assert_status "a missing log is red" $? 1
out=$(hm-gate-verify log "$T_TMP/g.log" --expect a,z 2>&1); assert_status "a missing expected step is red" $? 1; assert_contains "and is named" "$out" "z"
hm-gate-verify log "$T_TMP/g.log" --expect a,b >/dev/null; assert_status "every expected step present" $? 0
hm-gate-verify log "$T_TMP/g.log" --expect 'a,.*' >/dev/null 2>&1; assert_status "an expected name is a step name" $? 64
printf 'a exit 0\n  b exit 1\nb exit 1 later\n' > "$T_TMP/loose.log"
assert_eq "only whole step lines count" "$(hm-gate-verify log "$T_TMP/loose.log")" "GREEN (1 steps)"

# ---- hm-gate-verify commits ----------------------------------------------------------------------------------------
base=$(git rev-parse HEAD)
c() { local msg="$1"; shift; for f in "$@"; do echo "$RANDOM" > "$f"; done; git add -A; git commit -qm "$msg"; }
COMMON="--max-files 5 --style conventional --attribution deny"
c "feat(gate): one good commit" f1
hm-gate-verify commits "$base..HEAD" $COMMON >/dev/null; assert_status "a good commit passes" $? 0
assert_eq "it says how many" "$(hm-gate-verify commits "$base..HEAD" $COMMON)" "OK (1 commits)"
good=$(git rev-parse HEAD)
c "$(printf 'fix: a fix\n\nCo-Authored-By: Someone <x@y>')" f2
out=$(hm-gate-verify commits "$good..HEAD" $COMMON 2>&1); assert_status "a Co-Authored-By trailer fails under deny" $? 1; assert_contains "named as attribution" "$out" "attribution"
hm-gate-verify commits "$good..HEAD" --max-files 5 --style conventional --attribution allow >/dev/null 2>&1; assert_status "and passes under allow" $? 0
for trailer in 'co-authored-by: x' 'Claude-Session: abc' 'Generated with [Claude Code](https://claude.com/claude-code)'; do
  git reset -q --hard "$good"; c "$(printf 'fix: a fix\n\n%s' "$trailer")" f2
  hm-gate-verify commits "$good..HEAD" $COMMON >/dev/null 2>&1; assert_status "deny refuses: $trailer" $? 1
done
git reset -q --hard "$good"; c "fix: six files" g1 g2 g3 g4 g5 g6
out=$(hm-gate-verify commits "$good..HEAD" $COMMON 2>&1); assert_status "a 6-file commit fails --max-files 5" $? 1; assert_contains "named as files" "$out" "files"
git reset -q --hard "$good"; c "update stuff" f3
hm-gate-verify commits "$good..HEAD" $COMMON >/dev/null 2>&1; assert_status "a free subject fails conventional" $? 1
hm-gate-verify commits "$good..HEAD" --max-files 5 --style free --attribution deny >/dev/null 2>&1; assert_status "and passes free" $? 0
git reset -q --hard "$good"; c "$(printf 'fix: with a body\n\nsome words')" f4
out=$(hm-gate-verify commits "$good..HEAD" $COMMON 2>&1); assert_status "a body is only a warning" $? 0; assert_contains "and is warned of" "$out" "WARN"
hm-gate-verify commits "$good..HEAD" $COMMON --no-body >/dev/null 2>&1; assert_status "a body fails with --no-body" $? 1
hm-gate-verify commits "HEAD..HEAD" $COMMON >/dev/null 2>&1; assert_status "an empty range is red" $? 1
out=$(hm-gate-verify commits "--output=$T_TMP/x..HEAD" $COMMON 2>&1); assert_status "a range starting with - is refused" $? 4
assert_contains "as an option, before git sees it" "$out" "may not start with '-'"
[ ! -e "$T_TMP/x..HEAD" ] && [ ! -e "$T_TMP/x" ] && ok "and writes nothing" || bad "and writes nothing"
hm-gate-verify commits "HEAD" $COMMON >/dev/null 2>&1; assert_status "a range must be base..tip" $? 64
hm-gate-verify commits "nope..HEAD" $COMMON >/dev/null 2>&1; assert_status "an unknown base is refused" $? 4
hm-gate-verify commits "$good..HEAD" --max-files 5 --style conventional >/dev/null 2>&1; assert_status "every flag is required" $? 64
hm-gate-verify commits "$good..HEAD" --max-files 0 --style conventional --attribution deny >/dev/null 2>&1; assert_status "max-files must be a positive number" $? 64
hm-gate-verify commits "$good..HEAD" --max-files 5 --style loose --attribution deny >/dev/null 2>&1; assert_status "an unknown style is refused" $? 64
hm-gate-verify nothing 2>/dev/null; assert_status "an unknown mode is a usage error" $? 64
t_done
