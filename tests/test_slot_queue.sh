#!/usr/bin/env bash
# The slot's queue (bin/hm-slot, bin/hm-lib.sh): a caller that waits files a ticket and takes the slot only as the oldest
# live ticket; a caller that does not wait is refused at once, also while tickets wait.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
LOCK="$HIVEMIND_HOME/slot.lock"; Q="$HIVEMIND_HOME/queue"
# --- ordering, by name alone: epoch first, then the pid as a number
mkdir -p "$T_TMP/ord"; : > "$T_TMP/ord/0000000100-100.json"; : > "$T_TMP/ord/0000000100-99.json"
: > "$T_TMP/ord/0000000099-5000.json"; : > "$T_TMP/ord/junk.json"; : > "$T_TMP/ord/0000000100-7.txt"
assert_eq "tickets are served by filing second, then by pid as a number" \
  "$(hm_queue_order "$T_TMP/ord" | tr '\n' ' ')" "0000000099-5000.json 0000000100-99.json 0000000100-100.json "
# --- a live older ticket holds the queue even when the slot is free
sleep 60 & old=$!; t_track $old
mkdir -p "$Q"; tk="$Q/0000000001-$old.json"; hm_holder_json "$old" '{"label":"older"}' > "$tk"
hm-slot run nowait -- true 2>"$T_TMP/e"; assert_status "no --wait: refused at once while a ticket waits, the slot free" $? 75
assert_eq "hm-slot status is free, the queue is shown" "$(hm-slot status | sed -n 1p)" "free"
assert_contains "status lists the waiting ticket" "$(hm-slot status)" '"label":"older"'
SECONDS=0; hm-slot run --wait 2 late -- true 2>/dev/null; s=$?; d=$SECONDS
assert_status "--wait <s>: the time runs out behind an older live ticket" $s 75
[ "$d" -ge 2 ] && [ "$d" -le 5 ] && ok "...after about the time given" || bad "waited $d s, expected about 2"
assert_eq "...and its own ticket is gone" "$(ls "$Q" | wc -l | tr -d ' ')" "1"
hm-slot acquire x --pid $$ --wait 1 2>/dev/null; assert_status "acquire --wait <s> times out the same way" $? 75
# --- a dead ticket is skipped and dropped
kill $old; wait $old 2>/dev/null
hm-slot run --wait 5 after -- true; assert_status "a dead older ticket does not hold the queue" $? 0
assert_eq "...and it was dropped" "$(ls "$Q" | wc -l | tr -d ' ')" "0"
# --- served in the order they filed
hm-slot run holder -- sleep 4 & h=$!; sleep 0.7
out="$T_TMP/order"; : > "$out"
hm-slot run --wait first -- sh -c "echo first >> '$out'" & a=$!; sleep 1.3
hm-slot run --wait second -- sh -c "echo second >> '$out'" & b=$!; sleep 0.5
assert_eq "two waiters file two tickets" "$(ls "$Q" | wc -l | tr -d ' ')" "2"
wait $h $a $b
assert_eq "the first to file runs first" "$(tr '\n' ' ' < "$out")" "first second "
assert_eq "the queue is empty after" "$(ls "$Q" | wc -l | tr -d ' ')" "0"
# --- a waiter that is killed leaves no ticket the next waiter has to outlast
hm-slot run holder -- sleep 3 & h=$!; sleep 0.5
hm-slot run --wait gone -- true & g=$!; sleep 0.7; kill $g; wait $g 2>/dev/null
assert_eq "an interrupted waiter removes its ticket" "$(ls "$Q" | wc -l | tr -d ' ')" "0"
wait $h
# --- a planted link at the ticket's name is not followed
sleep 30 & p=$!; t_track $p; mkdir -p "$Q"
hm-slot run holder -- sleep 3 & h=$!; sleep 0.5
secret="$T_TMP/secret"; echo keep > "$secret"
ln -s "$secret" "$Q/$(printf '%010d' "$(date +%s)")-$p.json"; ln -s "$secret" "$Q/$(printf '%010d' $(( $(date +%s) + 1 )))-$p.json"
hm-slot acquire planted --pid $p --wait 1 2>/dev/null; assert_status "a ticket name taken by a link makes the write fail" $? 1
assert_eq "...and the file it pointed at is untouched" "$(cat "$secret")" "keep"
wait $h; kill $p; wait $p 2>/dev/null
# --- the argument forms
hm-slot run --wait 2>/dev/null; assert_status "run --wait with nothing after is a usage error" $? 64
hm-slot run --wait 3 onlylabel 2>/dev/null; assert_status "run --wait <s> <label> with no command is a usage error" $? 64
hm-slot acquire x --pid $$ --wait abc 2>/dev/null; assert_status "acquire --wait with a word that is not a number is a usage error" $? 64
rm -rf "$Q" "$LOCK"
hm-slot run --wait 08 zero -- true 2>/dev/null; assert_status "--wait 08 is eight seconds, not an octal error" $? 0
hm-slot run --wait 09 nine -- true 2>/dev/null; assert_status "--wait 09 too" $? 0
# --- a --wait under a slot an ancestor holds is refused at once, not waited for
SECONDS=0; hm-slot run outer -- hm-slot run --wait 8 inner -- true 2>"$T_TMP/nest.err"; s=$?; d=$SECONDS
assert_status "a --wait nested under the slot its own parent holds is refused (75)" $s 75
[ "$d" -le 3 ] && ok "...at once" || bad "...took $d s"
assert_contains "...and says why" "$(cat "$T_TMP/nest.err")" "held by your own parent"
assert_eq "...leaving no ticket" "$(ls "$Q" 2>/dev/null | wc -l | tr -d ' ')" "0"
SECONDS=0; hm-slot run outer -- env HM_SLOT_HELD=1 hm-slot run --wait 2 inner -- true 2>"$T_TMP/nest2.err"; s=$?; d=$SECONDS
[ "$s" = 75 ] && [ "$d" -ge 2 ] && ok "a HM_SLOT_HELD that is not the holder changes nothing: it waits out its time" || bad "HM_SLOT_HELD=1: exit $s after $d s"
case "$(cat "$T_TMP/nest2.err")" in *"own parent"*) bad "...and it must not say parent" ;; *) ok "...and does not claim the holder is its parent" ;; esac
hm-slot run --wait w -- true; assert_status "--wait with no time and a free slot just runs" $? 0
cd /; t_done
