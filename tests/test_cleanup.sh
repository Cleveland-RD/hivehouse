#!/usr/bin/env bash
# It stops real processes, so it runs only when the owner asks, however it is started (tests/run.sh skips it too).
[ "${HH_CLEANUP_TEST:-}" = 1 ] || { echo "SKIP test_cleanup.sh (run by the owner: HH_CLEANUP_TEST=1)"; exit 0; }
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup   # every process below is recorded with t_track as it starts, so teardown reaps it whatever ends the run
case "$T_TMP" in /tmp/*|/private/tmp/*)   # then everything below would count as temporary, and the checks mean nothing
  bad "TMPDIR is under /tmp ($T_TMP): run with TMPDIR set elsewhere, e.g. TMPDIR=\$(getconf DARWIN_USER_TEMP_DIR)"; t_done ;;
esac
alive() { kill -0 "$1" 2>/dev/null; }
count() { hh-manifest list ${1:+--kind "$1"} | wc -l | tr -d ' '; }
# A temporary place of the test's own, so that the rest of $T_TMP (which sits under the real $TMPDIR) is not temporary
mkdir -p "$T_TMP/tmpd" "$T_TMP/out"; export TMPDIR="$T_TMP/tmpd"

# ---- usage and A1 --------------------------------------------------------------------------------------------------
hh-cleanup 2>/dev/null; assert_status "a mode is required" $? 64
hh-cleanup --disk --finish 2>/dev/null; assert_status "one mode only" $? 64
hh-cleanup --finish --bogus 2>/dev/null; assert_status "an unknown flag is a usage error" $? 64
mkdir "$T_TMP/norepo"; (cd "$T_TMP/norepo" && hh-cleanup --finish 2>/dev/null); assert_status "outside a repo: exit 2" $? 2
[ ! -e "$T_TMP/norepo/$T_STATE" ] && [ -z "$(find "$HIVEHOUSE_HOME" -type f)" ] && ok "outside a repo: nothing written" || bad "outside a repo: something was written"

# ---- files and directories -----------------------------------------------------------------------------------------
r=$(t_repo files); cd "$r" || exit 2
mkdir -p "$TMPDIR/scratch/deep" "$r/$T_STATE/tmp"; echo x > "$TMPDIR/scratch/deep/f"; echo x > "$r/$T_STATE/tmp/t"
realtmp=$(t_outside_tmp)
mkdir "$T_TMP/out/keep"; echo x > "$T_TMP/out/keep/f"
mkdir "$T_TMP/out/unlisted"; echo x > "$T_TMP/out/unlisted/f"
hh-manifest add dir path="$TMPDIR/scratch" >/dev/null
hh-manifest add file path="$r/$T_STATE/tmp/t" >/dev/null
hh-manifest add dir path="$realtmp" >/dev/null
hh-manifest add dir path="$T_TMP/out/keep" >/dev/null
hh-manifest add dir path="$T_TMP/out/gone" >/dev/null   # never created
before=$(cat $T_STATE/manifest.jsonl)
out=$(hh-cleanup --disk --dry-run); assert_status "dry run" $? 0
[ -d "$TMPDIR/scratch" ] && [ -d "$realtmp" ] && [ -f "$r/$T_STATE/tmp/t" ] && ok "dry run deletes nothing" || bad "dry run deleted something"
assert_eq "dry run leaves the manifest as it was" "$(cat $T_STATE/manifest.jsonl)" "$before"
assert_contains "dry run says so" "$out" "dry run"
out=$(hh-cleanup --disk); assert_status "--disk" $? 0
[ ! -e "$TMPDIR/scratch" ] && ok "--disk deletes a dir under TMPDIR" || bad "--disk left a dir under TMPDIR"
[ ! -e "$realtmp" ] && ok "--disk deletes a dir under /tmp" || bad "--disk left a dir under /tmp"
[ ! -e "$r/$T_STATE/tmp/t" ] && ok "--disk deletes a file under $T_STATE/tmp" || bad "--disk left $T_STATE/tmp"
[ -f "$T_TMP/out/keep/f" ] && ok "--disk keeps a dir that is not temporary" || bad "--disk touched a dir that is not temporary"
[ -f "$T_TMP/out/unlisted/f" ] && ok "--disk leaves a dir not on the manifest" || bad "--disk touched a dir not on the manifest"
assert_contains "the line for a deleted dir" "$out" "removed dir $TMPDIR/scratch by=owner (temporary)"
assert_contains "the line for a kept dir" "$out" "kept dir $T_TMP/out/keep by=owner"
assert_contains "a path that is already gone is dropped" "$out" "removed dir $T_TMP/out/gone by=owner (already gone)"
assert_contains "free disk before" "$out" "free disk before:"
assert_contains "free disk after" "$out" "free disk after:"
assert_eq "removed entries are dropped, the kept one stays" "$(hh-manifest list | jq -r .path)" "$T_TMP/out/keep"
out=$(hh-cleanup --finish); assert_status "--finish" $? 0
[ ! -e "$T_TMP/out/keep" ] && ok "--finish moves a dir that is not temporary away" || bad "--finish left it in place"
trashed=$(find "$r/$T_STATE/trash" -name f -path '*keep*' | head -1)
[ -n "$trashed" ] && [ "$(cat "$trashed")" = x ] && ok "...into the trash, contents intact" || bad "the trashed dir is not in $T_STATE/trash"
assert_contains "the trashed line" "$out" "trashed dir $T_TMP/out/keep by=owner"
assert_contains "the trash size is reported" "$out" "trash:"
[ -f "$T_TMP/out/unlisted/f" ] && ok "--finish leaves a dir not on the manifest" || bad "--finish touched a dir not on the manifest"
assert_eq "the manifest is empty" "$(count)" "0"

# ---- A5 judged again at cleanup, A18 judged again -------------------------------------------------------------------
mkdir "$T_TMP/out/sw" "$T_TMP/victim"; echo v > "$T_TMP/victim/f"
hh-manifest add dir path="$T_TMP/out/sw" >/dev/null
rm -rf "$T_TMP/out/sw"; ln -s "$T_TMP/victim" "$T_TMP/out/sw"
mkdir -p "$T_TMP/out/p" "$T_TMP/victim2"; echo v > "$T_TMP/out/p/f"; echo v > "$T_TMP/victim2/f"
hh-manifest add file path="$T_TMP/out/p/f" >/dev/null
rm -rf "$T_TMP/out/p"; ln -s "$T_TMP/victim2" "$T_TMP/out/p"
printf '%s\n' '{"id":"m-etc","kind":"file","path":"/private/etc/hosts","at":"x","by":"test"}' >> $T_STATE/manifest.jsonl
mkdir -p "$T_TMP/out/later/sub"; echo v > "$T_TMP/out/later/sub/f"
hh-manifest add dir path="$T_TMP/out/later/sub" >/dev/null
hh-manifest add worktree path="$T_TMP/out/later" base=main >/dev/null
out=$(hh-cleanup --finish); assert_status "--finish with unsafe entries" $? 0
[ -f "$T_TMP/victim/f" ] && ok "a dir swapped for a symlink after it was recorded: the target survives" || bad "followed a symlink swapped in after the add"
assert_contains "...and is skipped" "$out" "skipped dir $T_TMP/out/sw"
[ -f "$T_TMP/victim2/f" ] && ok "a parent swapped for a symlink: the file it now resolves to survives" || bad "acted through a parent swapped for a symlink"
assert_contains "...and is skipped as resolving elsewhere" "$out" "skipped file $T_TMP/out/p/f"
[ -f /private/etc/hosts ] && ok "a file not owned by the caller is left alone" || bad "/etc/hosts is gone"
assert_contains "...and skipped as not owned" "$out" "skipped file /private/etc/hosts by=test (refused: /private/etc/hosts is not owned by the caller)"
[ -f "$T_TMP/out/later/sub/f" ] && ok "a dir inside a worktree recorded after it is left alone (A18)" || bad "removed a dir inside a recorded worktree"
assert_contains "...and skipped as inside the worktree" "$out" "skipped dir $T_TMP/out/later/sub"
assert_contains "a recorded path that is not a git worktree is kept" "$out" "kept worktree $T_TMP/out/later by=owner (not a worktree of $r)"
cd /

# ---- processes -----------------------------------------------------------------------------------------------------
# All of it runs in one parent group, P (a subshell started under set -m), the cleanup included: P is the cleanup's own
# group, so a group guard that failed could reach nothing outside it. P reaps what it started when it ends; teardown
# kills each recorded group while its leader is still the one recorded, then every recorded pid.
r=$(t_repo procs); cd "$r" || exit 2
set -m
(
  from=1; [ -f "$T_TMP/run.ledger" ] && from=$(( $(wc -l < "$T_TMP/run.ledger") + 1 ))
  trap 't_reap "$T_TMP" "$from"' EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  set -m
  bash -c 'sleep 300 & wait' & g=$!                                  # its own group: bash and a sleep
  HH_FAKE_CLAUDE=busy bash -c 'bash "$1" --name x >/dev/null & sleep 300 & wait' _ "$HH_REPO_ROOT/tests/bin/claude" & gc=$!   # a group with a claude in it
  perl -e '$SIG{TERM} = "IGNORE"; sleep 300' & stubborn=$!
  sleep 300 & edited=$!
  sleep 300 & locp=$!                                              # recorded in the caller's locale, as 0.2.0 wrote it (A83)
  HH_FAKE_CLAUDE=busy bash "$HH_REPO_ROOT/tests/bin/claude" --name y >/dev/null & cl=$!
  set +m
  t_track $g $gc $stubborn $edited $cl $locp
  for p in $g $gc $stubborn $edited $cl $locp; do t_track_group $p; done
  bash -c 'sleep 300 & wait' & own=$!                                # P, the cleanup's own group
  sleep 300 & dead=$!
  t_track $own $dead
  sleep 1
  gchild=$(pgrep -P $g sleep); gcchild=$(pgrep -P $gc sleep); gcclaude=$(pgrep -P $gc -f tests/bin/claude); ownchild=$(pgrep -P $own sleep)
  t_track $gchild $gcchild $gcclaude $ownchild
  for p in $g $gc $stubborn $edited $cl $locp $own $dead $$; do hh-manifest add process pid=$p >/dev/null; done
  kill $dead; wait $dead 2>/dev/null
  f=$T_STATE/manifest.jsonl; jq -c --arg p "$edited" 'if .pid == $p then .started = "Mon Jan  1 00:00:00 2001" else . end' $f > $f.t && mv $f.t $f
  jq -c --arg p "$locp" --arg s "$(ps -o lstart= -p "$locp" | sed 's/^ *//;s/ *$//')" 'if .pid == $p then .started = $s else . end' $f > $f.t && mv $f.t $f
  out=$(hh-cleanup --disk); assert_status "--disk with processes" $? 0
  alive $g && alive $edited && ok "--disk stops no process" || bad "--disk stopped a process"
  out=$(hh-cleanup --finish); assert_status "--finish with processes" $? 0
  sleep 1
  ! alive $g && ok "a recorded process is stopped" || bad "a recorded process is still running"
  ! alive "$gchild" && ok "...with its whole group (A14)" || bad "its group was not signalled"
  ! alive $stubborn && ok "a process that ignores TERM is killed after the wait" || bad "a process that ignores TERM survived"
  ! alive $locp && ok "a process recorded with its start time in the caller's locale is still recognised and stopped (A83)" || bad "a process recorded in the caller's locale was not recognised"
  alive $edited && ok "a process whose start time changed is left alone" || bad "stopped a process whose identity changed"
  assert_contains "...and skipped" "$out" "skipped process $edited by=owner (identity changed)"
  alive $cl && ok "a Claude process is never stopped" || bad "stopped a Claude process"
  assert_contains "...and skipped" "$out" "skipped process $cl by=owner (a Claude process)"
  ! alive $gc && alive "$gcclaude" && ok "a group with a Claude process in it: only the recorded process is stopped" || bad "signalled a group that holds a Claude process"
  ! alive $own && alive "$ownchild" && ok "a process in the cleanup's own group: only it is stopped" || bad "signalled the cleanup's own group"
  assert_contains "the test itself, an ancestor of the cleanup, is skipped" "$out" "skipped process $$ by=owner (this cleanup or its caller)"
  assert_contains "a process already gone is dropped" "$out" "removed process $dead by=owner (already stopped)"
  assert_eq "kept: the edited, the claude and the caller" "$(count process)" "3"
  exit $(( FAILS < 127 ? FAILS : 127 ))   # 128 and above means the section was stopped
) < /dev/null > "$T_TMP/procs.out" 2>&1 & P=$!   # a background group never touches the terminal, so it cannot stop on it
set +m
t_track $P; t_track_group $P
wait $P; rc=$?; cat "$T_TMP/procs.out"
if [ "$rc" -ge 128 ]; then bad "the process section was stopped (exit $rc)"; else FAILS=$((FAILS + rc)); fi
cd /

