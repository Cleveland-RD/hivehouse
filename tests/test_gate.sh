#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
LOG="$T_TMP/gate.log"

LOCK="$HIVEMIND_HOME/slot.lock"
steps() { grep -v '^#' "$1"; }   # the step lines of a gate log, without its header
head_now=$(git rev-parse HEAD)

# ---- hm-gate ------------------------------------------------------------------------------------------------------
hm-gate --log "$LOG" -- a true b 'echo out; echo err >&2; false' c 'touch "$TMPDIR/ran-c"'; assert_status "a failing step fails the gate" $? 1
assert_eq "a header names every step, the commit and whether the tree was clean" "$(head -1 "$LOG")" "# hm-gate steps: a,b,c head=$head_now dirty=0"
assert_eq "one line per step, in order" "$(steps "$LOG")" "$(printf 'a exit 0\nb exit 1\nc exit 0')"
[ -f "$TMPDIR/ran-c" ] && ok "every step runs after a failure" || bad "every step runs after a failure"
assert_eq "a step's output goes to its own log" "$(cat "$LOG.d/b.log")" "$(printf 'out\nerr')"
[ ! -d "$LOCK" ] && ok "the slot's lock is gone after the gate" || bad "the slot's lock is gone after the gate"
hm-gate --log "$LOG" -- only true; assert_status "all green is exit 0" $? 0
assert_eq "a rerun leaves no line of the earlier run" "$(steps "$LOG")" "only exit 0"
[ ! -e "$LOG.d/b.log" ] && ok "a rerun leaves no step log of the earlier run" || bad "a rerun leaves no step log of the earlier run"
hm-gate --log "$LOG" -- s 'hm-slot status'; assert_contains "the gate holds the slot under its label" "$(cat "$LOG.d/s.log")" '"label":"gate"'
echo stray > stray; hm-gate --log "$LOG" -- d true
assert_eq "a dirty tree is recorded" "$(head -1 "$LOG")" "# hm-gate steps: d head=$head_now dirty=1"
rm stray
# the gate's own log in the tree: a second run is not made dirty by the first run's log and step logs
mkdir -p sub; for run in 1 2; do (cd sub && hm-gate --log ../gate.log -- e true); done
assert_eq "a log in the tree does not make the next run dirty" "$(head -1 gate.log)" "# hm-gate steps: e head=$head_now dirty=0"
hm-gate-verify log gate.log --commit HEAD >/dev/null; assert_status "and its second run vouches for the commit" $? 0
echo stray > stray; (cd sub && hm-gate --log ../gate.log -- e true)
assert_eq "a change outside the log is still dirty, from a subdirectory too" "$(head -1 gate.log)" "# hm-gate steps: e head=$head_now dirty=1"
rm -rf stray gate.log gate.log.d sub
# a tracked file as the log, or as its step-log directory, is refused before the slot and left as it was
echo edited >> README; before=$(cat README)
hm-gate --log README -- a "touch '$T_TMP/tracked-ran'" 2>/dev/null; assert_status "a tracked file as --log is refused" $? 64
assert_eq "and the tracked file is untouched" "$(cat README)" "$before"
mkdir -p g.log.d; echo kept > g.log.d/f; git add g.log.d/f; git commit -qm "test: a tracked step-log dir"
hm-gate --log g.log -- a "touch '$T_TMP/tracked-ran'" 2>/dev/null; assert_status "a tracked <log>.d is refused" $? 64
assert_eq "and its files are untouched" "$(cat g.log.d/f)" "kept"
[ ! -e "$T_TMP/tracked-ran" ] && [ ! -d "$LOCK" ] && ok "and nothing ran, nor took the slot" || bad "and nothing ran, nor took the slot"
git reset -q --hard "$head_now"; rm -rf g.log.d g.log
# every argument is checked before anything runs: a first step that touches a file must not have run
T="touch '$T_TMP/touched'"
for args in "-- first \"$T\" a" "-- first \"$T\" ../x true" "-- first \"$T\" a..b true" "-- first \"$T\" 'a b' true" "-- first \"$T\" a true a true" "--" "first \"$T\""; do
  rm -f "$T_TMP/touched"
  eval "hm-gate --log \"$LOG\" $args 2>/dev/null"; s=$?
  label=${args//"$T_TMP"/T}
  assert_status "refused: $label" $s 64
  [ ! -e "$T_TMP/touched" ] && ok "nothing ran: $label" || bad "nothing ran: $label"
done
hm-gate --log "$LOG" -- unit.tests true lint-all true; assert_status "a step name may hold '.' and '-'" $? 0
assert_eq "and verifies by its header" "$(hm-gate-verify log "$LOG" --expect unit.tests --commit HEAD)" "GREEN (2 steps)"
# a step name is ASCII under any locale, at every reader: hm-gate's steps, a log's header and lines, an expected name
for loc in C en_US.UTF-8; do
  for n in é Aé ß ｈ; do
    (export LC_ALL=$loc; hm-gate --log "$T_TMP/loc.log" -- "$n" true 2>/dev/null); assert_status "a step [$n] is refused under $loc" $? 64
    printf '# hm-gate steps: %s head=%s dirty=0\n%s exit 0\n' "$n" "$head_now" "$n" > "$T_TMP/loc.log"
    (export LC_ALL=$loc; hm-gate-verify log "$T_TMP/loc.log" >/dev/null 2>&1); assert_status "a log naming step [$n] is red under $loc" $? 1
    (export LC_ALL=$loc; hm-gate-verify log "$T_TMP/loc.log" --expect "$n" >/dev/null 2>&1); assert_status "an expected [$n] is refused under $loc" $? 64
  done
done
rm -f "$T_TMP/loc.log"
hm-gate -- x true 2>/dev/null; assert_status "no --log is a usage error" $? 64
rm -f "$T_TMP/touched"; hm-gate --log "$T_TMP/no/such/dir/g.log" -- first "$T" 2>/dev/null; assert_status "a log that cannot be written is refused before the slot" $? 64
[ ! -e "$T_TMP/touched" ] && [ ! -d "$LOCK" ] && ok "and nothing ran" || bad "and nothing ran"
# a busy slot: nothing runs and no log is written
sleep 30 & holder=$!; hm-slot acquire other --pid $holder
rm -f "$LOG"; hm-gate --log "$LOG" -- t "touch '$T_TMP/busy-ran'" 2>/dev/null; assert_status "a busy slot is exit 75" $? 75
[ ! -e "$T_TMP/busy-ran" ] && [ ! -e "$LOG" ] && ok "a busy slot runs nothing and writes no log" || bad "a busy slot runs nothing and writes no log"
hm-slot release --pid $holder; kill $holder; wait $holder 2>/dev/null
# an interrupted gate stops now, with the step's own children, writes no line for that step, and frees the slot
# The step's sleep has a length no other process has, matched as a whole command line, so nothing else is mistaken for it.
NAP="31.$$"
for sig in TERM:143 HUP:129; do
  name=${sig%%:*}; want=${sig##*:}
  hm-gate --log "$LOG" -- done true slow "true; sleep $NAP" never true 2>/dev/null & g=$!; sleep 2
  t0=$SECONDS; kill -$name $g; wait $g; assert_status "a $name stops the gate with $want" $? $want
  [ $((SECONDS - t0)) -lt 5 ] && ok "$name: at once, not when the step ends" || bad "$name: at once, not when the step ends: $((SECONDS - t0)) s"
  sleep 0.5; pgrep -f "^sleep $NAP\$" >/dev/null && bad "$name: the step's own process is gone" || ok "$name: the step's own process is gone"
  assert_eq "$name: no line for the step it stopped, none after" "$(steps "$LOG")" "done exit 0"
  [ ! -d "$LOCK" ] && ok "$name: the slot's lock is gone" || bad "$name: the slot's lock is gone"
  out=$(hm-gate-verify log "$LOG" 2>&1); assert_status "$name: the stopped gate verifies RED with no --expect" $? 1
  assert_contains "$name: naming the steps that never wrote a line" "$out" "missing: slow never"
done

# ---- hm-gate-verify log --------------------------------------------------------------------------------------------
H="# hm-gate steps: a,b head=$head_now dirty=0"
printf '%s\na exit 0\nb exit 0\n' "$H" > "$T_TMP/g.log"
out=$(hm-gate-verify log "$T_TMP/g.log"); assert_status "green log" $? 0; assert_eq "green says its step count" "$out" "GREEN (2 steps)"
hm-gate --log "$LOG" -- a true b false c true >/dev/null 2>&1
out=$(hm-gate-verify log "$LOG" 2>&1); assert_status "a red step is red" $? 1; assert_contains "red names the failing step" "$out" "b exit 1"
printf '%s\n' "$H" > "$T_TMP/none.log"
out=$(hm-gate-verify log "$T_TMP/none.log" 2>&1); assert_status "no step lines is red" $? 1; assert_contains "and says so" "$out" "no steps"
: > "$T_TMP/empty.log"; hm-gate-verify log "$T_TMP/empty.log" >/dev/null 2>&1; assert_status "an empty log is red" $? 1
hm-gate-verify log "$T_TMP/missing.log" >/dev/null 2>&1; assert_status "a missing log is red" $? 1
printf 'a exit 0\nb exit 0\n' > "$T_TMP/script.log"   # a project's own gate script writes no header
out=$(hm-gate-verify log "$T_TMP/script.log" 2>&1); assert_status "a log with no header and no --expect is red" $? 1; assert_contains "and says to name the steps" "$out" "--expect"
hm-gate-verify log "$T_TMP/script.log" --expect a,b >/dev/null; assert_status "with --expect it is read" $? 0
out=$(hm-gate-verify log "$T_TMP/script.log" --expect a,z 2>&1); assert_status "a missing expected step is red" $? 1; assert_contains "and is named" "$out" "z"
hm-gate-verify log "$T_TMP/g.log" --expect 'a,.*' >/dev/null 2>&1; assert_status "an expected name is a step name" $? 64
printf '%s\na exit 0\na exit 0\nb exit 0\n' "$H" > "$T_TMP/twice.log"
out=$(hm-gate-verify log "$T_TMP/twice.log" 2>&1); assert_status "a step written twice is red" $? 1; assert_contains "and is named" "$out" "twice: a"
printf '%s\na exit 0\n  b exit 1\nb exit 1 later\nb exit 0\n' "$H" > "$T_TMP/loose.log"
assert_eq "only whole step lines count" "$(hm-gate-verify log "$T_TMP/loose.log")" "GREEN (2 steps)"
# --commit: a log vouches only for the commit it ran on, with a clean tree
hm-gate-verify log "$T_TMP/g.log" --commit HEAD >/dev/null; assert_status "the commit the gate ran on" $? 0
hm-gate-verify log "$T_TMP/g.log" --commit "$(git rev-parse --short HEAD)" >/dev/null; assert_status "named by a short hash" $? 0
git commit -q --allow-empty -m "chore: move on"
out=$(hm-gate-verify log "$T_TMP/g.log" --commit HEAD 2>&1); assert_status "a log of an earlier commit is red" $? 1; assert_contains "and says which" "$out" "$head_now"
printf '# hm-gate steps: a head=%s dirty=1\na exit 0\n' "$head_now" > "$T_TMP/dirty.log"
out=$(hm-gate-verify log "$T_TMP/dirty.log" --commit "$head_now" 2>&1); assert_status "a gate on a dirty tree vouches for no commit" $? 1; assert_contains "and says so" "$out" "dirty"
hm-gate-verify log "$T_TMP/script.log" --expect a,b --commit HEAD >/dev/null 2>&1; assert_status "--commit needs a header" $? 1
hm-gate-verify log "$T_TMP/g.log" --commit nope >/dev/null 2>&1; assert_status "an unknown commit is refused" $? 4
git reset -q --hard "$head_now"

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
for trailer in 'co-authored-by: x' 'Co-authored-by : x' 'Claude-Session: abc' 'Generated with [Claude Code](https://claude.com/claude-code)' 'Generated with Claude Code'; do
  git reset -q --hard "$good"; c "$(printf 'fix: a fix\n\n%s' "$trailer")" f2
  hm-gate-verify commits "$good..HEAD" $COMMON >/dev/null 2>&1; assert_status "deny refuses: $trailer" $? 1
done
git reset -q --hard "$good"; c "fix: six files" g1 g2 g3 g4 g5 g6
out=$(hm-gate-verify commits "$good..HEAD" $COMMON 2>&1); assert_status "a 6-file commit fails --max-files 5" $? 1; assert_contains "named as files" "$out" "files"
# a merge's own file count is not counted; its subject and the merged commits are checked in the same range
git reset -q --hard "$good"; git checkout -q -b side
for k in 1 2 3 4 5 6 7 8; do c "feat: part $k" m${k}a m${k}b m${k}c m${k}d m${k}e; done
git checkout -q -; git merge -q --no-ff -m "chore(join): merge side" side
assert_eq "the merge brings in 40 files" "$(git diff --name-only "$good" HEAD | grep -c .)" "40"
out=$(hm-gate-verify commits "$good..HEAD" $COMMON 2>&1); assert_status "a merge of 40 files passes --max-files 5" $? 0
assert_eq "and every commit in the range is checked" "$out" "OK (9 commits)"
git reset -q --hard "$good"; git merge -q --no-ff -m "merge side" side
hm-gate-verify commits "$good..HEAD" $COMMON >/dev/null 2>&1; assert_status "a merge's free subject still fails conventional" $? 1
git reset -q --hard "$good"; git checkout -q side; c "fix: six files" s1 s2 s3 s4 s5 s6; git checkout -q -
git merge -q --no-ff -m "chore(join): merge side" side
out=$(hm-gate-verify commits "$good..HEAD" $COMMON 2>&1); assert_status "a merged branch's own 6-file commit still fails" $? 1
assert_contains "named as files" "$out" "files: 6"
git reset -q --hard "$good"; git merge -q --no-ff --no-commit side >/dev/null 2>&1; for k in 1 2 3 4 5 6; do echo "$k" > own$k; done
git add -A; git commit -qm "chore(join): merge side"
out=$(hm-gate-verify commits "$good..HEAD" $COMMON 2>&1); assert_status "a merge carrying 6 files of its own fails --max-files 5" $? 1
assert_contains "the merge itself is named, by its own 6 files" "$out" "$(git rev-parse --short HEAD) files: 6"
# a merge that undoes 6 of the side's files counts them: --cc saw nothing there
git reset -q --hard "$good"; git branch -q -D side; git checkout -q -b side
c "feat: six on the side" u1 u2 u3 u4 u5 u6; git checkout -q -
git merge -q --no-ff --no-commit side >/dev/null 2>&1; git checkout -q "$good" -- . 2>/dev/null; rm -f u1 u2 u3 u4 u5 u6
git add -A; git commit -qm "chore(join): merge side"
out=$(hm-gate-verify commits "$good..HEAD" $COMMON 2>&1); assert_status "a merge that undoes 6 of the side's files fails" $? 1
assert_contains "the merge itself is named, by the 6 it undid" "$out" "$(git rev-parse --short HEAD) files: 6"
# both sides edit the same 6 files, cleanly: git's own merge, nothing of the merge's own (--cc counted all 6)
git reset -q --hard "$good"; git branch -q -D side
for k in 1 2 3 4 5 6; do printf 'a\nb\nc\nd\ne\n' > both$k; done; c "feat: six shared files"; shared=$(git rev-parse HEAD)
git checkout -q -b side   # each side's edits in two commits of 3, so only the merge is judged on 6
for half in "1 2 3" "4 5 6"; do for k in $half; do printf 'A\nb\nc\nd\ne\n' > both$k; done; git commit -qam "feat: the side's first lines"; done
git checkout -q -
for half in "1 2 3" "4 5 6"; do for k in $half; do printf 'a\nb\nc\nd\nE\n' > both$k; done; git commit -qam "feat: our last lines"; done
git merge -q --no-ff -m "chore(join): merge side" side >/dev/null 2>&1
assert_eq "both sides' edits are in the merge" "$(cat both6)" "$(printf 'A\nb\nc\nd\nE')"
assert_eq "and --cc would count all 6" "$(git diff-tree -r --cc --no-commit-id --name-only HEAD | grep -c .)" "6"
out=$(hm-gate-verify commits "$shared..HEAD" $COMMON 2>&1); assert_status "a clean merge where both sides edit 6 files passes" $? 0
assert_eq "with every commit checked" "$out" "OK (5 commits)"
# 6 conflicts resolved by taking our side: the resolutions are the merge's own (--cc saw none of them)
git reset -q --hard "$shared"; git branch -q -D side; git checkout -q -b side
for half in "1 2 3" "4 5 6"; do for k in $half; do echo theirs > both$k; done; git commit -qam "feat: theirs"; done
git checkout -q -
for half in "1 2 3" "4 5 6"; do for k in $half; do echo ours > both$k; done; git commit -qam "feat: ours"; done
git merge -q --no-ff side >/dev/null 2>&1; git checkout -q --ours -- both1 both2 both3 both4 both5 both6
git add -A; git commit -qm "chore(join): merge side"
assert_eq "--cc counts no resolution taken whole from one side" "$(git diff-tree -r --cc --no-commit-id --name-only HEAD | grep -c .)" "0"
out=$(hm-gate-verify commits "$shared..HEAD" $COMMON 2>&1); assert_status "a merge resolving 6 conflicts by hand fails" $? 1
assert_contains "the merge itself is named, by its 6 resolutions" "$out" "$(git rev-parse --short HEAD) files: 6"
git reset -q --hard "$good"; git branch -q -D side
git reset -q --hard "$good"; c "update stuff" f3
hm-gate-verify commits "$good..HEAD" $COMMON >/dev/null 2>&1; assert_status "a free subject fails conventional" $? 1
hm-gate-verify commits "$good..HEAD" --max-files 5 --style free --attribution deny >/dev/null 2>&1; assert_status "and passes free" $? 0
for loc in C en_US.UTF-8; do   # a scope is lower-case ASCII under any locale
  git reset -q --hard "$good"; c "fix(gaté): a scope with é" f5
  (export LC_ALL=$loc; hm-gate-verify commits "$good..HEAD" $COMMON >/dev/null 2>&1); assert_status "a non-ASCII scope fails conventional under $loc" $? 1
  git reset -q --hard "$good"; c "fix(Gate): a capital scope" f5
  (export LC_ALL=$loc; hm-gate-verify commits "$good..HEAD" $COMMON >/dev/null 2>&1); assert_status "a capital scope fails conventional under $loc" $? 1
done
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
