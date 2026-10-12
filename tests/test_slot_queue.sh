#!/usr/bin/env bash
# The slot's queue (bin/hh-slot, bin/hh-lib.sh): a caller that waits files a ticket and takes the slot only as the oldest
# live ticket; a caller that does not wait is refused at once, also while tickets wait.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
r=$(t_repo proj); cd "$r" || exit 2
LOCK="$HIVEHOUSE_HOME/slot.lock"; Q="$HIVEHOUSE_HOME/queue"
# --- ordering, by name alone: epoch first, then the pid as a number
mkdir -p "$T_TMP/ord"; : > "$T_TMP/ord/0000000100-100.json"; : > "$T_TMP/ord/0000000100-99.json"
: > "$T_TMP/ord/0000000099-5000.json"; : > "$T_TMP/ord/junk.json"; : > "$T_TMP/ord/0000000100-7.txt"
assert_eq "tickets are served by filing second, then by pid as a number" \
  "$(hh_queue_order "$T_TMP/ord" | tr '\n' ' ')" "0000000099-5000.json 0000000100-99.json 0000000100-100.json "
# --- a live older ticket holds the queue even when the slot is free
sleep 60 & old=$!; t_track $old
mkdir -p "$Q"; tk="$Q/0000000001-$old.json"; hh_holder_json "$old" '{"label":"older"}' > "$tk"
hh-slot run nowait -- true 2>"$T_TMP/e"; assert_status "no --wait: refused at once while a ticket waits, the slot free" $? 75
assert_eq "hh-slot status is free, the queue is shown" "$(hh-slot status | sed -n 1p)" "free"
assert_contains "status lists the waiting ticket" "$(hh-slot status)" '"label":"older"'
SECONDS=0; hh-slot run --wait 2 late -- true 2>/dev/null; s=$?; d=$SECONDS
assert_status "--wait <s>: the time runs out behind an older live ticket" $s 75
[ "$d" -ge 2 ] && [ "$d" -le 5 ] && ok "...after about the time given" || bad "waited $d s, expected about 2"
assert_eq "...and its own ticket is gone" "$(ls "$Q" | wc -l | tr -d ' ')" "1"
hh-slot acquire x --pid $$ --wait 1 2>/dev/null; assert_status "acquire --wait <s> times out the same way" $? 75
# --- a dead ticket is skipped and dropped
kill $old; wait $old 2>/dev/null
hh-slot run --wait 5 after -- true; assert_status "a dead older ticket does not hold the queue" $? 0
assert_eq "...and it was dropped" "$(ls "$Q" | wc -l | tr -d ' ')" "0"
# --- served in the order they filed
hh-slot run holder -- sleep 4 & h=$!; sleep 0.7
out="$T_TMP/order"; : > "$out"
hh-slot run --wait first -- sh -c "echo first >> '$out'" & a=$!; sleep 1.3
hh-slot run --wait second -- sh -c "echo second >> '$out'" & b=$!; sleep 0.5
assert_eq "two waiters file two tickets" "$(ls "$Q" | wc -l | tr -d ' ')" "2"
wait $h $a $b
assert_eq "the first to file runs first" "$(tr '\n' ' ' < "$out")" "first second "
assert_eq "the queue is empty after" "$(ls "$Q" | wc -l | tr -d ' ')" "0"
# --- a waiter that is killed leaves no ticket the next waiter has to outlast
hh-slot run holder -- sleep 3 & h=$!; sleep 0.5
hh-slot run --wait gone -- true & g=$!; sleep 0.7; kill $g; wait $g 2>/dev/null
assert_eq "an interrupted waiter removes its ticket" "$(ls "$Q" | wc -l | tr -d ' ')" "0"
wait $h
# --- a planted link at the ticket's name is not followed
sleep 30 & p=$!; t_track $p; mkdir -p "$Q"
hh-slot run holder -- sleep 600 & h=$!; sleep 0.5; t_track $h $(pgrep -P $h)
secret="$T_TMP/secret"; echo keep > "$secret"
now=$(date +%s)
for k in $(seq 0 119); do ln -s "$secret" "$Q/$(printf '%010d' $((now + k)))-$p.json"; done   # every second it could file in for the next two minutes
hh-slot acquire planted --pid $p --wait 1 2>/dev/null; assert_status "a ticket name taken by a link makes the write fail" $? 1
assert_eq "...and the file it pointed at is untouched" "$(cat "$secret")" "keep"
hc=$(pgrep -P $h); kill $h $hc 2>/dev/null; wait $h 2>/dev/null; kill $p; wait $p 2>/dev/null   # the holder: its own pid and its sleep, recorded above
# --- the argument forms
hh-slot run --wait 2>/dev/null; assert_status "run --wait with nothing after is a usage error" $? 64
hh-slot run --wait 3 onlylabel 2>/dev/null; assert_status "run --wait <s> <label> with no command is a usage error" $? 64
hh-slot acquire x --pid $$ --wait abc 2>/dev/null; assert_status "acquire --wait with a word that is not a number is a usage error" $? 64
rm -rf "$Q" "$LOCK"
hh-slot run --wait 08 zero -- true 2>/dev/null; assert_status "--wait 08 is eight seconds, not an octal error" $? 0
hh-slot run --wait 09 nine -- true 2>/dev/null; assert_status "--wait 09 too" $? 0
# --- a --wait under a slot an ancestor holds is refused at once, not waited for
SECONDS=0; hh-slot run outer -- hh-slot run --wait 8 inner -- true 2>"$T_TMP/nest.err"; s=$?; d=$SECONDS
assert_status "a --wait nested under the slot its own parent holds is refused (75)" $s 75
[ "$d" -le 3 ] && ok "...at once" || bad "...took $d s"
assert_contains "...and says why" "$(cat "$T_TMP/nest.err")" "held by your own parent"
assert_eq "...leaving no ticket" "$(ls "$Q" 2>/dev/null | wc -l | tr -d ' ')" "0"
SECONDS=0; hh-slot run outer -- env HH_SLOT_HELD=1 hh-slot run --wait 2 inner -- true 2>"$T_TMP/nest2.err"; s=$?; d=$SECONDS
[ "$s" = 75 ] && [ "$d" -ge 2 ] && ok "a HH_SLOT_HELD that is not the holder changes nothing: it waits out its time" || bad "HH_SLOT_HELD=1: exit $s after $d s"
case "$(cat "$T_TMP/nest2.err")" in *"own parent"*) bad "...and it must not say parent" ;; *) ok "...and does not claim the holder is its parent" ;; esac
# ...also with another waiter ahead of it in the queue (the outer holds, W waits for the lock, the inner waits behind W)
rm -rf "$Q" "$LOCK"; out3="$T_TMP/three"; : > "$out3"; rm -f "$T_TMP/in3.res"
hh-slot run --wait outer -- sh -c "sleep 2; SECONDS=0; hh-slot run --wait 8 inner -- true 2>'$T_TMP/in3.err'; echo \$? \$SECONDS > '$T_TMP/in3.res'" & o3=$!
sleep 0.7
hh-slot run --wait 8 other -- sh -c "echo other >> '$out3'" 2>/dev/null & w3=$!
wait $o3 $w3
read -r rc3 secs3 < "$T_TMP/in3.res"
assert_eq "the nested --wait is refused (75) even with another waiter ahead of it" "$rc3" "75"
[ "${secs3:-99}" -le 2 ] && ok "...at once, not after its own time" || bad "...took ${secs3:-?} s"
assert_contains "...and says why" "$(cat "$T_TMP/in3.err")" "held by your own parent"
assert_eq "...and the waiter ahead of it still ran" "$(cat "$out3")" "other"
# ...the check runs on every pass: an older live ticket keeps this one off the head, and the parent takes the slot after it filed
rm -rf "$Q" "$LOCK"; mkdir -p "$Q"; sleep 60 & old3=$!; t_track $old3; hh_holder_json $old3 '{"label":"older"}' > "$Q/0000000001-$old3.json"
SECONDS=0; ( HH_SLOT_HELD=$$ hh-slot run --wait 8 child -- true 2>"$T_TMP/c3.err"; echo $? > "$T_TMP/c3.rc" ) & c3=$!
sleep 1; mkdir "$LOCK"; hh_holder_json $$ '{"label":"parent"}' > "$LOCK/holder.json"
wait $c3; assert_eq "a waiter off the head still refuses once its parent holds the slot" "$(cat "$T_TMP/c3.rc")" "75"
assert_contains "...saying so" "$(cat "$T_TMP/c3.err")" "held by your own parent"
rm -rf "$LOCK" "$Q"; kill $old3; wait $old3 2>/dev/null
# ...and a holder that is gone is not "the parent": it is taken over
sleep 30 & dead3=$!; kill $dead3; wait $dead3 2>/dev/null
mkdir "$LOCK"; jq -nc --argjson pid "$dead3" '{pid:$pid,lstart:"Mon Jan  1 00:00:00 2001",created:0}' > "$LOCK/holder.json"
HH_SLOT_HELD=$dead3 hh-slot run --wait 3 afterdead -- true 2>/dev/null; assert_status "a gone holder named by HH_SLOT_HELD is taken over, not refused" $? 0
hh-slot run --wait w -- true; assert_status "--wait with no time and a free slot just runs" $? 0
cd /; t_done
