#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
LOCK="$HIVEMIND_HOME/slot.lock"
assert_eq "free at start" "$(hm-slot status)" "free"
out=$(hm-slot run gate -- bash -c 'hm-slot status'); assert_contains "held during run" "$out" '"label":"gate"'
assert_contains "holder records the project" "$out" "\"project\":\"$r\""
assert_eq "free after run" "$(hm-slot status)" "free"
hm-slot run seven -- sh -c 'exit 7'; assert_status "the command's exit status is passed on" $? 7
hm-slot run long -- sleep 3 & bg=$!; sleep 1
hm-slot run other -- true 2>"$T_TMP/busy.err"; assert_status "busy is refused" $? 75
assert_contains "...and the message names the lock's path, so a stuck one can be found" "$(cat "$T_TMP/busy.err")" "$LOCK"
hm-slot acquire x --pid $$ 2>/dev/null; assert_status "acquire while busy is refused" $? 75
# a second caller with a different environment (other project, HM_PROJECT of a third repo, plugin data set) meets the same lock
r2=$(t_repo proj2); r3=$(t_repo proj3)
(cd "$r2" && env -u HM_PROJECT CLAUDE_PLUGIN_DATA="$T_TMP/plugdata" hm-slot run x -- true 2>/dev/null); assert_status "other project refused" $? 75
(cd "$T_TMP" && HM_PROJECT="$r3" CLAUDE_PLUGIN_DATA="$T_TMP/plugdata" hm-slot run x -- true 2>/dev/null); assert_status "HM_PROJECT of another repo refused" $? 75
wait $bg
sleep 30 & p=$!; hm-slot acquire server --pid $p; assert_contains "acquired for pid" "$(hm-slot status)" "\"pid\":$p"
assert_contains "acquired holder has a start time" "$(hm-slot status)" '"lstart":"'
# A22: release needs the holder's own pid
hm-slot release --pid $$ 2>/dev/null; assert_status "release with the wrong pid is refused" $? 4
[ -d "$LOCK" ] && ok "the lock is left in place" || bad "the lock is left in place"
hm-slot release --pid $p --label other 2>/dev/null; assert_status "release with the wrong label is refused" $? 4
hm-slot release 2>/dev/null; assert_status "release without a pid is a usage error" $? 64
hm-slot release --pid $p --label server; assert_status "release by the holder" $? 0
assert_eq "free after release" "$(hm-slot status)" "free"
hm-slot acquire server --pid $p; kill $p; wait $p 2>/dev/null
assert_eq "a dead holder reads as free" "$(hm-slot status)" "free"
hm-slot run after -- true; assert_status "dead holder is stale" $? 0
# pid reuse: a live pid with another start time is not the holder
sleep 30 & live=$!
mkdir "$LOCK"; jq -nc --argjson pid "$live" '{pid:$pid,lstart:"Mon Jan  1 00:00:00 2001",created:0,label:"old"}' > "$LOCK/holder.json"
assert_eq "live pid, wrong start time reads as free" "$(hm-slot status)" "free"
hm-slot run reuse -- true; assert_status "live pid, wrong start time is stale" $? 0
mkdir "$LOCK"; jq -nc --argjson pid "$live" '{pid:$pid,lstart:"Mon Jan  1 00:00:00 2001",created:0,label:"old"}' > "$LOCK/holder.json"
hm-slot release --pid $live 2>/dev/null; assert_status "release re-reads the start time and refuses" $? 4
rm -rf "$LOCK"; kill $live; wait $live 2>/dev/null
# run's trap removes only its own lock
hm-slot run mine -- sh -c "jq -nc '{pid:1,lstart:\"x\",created:0,label:\"theirs\"}' > \"$LOCK/holder.json\""
[ -f "$LOCK/holder.json" ] && assert_contains "another holder's record survives run's trap" "$(cat "$LOCK/holder.json")" '"theirs"' || bad "another holder's record survives run's trap"
rm -rf "$LOCK"
# kill -9 of hm-slot run frees the slot (its child may still run): documented behaviour
hm-slot run nine -- sleep 3 & k=$!; sleep 0.5; kill -9 $k; wait $k 2>/dev/null
assert_eq "kill -9 of run frees the slot" "$(hm-slot status)" "free"
# A2/A17: exactly one winner, 20 rounds each
race() {  # race <n contenders> <stale|fresh> : prints the number of contenders that ran their command
  local n="$1" mode="$2" f="$T_TMP/won" i s
  rm -f "$f" "$T_TMP/won.1"; rm -rf "$LOCK" "$LOCK.takeover"
  if [ "$mode" = stale ]; then
    sleep 30 & s=$!; local ls; ls=$(hm_lstart $s); kill $s; wait $s 2>/dev/null
    mkdir "$LOCK"; jq -nc --argjson pid "$s" --arg l "$ls" '{pid:$pid,lstart:$l,created:0}' > "$LOCK/holder.json"
  fi
  for i in $(seq 1 "$n"); do
    ( [ "$i" = 3 ] && sleep 0.03; hm-slot run "c$i" -- sh -c "echo $i >> '$f'; sleep 0.5" 2>/dev/null ) &
  done
  wait
  if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi
}
bad_rounds=0; for round in $(seq 1 20); do [ "$(race 2 fresh)" = 1 ] || bad_rounds=$((bad_rounds + 1)); done
assert_eq "two contenders, fresh lock: one winner in 20 rounds" "$bad_rounds" "0"
bad_rounds=0; for round in $(seq 1 20); do [ "$(race 2 stale)" = 1 ] || bad_rounds=$((bad_rounds + 1)); done
assert_eq "two contenders, stale lock: one winner in 20 rounds" "$bad_rounds" "0"
bad_rounds=0; for round in $(seq 1 20); do [ "$(race 3 stale)" = 1 ] || bad_rounds=$((bad_rounds + 1)); done
assert_eq "three contenders (one late), stale lock: one winner in 20 rounds" "$bad_rounds" "0"
# a takeover guard left by a crashed process
rm -rf "$LOCK"; mkdir "$LOCK.takeover"; sleep 30 & s=$!; ls=$(hm_lstart $s); kill $s; wait $s 2>/dev/null
mkdir "$LOCK"; jq -nc --argjson pid "$s" --arg l "$ls" '{pid:$pid,lstart:$l,created:0}' > "$LOCK/holder.json"
hm-slot run g -- true 2>/dev/null; assert_status "a fresh takeover guard blocks a takeover" $? 75
touch -t 202001010000 "$LOCK.takeover"; hm-slot run g -- true; assert_status "an old takeover guard is cleared" $? 0
# the takeover guard is reclaimed after 30 s and not before (a guard 20 s old blocks, one 60 s old is cleared)
ago() { date -v-"$1"S +%Y%m%d%H%M.%S; }
rm -rf "$LOCK" "$LOCK.takeover"; mkdir "$LOCK.takeover"; mkdir "$LOCK"
jq -nc --argjson pid "$s" --arg l "$ls" '{pid:$pid,lstart:$l,created:0}' > "$LOCK/holder.json"
touch -t "$(ago 20)" "$LOCK.takeover"; hm-slot run g20 -- true 2>/dev/null; assert_status "a 20 s old takeover guard still blocks" $? 75
touch -t "$(ago 60)" "$LOCK.takeover"; hm-slot run g60 -- true; assert_status "a 60 s old takeover guard is reclaimed" $? 0
# a lock with no holder record is busy for 10 s and stale after
rm -rf "$LOCK" "$LOCK.takeover"; mkdir "$LOCK"
hm-slot run n0 -- true 2>/dev/null; assert_status "a fresh lock with no holder record is busy" $? 75
touch -t "$(ago 20)" "$LOCK"; hm-slot run n20 -- true; assert_status "a lock with no holder record, 20 s old, is stale" $? 0
# the holder is re-read under the guard: a takeover that lost the race to another one backs off (the swap happens just
# before the guard is taken, so nothing here depends on timing)
swap_hook=""
mkdir() { if [ -n "$swap_hook" ] && [ "$1" = "$LOCK.takeover" ]; then local h="$swap_hook"; swap_hook=""; eval "$h"; fi; command mkdir "$@"; }
sleep 30 & d2=$!; ls2=$(hm_lstart $d2); kill $d2; wait $d2 2>/dev/null
dead_holder() { rm -rf "$LOCK" "$LOCK.takeover"; command mkdir "$LOCK"; jq -nc --argjson pid "$s" --arg l "$ls" '{pid:$pid,lstart:$l,created:0}' > "$LOCK/holder.json"; }
mine=$(hm_holder_json $$ '{"label":"me"}')
dead_holder; swap_hook='hm_holder_json $$ > "$LOCK/holder.json"'
hm_lock_try "$LOCK" "$mine"; assert_status "a holder that came back to life is not taken over" $? 1
assert_eq "...and its record is untouched" "$(jq -r .pid "$LOCK/holder.json")" "$$"
[ ! -e "$LOCK.takeover" ] && ok "...and the guard is released" || bad "the guard was left behind"
dead_holder; swap_hook='jq -nc --argjson pid "$d2" --arg l "$ls2" "{pid:\$pid,lstart:\$l,created:1}" > "$LOCK/holder.json"'
hm_lock_try "$LOCK" "$mine"; assert_status "another stale holder written meanwhile: back off" $? 1
assert_eq "...its record is untouched" "$(jq -r .created "$LOCK/holder.json")" "1"
rm -rf "$LOCK" "$LOCK.takeover"; command mkdir "$LOCK"; touch -t "$(ago 20)" "$LOCK"; swap_hook='touch "$LOCK"'
hm_lock_try "$LOCK" "$mine"; assert_status "a record-less lock refreshed meanwhile is no longer stale: back off" $? 1
[ -d "$LOCK" ] && ok "...and the lock is still there" || bad "the refreshed lock was removed"
unset -f mkdir; rm -rf "$LOCK" "$LOCK.takeover"
# usage and A1
hm-slot bogus 2>/dev/null; assert_status "unknown command is a usage error" $? 64
hm-slot acquire x 2>/dev/null; assert_status "acquire without --pid is a usage error" $? 64
mkdir "$T_TMP/norepo"; cd "$T_TMP/norepo"
assert_eq "status works outside a repo" "$(hm-slot status)" "free"
out=$(hm-slot run outside -- hm-slot status); assert_contains "run works outside a repo" "$out" '"label":"outside"'
assert_contains "no project is recorded outside a repo" "$out" '"project":""'
[ ! -e "$T_TMP/norepo/$T_STATE" ] && [ ! -e /$T_STATE ] && ok "no project state written outside a repo" || bad "no project state written outside a repo"
cd /; t_teardown; t_done