# ---- tmux panes ----------------------------------------------------------------------------------------------------
r=$(t_repo panes); cd "$r" || exit 2
S="$HH_TMUX_SOCKET"
track_tmux() { t_track "$(tmux -S "$S" display-message -p '#{pid}')" "$(tmux -S "$S" display-message -p -t "$1" '#{pane_pid}')"; }   # its server and pane
tmux -S "$S" new-session -d -s a 'sleep 300'; pa=$(tmux -S "$S" display-message -p -t a '#{pane_id}'); track_tmux a
hh-manifest add tmux socket="$S" pane="$pa" agent=impl >/dev/null
reg="$(hh_registry_dir)/$(hh_pane_key "$(cd "$(dirname "$S")" && pwd -P)/$(basename "$S")" "$pa").json"
mkdir -p "$(dirname "$reg")"; echo '{}' > "$reg"
tmux -S "$S" new-session -d -s b 'sleep 300'; pb=$(tmux -S "$S" display-message -p -t b '#{pane_id}'); track_tmux b
hh-manifest add tmux socket="$S" pane="$pb" agent=rev >/dev/null
tmux -S "$S" kill-session -t b
out=$(hh-cleanup --disk); tmux -S "$S" has-session -t a 2>/dev/null && ok "--disk kills no pane" || bad "--disk killed a pane"
out=$(hh-cleanup --finish); assert_status "--finish with panes" $? 0
tmux -S "$S" has-session -t a 2>/dev/null && bad "the recorded pane is still there" || ok "the recorded pane is killed"
[ ! -e "$reg" ] && ok "...and its registry entry removed" || bad "its registry entry is left"
assert_contains "a pane already gone is dropped" "$out" "removed tmux $pb by=owner (pane already gone)"
# a new server hands out the same pane id: the pane is somebody else's
tmux -S "$S" kill-server 2>/dev/null; sleep 0.5
tmux -S "$S" new-session -d -s c 'sleep 300'; pc=$(tmux -S "$S" display-message -p -t c '#{pane_id}'); track_tmux c
hh-manifest add tmux socket="$S" pane="$pc" agent=impl >/dev/null
tmux -S "$S" kill-server 2>/dev/null; sleep 0.5
tmux -S "$S" new-session -d -s d 'sleep 300'; pd=$(tmux -S "$S" display-message -p -t d '#{pane_id}'); track_tmux d
assert_eq "the new server reused the pane id" "$pd" "$pc"
out=$(hh-cleanup --finish)
tmux -S "$S" has-session -t d 2>/dev/null && ok "a pane that took a recorded id on a new server is left alone" || bad "killed another pane by a reused id"
assert_contains "...and skipped" "$out" "skipped tmux $pc by=owner (pane is not the one recorded)"
tmux -S "$S" kill-server 2>/dev/null; sleep 0.5
# the caller's own pane is never killed
po=$(tmux -S "$S" new-session -d -s o -P -F '#{pane_id}' "sleep 2; HH_PROJECT='$r' hh-cleanup --finish > '$T_TMP/own.out' 2>&1; sleep 300")
track_tmux o
hh-manifest add tmux socket="$S" pane="$po" agent=orch >/dev/null
sleep 6
tmux -S "$S" has-session -t o 2>/dev/null && ok "the caller's own pane is not killed" || bad "the cleanup killed its own pane"
assert_contains "...and skipped" "$(cat "$T_TMP/own.out")" "skipped tmux $po by=owner (the caller's own pane)"
tmux -S "$S" kill-server 2>/dev/null
cd /

