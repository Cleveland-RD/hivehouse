#!/usr/bin/env bash
# The machine's one slot (bin/hh-slot, bin/hh-lib.sh): used only when the folder passes every check; else the user's own.
# The tests reach a fixture folder through a scratch copy of bin/ (t_slot_bin) and never the real one.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
r=$(t_repo proj); cd "$r" || exit 2
ME=$(id -u)
M="$T_TMP/mach/base/slot"
mkslot() {  # a valid fixture: slot/ and slot/queue/ mode 2775, the parents 755
  rm -rf "$T_TMP/mach"; mkdir -p "$M/queue"; chmod 755 "$T_TMP/mach" "$T_TMP/mach/base"; chmod 2775 "$M" "$M/queue"
}
SB=$(t_slot_bin "$M"); SBX=$(t_slot_bin "$M" 0)
used() {  # used <bin dir>: which slot a run under that copy of bin/ takes: machine, or the user's own
  rm -rf "$HIVEHOUSE_HOME/slot.lock"
  env -u HH_SLOT_LOCAL "$1/hh-slot" run probe -- sh -c "[ -d '$M/slot.lock' ] && echo machine || { [ -d '$HIVEHOUSE_HOME/slot.lock' ] && echo own; }"
}
why() { env -u HH_SLOT_LOCAL "$SB/hh-slot" status 2>&1 >/dev/null; }
# --- the four-digit mode
d="$T_TMP/modes"; mkdir -p "$d/a" "$d/b" "$d/c"; chmod 2775 "$d/a"; chmod 775 "$d/b"; chmod 1777 "$d/c"
assert_eq "a setgid folder reads 2775" "$(hh_stat4 "$d/a")" "2775"
assert_eq "without setgid it reads 0775" "$(hh_stat4 "$d/b")" "0775"
assert_eq "hh_pad4 pads 775 (Linux %a) to 0775" "$(hh_pad4 775)" "0775"
assert_eq "...and 2775 stays" "$(hh_pad4 2775)" "2775"
assert_eq "...and 0 becomes 0000" "$(hh_pad4 0)" "0000"
hh_pad4 77x >/dev/null 2>&1; assert_status "...and a non-octal value fails" $? 1
assert_eq "sticky is kept" "$(hh_stat4 "$d/c")" "1777"
hh_stat4 "$d/none" 2>/dev/null; assert_status "a missing path fails" $? 1
# --- a valid folder is used
mkslot; assert_eq "a valid machine folder is the slot" "$(used "$SB")" "machine"
assert_contains "status names it" "$(why)" "the machine slot"
out=$(env -u HH_SLOT_LOCAL "$SB/hh-slot" run lbl -- "$SB/hh-slot" status 2>/dev/null); assert_contains "the holder is recorded there" "$out" '"label":"lbl"'
( umask 022; env -u HH_SLOT_LOCAL "$SB/hh-slot" run perm -- sh -c "stat -f %Lp '$M/slot.lock' '$M/slot.lock/holder.json' > '$T_TMP/perm'" )
assert_eq "its lock and holder record are group-writable, so another user can take over a gone holder" "$(tr '\n' ' ' < "$T_TMP/perm")" "775 664 "
# --- the test environment never touches the machine path
mkslot; rm -rf "$HIVEHOUSE_HOME/slot.lock"
"$SB/hh-slot" run local -- sh -c "[ -d '$HIVEHOUSE_HOME/slot.lock' ]"; assert_status "HH_SLOT_LOCAL=1 (the test environment's) uses the user's own slot" $? 0
[ ! -e "$M/slot.lock" ] && [ -z "$(ls -A "$M/queue")" ] && ok "...and leaves a valid machine folder untouched" || bad "...and leaves a valid machine folder untouched"
assert_eq "t_setup sets HH_SLOT_LOCAL" "${HH_SLOT_LOCAL:-}" "1"
assert_contains "status says why" "$("$SB/hh-slot" status 2>&1 >/dev/null)" "HH_SLOT_LOCAL=1"
# --- each failed condition falls back to the user's own slot, and status says why
mkslot; rm -rf "$M"; mkdir "$T_TMP/mach/real"; chmod 2775 "$T_TMP/mach/real"; mkdir "$T_TMP/mach/real/queue"; chmod 2775 "$T_TMP/mach/real/queue"; ln -s "$T_TMP/mach/real" "$M"
assert_eq "slot/ a link: own slot" "$(used "$SB")" "own"; assert_contains "...the reason is a link" "$(why)" "is a link"
mkslot; rm -rf "$M/queue"; mkdir "$T_TMP/mach/q"; chmod 2775 "$T_TMP/mach/q"; ln -s "$T_TMP/mach/q" "$M/queue"
assert_eq "slot/queue a link: own slot" "$(used "$SB")" "own"; assert_contains "...the reason is a link" "$(why)" "queue is a link"
mkslot; assert_eq "not root's (the required owner is another uid): own slot" "$(used "$SBX")" "own"
assert_contains "...the reason names the owner" "$(env -u HH_SLOT_LOCAL "$SBX/hh-slot" status 2>&1 >/dev/null)" "is owned by uid $ME, not 0"
mkslot; chmod 755 "$M"; assert_eq "mode 755 (no setgid, no group write): own slot" "$(used "$SB")" "own"; assert_contains "...the reason is the mode" "$(why)" "has mode 0755, not 2775"
mkslot; chmod 775 "$M"; assert_eq "mode 775 without setgid: own slot" "$(used "$SB")" "own"; assert_contains "...the reason is the mode" "$(why)" "has mode 0775, not 2775"
mkslot; chmod 2777 "$M/queue"; assert_eq "queue/ mode 2777: own slot" "$(used "$SB")" "own"; assert_contains "...the reason is the mode" "$(why)" "queue has mode 2777, not 2775"
mkslot; chmod 775 "$T_TMP/mach/base"; assert_eq "a parent the user can write: own slot" "$(used "$SB")" "own"
assert_contains "...the reason is the parent" "$(why)" "writable by group or others"
mkslot; rm -rf "$M"; assert_eq "no folder: own slot" "$(used "$SB")" "own"; assert_contains "...and status points to setup" "$(why)" "hh-slot setup"
# --- a gone holder in the machine folder is taken over
mkslot; sleep 30 & s=$!; ls=$(hh_lstart $s); kill $s; wait $s 2>/dev/null
mkdir "$M/slot.lock"; chmod 775 "$M/slot.lock"; jq -nc --argjson pid "$s" --arg l "$ls" '{pid:$pid,lstart:$l,created:0}' > "$M/slot.lock/holder.json"; chmod 664 "$M/slot.lock/holder.json"
env -u HH_SLOT_LOCAL "$SB/hh-slot" run take -- true; assert_status "a group-writable lock whose holder is gone is taken over" $? 0
# --- a waiter queues in the machine folder
mkslot; env -u HH_SLOT_LOCAL "$SB/hh-slot" run holder -- sleep 3 & h=$!; sleep 0.7
env -u HH_SLOT_LOCAL "$SB/hh-slot" run --wait w -- true & w=$!; sleep 0.7
assert_eq "a ticket is filed in the machine queue" "$(ls "$M/queue" | wc -l | tr -d ' ')" "1"
assert_eq "...group-writable, so another user can drop it once its process is gone" "$(stat -f %Lp "$M/queue/$(ls "$M/queue")")" "664"
wait $h $w; assert_eq "the queue is empty after" "$(ls "$M/queue" | wc -l | tr -d ' ')" "0"
# --- hh-slot setup prints the lines and runs nothing
out=$("$SB/hh-slot" setup); assert_status "setup succeeds" $? 0
assert_contains "mkdir for both folders" "$out" "sudo mkdir -p -- '$M/queue'"
assert_contains "chmod 2775 for both" "$out" "sudo chmod -- 2775 '$M' '$M/queue'"
assert_contains "chown to root and staff on macOS" "$out" "sudo chown -- root:staff '$M' '$M/queue'"
assert_contains "the parent is root's and 0755" "$out" "sudo chmod -- 0755 '$T_TMP/mach/base'"
t_run_printed "$(printf '%s\n' "$out" | grep '^sudo ')"; assert_status "each printed sudo line runs as this user on the scratch folder (BSD chown and chmod take the options first)" $? 0
assert_contains "a group can be named" "$("$SB/hh-slot" setup users)" "sudo chown -- root:users '$M' '$M/queue'"
"$SB/hh-slot" setup 'a b' 2>/dev/null; assert_status "a bad group name is a usage error" $? 64
cd /; t_done
