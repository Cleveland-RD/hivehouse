#!/usr/bin/env bash
# R1, the three guards (bin/guard/rm, find, rsync): a call with any protected operand is refused whole, nothing is deleted; any other call goes
# to the real tool unchanged. Every case runs against a fake root (HH_GUARD_ROOT) with a stub in place of the real tool (HH_GUARD_REAL) that only
# records its arguments, and before each run the test checks that every operand lies inside the scratch folder. Real deletion is tested once, on
# a file the test made.
. "$(dirname "$0")/lib.sh"
t_setup
R="$T_TMP/root"; FH="$R/Users/me/dias"; PL="$R/srv/a/tools/plug"; G="$PL/bin/guard"
mkdir -p "$FH/.claude" "$FH/proj/.git" "$FH/proj/src" "$FH/host:/.git" "$FH/plain/sub/deep" "$FH/wt" "$FH/hubdir/$T_HUB" "$FH/src" "$R/private/tmp/x" "$R/private/tmp/repo/.git" \
  "$R/private/var/folders/ab/T/z" "$R/home/other" "$PL/bin/guard" "$R/Users/other"
cp "$HH_REPO_ROOT/bin/hh-lib.sh" "$PL/bin/hh-lib.sh"; cp "$HH_REPO_ROOT"/bin/guard/* "$G/"
echo "gitdir: elsewhere" > "$FH/wt/.git"; ln -s "$FH/proj" "$FH/proj-link"; : > "$FH/plain/file"; : > "$FH/plain/sub/deep/f"
STUB="$T_TMP/stub"; STUBLOG="$T_TMP/stub.log"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s"\n' "$STUBLOG" > "$STUB"; chmod +x "$STUB"
export HOME="$FH" HH_GUARD_ROOT="$R" HH_GUARD_REAL="$STUB"
assert_eq "the real tool is the stub (a test that would reach a real rm fails instead of running)" "$HH_GUARD_REAL" "$T_TMP/stub"

inside() { local a; for a in "$@"; do case "$a" in /bin/rm|"$T_TMP"/*) ;; /*) return 1 ;; esac; done; }   # every absolute word lies in the scratch (/bin/rm only names a command inside -exec)
run() {  # run <guard> <args>...: ERR and RC; STUBLOG shows whether the stub was reached
  rm -f "$STUBLOG"; inside "${@:2}" || { bad "not run: an operand outside the scratch folder: $*"; RC=99; return 1; }
  ERR=$(cd "${RUNCWD:-$FH}" && "$G/$1" "${@:2}" 2>&1 >/dev/null); RC=$?
}
refused() {  # refused <label> <guard> <args>...
  local l="$1"; shift; run "$@" || return
  if [ "$RC" -eq 1 ] && [ ! -e "$STUBLOG" ] && case "$ERR" in *"nothing was deleted"*) true ;; *) false ;; esac; then ok "$l"; else bad "$l: exit $RC, stub $([ -e "$STUBLOG" ] && echo reached || echo not reached) [$ERR]"; fi
}
allowed() {  # allowed <label> <guard> <args>...: reaches the stub with the arguments unchanged
  local l="$1" g="$2"; shift 2; run "$g" "$@" || return
  if [ "$RC" -eq 0 ] && [ "$(cat "$STUBLOG" 2>/dev/null)" = "$(printf '%s\n' "$@")" ]; then ok "$l"; else bad "$l: exit $RC [$ERR] stub got [$(cat "$STUBLOG" 2>/dev/null)]"; fi
}

echo "-- the table: each tool x each target"
EMPTY=""; shopt -s nullglob
targets=("fake /|$R/$EMPTY" "depth 1|$R/Users" "depth 2|$R/Users/me" "the home|$FH" "repo root|$FH/proj" "hub folder|$FH/hubdir" "plugin root|$PL" "empty operand|" "glob of /Users/*|GLOB")
for t in "${targets[@]}"; do
  name=${t%%|*}; op=${t#*|}
  if [ "$op" = GLOB ]; then ops=("$R"/Users/*); else ops=("$op"); fi
  refused "rm refuses $name" rm "${ops[@]}"
  refused "rm -r refuses $name" rm -r "${ops[@]}"
  refused "rm -rf refuses $name" rm -rf "${ops[@]}"
  refused "find -delete refuses $name" find "${ops[@]}" -name x -delete
  refused "find -exec rm refuses $name" find "${ops[@]}" -type f -exec rm -rf {} +
  refused "rsync --delete refuses $name" rsync -a --delete "$FH/src/" "${ops[@]}"
done
for t in "ok file|$FH/plain/file" "ok depth-4 dir|$FH/plain/sub/deep" "linked worktree|$FH/wt" "inside /private/tmp|$R/private/tmp/x" "a repo inside /private/tmp|$R/private/tmp/repo" "inside TMPDIR|$R/private/var/folders/ab/T/z"; do
  name=${t%%|*}; op=${t#*|}; [ "$name" != "inside TMPDIR" ] || export TMPDIR="$R/private/var/folders/ab/T"
  allowed "rm passes $name" rm "$op"
  allowed "rm -rf passes $name" rm -rf "$op"
  allowed "find -delete passes $name" find "$op" -name x -delete
  allowed "find -exec rm passes $name" find "$op" -type f -exec rm -rf {} +
  allowed "rsync --delete passes $name" rsync -a --delete "$FH/src/" "$op"
done
unset TMPDIR

echo "-- the whole call, and what is not judged"
refused "one protected operand among good ones refuses the whole call" rm "$FH/plain/file" "$FH/proj" "$FH/plain/sub/deep"
refused "...with its option first and -- before the operands" rm -rf -- "$FH/plain/file" "$FH/proj"
refused "...a link to a repository, ending in /, follows the link" rm -r "$FH/plain/file" "$FH/proj-link/"
allowed "...but the same link without the / is judged as itself" rm "$FH/proj-link"
allowed "options and -- are not operands" rm -rf -- "$FH/plain/file"
allowed "rm with no operand goes through" rm -f
allowed "find without -delete or -exec rm is not judged, even from a repository root" find "$FH/proj" -name x -print
allowed "find -exec of another command is not judged" find "$FH/proj" -name x -exec ls {} +
refused "find -exec by a path to rm is judged" find "$FH/proj" -exec /bin/rm -r {} +
RUNCWD="$FH/proj" refused "find with no starting point deletes in the current folder (a repository root)" find -name x -delete
RUNCWD="$FH/plain" allowed "...and passes from a plain folder" find -name x -delete
allowed "rsync without --delete is not judged" rsync -a "$FH/src/" "$FH/proj/"
allowed "rsync --delete to a remote destination is not judged" rsync -a --delete "$FH/src/" "host:backup/"
allowed "...even when a local folder is named like the host (host: is a repository here)" rsync -a --delete "$FH/src/" "host:"
allowed "...nor an rsync:// one" rsync -a --delete "$FH/src/" "rsync://host/module/"
refused "rsync --delete with an option after the destination still judges the destination" rsync -a --delete "$FH/plain/" "$FH/proj" --exclude "$FH/src"
allowed "rsync --delete from a repository, to a plain folder" rsync -a --delete "$FH/proj/" "$FH/plain/sub/deep/"
refused "rsync --delete-after is judged too" rsync -a --delete-after "$FH/src/" "$FH/proj"
echo "-- real deletion, once, on files the test made"
unset HH_GUARD_ROOT HH_GUARD_REAL; mkdir -p "$T_TMP/real"; : > "$T_TMP/real/f1"; : > "$T_TMP/real/f2"
( cd "$T_TMP/real" && "$G/rm" "$T_TMP/real/f1" ); assert_status "rm through the guard deletes a file in the scratch" $? 0
[ ! -e "$T_TMP/real/f1" ] && ok "...and the file is gone" || bad "...the file is still there"
( cd "$T_TMP/real" && "$G/find" "$T_TMP/real" -name f2 -delete ); assert_status "find -delete through the guard deletes a file in the scratch" $? 0
[ ! -e "$T_TMP/real/f2" ] && ok "...and the file is gone" || bad "...the file is still there"
echo "-- more than one copy of the guard on PATH"
# a plugin update, a worktree or an export copy puts a second guard folder on PATH beside the first: each must pass over every guard folder
# and reach the real tool once. The real rm here is a stub on PATH after both; each run has a time limit, so a regression fails instead of hanging.
mkcopy() {  # mkcopy <dir> [nomark]: a plugin copy with bin/hh-lib.sh and bin/guard
  mkdir -p "$1/bin/guard"; cp "$HH_REPO_ROOT/bin/hh-lib.sh" "$1/bin/"; cp "$HH_REPO_ROOT"/bin/guard/rm "$HH_REPO_ROOT"/bin/guard/find "$HH_REPO_ROOT"/bin/guard/rsync "$1/bin/guard/"
  [ "${2:-}" = nomark ] || cp "$HH_REPO_ROOT/bin/guard/.hh-guard" "$1/bin/guard/"
}
run_to() {  # run_to <seconds> <PATH> <command>...: RC (124 when it ran past the limit and was killed) and ERR; the seam for the real tool is off
  local secs="$1" pth="$2" pid i; shift 2
  ( cd "$FH" && PATH="$pth" exec env -u HH_GUARD_REAL "$@" ) > /dev/null 2> "$T_TMP/rt.err" & pid=$!; t_track "$pid"
  for ((i = 0; i < secs * 10; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; RC=124; else wait "$pid"; RC=$?; fi
  ERR=$(cat "$T_TMP/rt.err")
}
CA="$R/srv/c/plugA"; CB="$R/srv/c/plugB"; mkcopy "$CA"; mkcopy "$CB"
REALBIN="$T_TMP/realbin"; REALLOG="$T_TMP/real.log"; mkdir -p "$REALBIN"
printf '#!/bin/sh\nprintf "CALLED %%s\\n" "$*" >> "%s"\n' "$REALLOG" > "$REALBIN/rm"; chmod +x "$REALBIN/rm"
for order in "A then B|$CA|$CB" "B then A|$CB|$CA"; do
  name=${order%%|*}; rest=${order#*|}; first=${rest%%|*}; second=${rest#*|}
  P="$first/bin/guard:$second/bin/guard:$REALBIN:/usr/bin:/bin"; rm -f "$REALLOG"
  run_to 10 "$P" rm "$FH/plain/file"
  assert_eq "two guards on PATH ($name): the call ends (no hang), exit 0" "$RC" "0"
  assert_eq "...and reaches the real rm once, with its operand" "$(cat "$REALLOG" 2>/dev/null)" "CALLED $FH/plain/file"
  rm -f "$REALLOG"; run_to 10 "$P" rm -rf "$FH/proj"
  assert_eq "...a protected operand is still refused: exit 1" "$RC" "1"
  [ ! -e "$REALLOG" ] && ok "...and the real rm is not reached" || bad "the real rm was reached for a protected operand"
done
# copies without the marker (an older guard) cannot be passed over by name: the loop stop ends the call, in an error, within the limit
for d in "$R/srv/c/oA" "$R/srv/c/oB"; do mkcopy "$d" nomark; done
[ ! -e "$R/srv/c/oA/bin/guard/.hh-guard" ] && [ ! -e "$R/srv/c/oB/bin/guard/.hh-guard" ] && ok "the old copies hold no marker" || bad "the old copies hold a marker"
rm -f "$REALLOG"; run_to 20 "$R/srv/c/oA/bin/guard:$R/srv/c/oB/bin/guard:$REALBIN:/usr/bin:/bin" rm "$FH/plain/file"
assert_eq "two guards that cannot pass each other over: the loop stop ends it (exit 2), no hang" "$RC" "2"
assert_contains "...saying more than one guard is on PATH" "$ERR" "more than one copy of bin/guard is on PATH"
[ ! -e "$REALLOG" ] && ok "...and nothing was run" || bad "the real rm ran"
for t in find rsync; do
  run_to 20 "$R/srv/c/oA/bin/guard:$R/srv/c/oB/bin/guard:/usr/bin:/bin" "$t" "$FH/src" -name x
  assert_eq "$t: the same loop stop (exit 2)" "$RC" "2"
done
# a real find runs rm by name (-exec rm): the guard of rm is not in a loop, so it is not stopped by find's own count
rm -f "$REALLOG"; run_to 20 "$CA/bin/guard:$CB/bin/guard:$REALBIN:/usr/bin:/bin" find "$FH/plain/sub/deep" -type f -exec rm {} +
assert_eq "find -exec rm under the guards: the call ends, exit 0" "$RC" "0"
assert_contains "...and the guard of rm handed it on (the real rm was reached)" "$(cat "$REALLOG" 2>/dev/null)" "CALLED $FH/plain/sub/deep/f"
# a guard with no real tool beyond it ends in an error; made with a tool name that has no real program, so that PATH can keep /usr/bin
for d in "$R/srv/c/nA" "$R/srv/c/nB"; do mkcopy "$d"; sed -i.bak -e 's/hh_guard_real rm/hh_guard_real hhnotool/' -e 's/hh_guard_judge rm/hh_guard_judge hhnotool/' "$d/bin/guard/rm"; mv "$d/bin/guard/rm" "$d/bin/guard/hhnotool"; rm -f "$d/bin/guard/rm.bak"; done
run_to 10 "$R/srv/c/nA/bin/guard:$R/srv/c/nB/bin/guard:/usr/bin:/bin" hhnotool "$FH/plain/file"
assert_eq "two guards and no real program: it ends in an error (127), not a hang" "$RC" "127"
assert_contains "...saying there is no real tool beyond the guard" "$ERR" "is not on PATH beyond the guard"

echo "-- the page"
doc=$(tr '\n' ' ' < "$HH_REPO_ROOT/docs/rm-guard.md" | sed 's/  */ /g')
assert_contains "README links the guard's page" "$(cat "$HH_REPO_ROOT/README.md")" "(docs/rm-guard.md)"
for w in "a git repository root" "synced cloud folder" "There is no switch" "What it does not stop" "HH_GUARD_ROOT" "bin/hh-guard-env"; do
  case "$w" in "There is no switch") w="No switch" ;; esac
  assert_contains "docs/rm-guard.md covers: $w" "$doc" "$w"
done
cd /; t_teardown; t_done