# ---- worktrees -----------------------------------------------------------------------------------------------------
r=$(t_repo trees); cd "$r" || exit 2
git worktree add -q -b merged "$T_TMP/wt-merged" main
git worktree add -q -b dirty "$T_TMP/wt-dirty" main; echo d > "$T_TMP/wt-dirty/new"
git worktree add -q -b ahead "$T_TMP/wt-ahead" main; git -C "$T_TMP/wt-ahead" commit -q --allow-empty -m ahead
for w in merged dirty ahead; do hh-manifest add worktree path="$T_TMP/wt-$w" base=main >/dev/null; done
hh-manifest add remote host=box path=/home/u/proj >/dev/null
out=$(hh-cleanup --disk); [ -d "$T_TMP/wt-merged" ] && ok "--disk removes no worktree" || bad "--disk removed a worktree"
out=$(hh-cleanup --finish); assert_status "--finish with worktrees" $? 0
[ ! -e "$T_TMP/wt-merged" ] && ok "a merged, clean worktree is removed" || bad "a merged, clean worktree is left"
git rev-parse --verify -q merged >/dev/null && ok "...and its branch kept" || bad "its branch was deleted"
[ -f "$T_TMP/wt-dirty/new" ] && ok "a dirty worktree is kept" || bad "a dirty worktree was removed"
assert_contains "...with its reason" "$out" "kept worktree $T_TMP/wt-dirty by=owner (uncommitted changes)"
[ -d "$T_TMP/wt-ahead" ] && ok "a worktree not merged into its base is kept" || bad "an unmerged worktree was removed"
assert_contains "...with its reason" "$out" "kept worktree $T_TMP/wt-ahead by=owner (not merged into main)"
assert_contains "a remote entry is kept until hh-remote-sync" "$out" "kept remote box:/home/u/proj by=owner (remote cleanup arrives with hh-remote-sync)"
assert_eq "kept: dirty, ahead and the remote" "$(count)" "3"

# ---- one cleanup at a time -----------------------------------------------------------------------------------------
sleep 300 & holder=$!; t_track $holder
mkdir $T_STATE/cleanup.lock; hh_holder_json $holder > $T_STATE/cleanup.lock/holder.json
hh-cleanup --finish >/dev/null 2>&1; assert_status "a second cleanup is refused" $? 75
[ -d "$T_TMP/wt-dirty" ] && assert_eq "...and does nothing" "$(count)" "3"
kill $holder; wait $holder 2>/dev/null
hh-cleanup --finish >/dev/null; assert_status "a dead holder's lock is taken over" $? 0
[ ! -e $T_STATE/cleanup.lock ] && ok "the lock is released afterwards" || bad "the cleanup lock was left"
cd /
t_done
