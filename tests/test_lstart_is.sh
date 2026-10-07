#!/usr/bin/env bash
# hm_lstart_is (bin/hm-lib.sh), A83: a recorded process start time matches when it equals the C form hm_lstart writes now, or the
# caller's-locale form of `ps -o lstart=` that 0.2.0 wrote. It never loosens the pid-reuse check (the same second is still needed), and
# a lock's holder fails toward busy: hm_lock_stale calls a live pid's lock stale only for a record shaped like one of the two forms
# that names another time. Run under en_GB, where ps prints "Tue  6 Oct 18:00:39 2026" and C prints "Tue Oct  6 18:00:39 2026".
# The fr_FR record is HAND-BUILT in fr_FR's shape ("mar.  6 oct. 18:00:39 2026"), which is neither form here.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
LOC=en_GB.UTF-8
locale -a 2>/dev/null | grep -qix "$LOC" || { echo "  SKIP the $LOC locale is not installed: the caller's-locale form cannot be tested here"; exit 0; }
t_setup
export LC_ALL=$LOC
trim() { sed 's/^ *//;s/ *$//'; }
env -u HIVEHOUSE_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
sleep 300 >/dev/null 2>&1 & pold=$!; t_track "$pold"; sleep 2   # started at another second than p
sleep 300 >/dev/null 2>&1 & p=$!; t_track "$p"
C=$(LC_ALL=C /bin/ps -o lstart= -p "$p" | trim); L=$(/bin/ps -o lstart= -p "$p" | trim)
[ "$C" != "$L" ] && ok "(ps prints this time differently under $LOC: $L / $C)" || bad "$LOC prints the same as C: the tests below prove nothing"
OTHER_C="Mon Jan  1 00:00:00 2001"; OTHER_L="Mon  1 Jan 00:00:00 2001"; FR="mar.  6 oct. 18:00:39 2026"

echo "-- hm_lstart_is"
hm_lstart_is "$p" "$C"; assert_status "the C form" $? 0
hm_lstart_is "$p" "$L"; assert_status "the caller's-locale form (what 0.2.0 wrote)" $? 0
hm_lstart_is "$p" "$OTHER_C"; assert_status "another time, C form: pid reuse" $? 1
hm_lstart_is "$p" "$OTHER_L"; assert_status "another time, caller's-locale form: pid reuse" $? 1
hm_lstart_is "$p" "$FR"; assert_status "a form of a third locale" $? 1
hm_lstart_is "$p" ""; assert_status "an empty record" $? 1
hm_lstart_is "" "$C"; assert_status "an empty pid" $? 1
sleep 300 >/dev/null 2>&1 & q=$!; qC=$(LC_ALL=C /bin/ps -o lstart= -p "$q" | trim); qL=$(/bin/ps -o lstart= -p "$q" | trim); kill "$q"; wait "$q" 2>/dev/null
hm_lstart_is "$q" ""; assert_status "a dead pid and an empty record (both read empty)" $? 1
hm_lstart_is "$q" "$qC"; assert_status "a dead pid, C form" $? 1
hm_lstart_is "$q" "$qL"; assert_status "a dead pid, caller's-locale form" $? 1
n=$( (set -x; hm_lstart_is "$p" "$C") 2>&1 | grep -c '/bin/ps -o lstart')
assert_eq "the C form is matched with one ps" "$n" "1"
n=$( (set -x; hm_lstart_is "$p" "$L") 2>&1 | grep -c '/bin/ps -o lstart')
assert_eq "the other form takes a second" "$n" "2"

echo "-- hm_lock_stale: a live pid's lock"
LK="$T_TMP/lock"
rec() { rm -rf "$LK"; mkdir -p "$LK"; jq -nc --argjson pid "$1" --arg l "$2" '{pid:$pid,lstart:$l,created:0}' > "$LK/holder.json"; }
rec "$p" "$C";       hm_lock_stale "$LK"; assert_status "the C form of this process: busy" $? 1
rec "$p" "$L";       hm_lock_stale "$LK"; assert_status "the caller's-locale form of this process (0.2.0's holder): busy" $? 1
rec "$p" "$OTHER_C"; hm_lock_stale "$LK"; assert_status "a C-shaped record of another time: stale (pid reuse)" $? 0
rec "$p" "$OTHER_L"; hm_lock_stale "$LK"; assert_status "a caller's-locale-shaped record of another time: stale (pid reuse)" $? 0
rec "$p" "xyz";      hm_lock_stale "$LK"; assert_status "a record of no known shape: busy" $? 1
rec "$p" "";         hm_lock_stale "$LK"; assert_status "no recorded start time with a live pid: busy" $? 1
echo "-- hm_lstart_fp: the numbers a record holds, whatever its language"
assert_eq "C" "$(hm_lstart_fp "Tue Oct  6 18:00:39 2026")" "18:00:39 2026 6"
assert_eq "en_GB" "$(hm_lstart_fp "Tue  6 Oct 18:00:39 2026")" "18:00:39 2026 6"
assert_eq "fr_FR (hand-built)" "$(hm_lstart_fp "mar.  6 oct. 18:00:39 2026")" "18:00:39 2026 6"
assert_eq "a two-digit day" "$(hm_lstart_fp "Tue Oct 16 08:00:39 2026")" "08:00:39 2026 16"
assert_eq "a leading zero on the day is dropped" "$(hm_lstart_fp "Tue Oct 06 08:00:39 2026")" "08:00:39 2026 6"
for j in "" xyz "Tue Oct  6 2026" "Tue Oct  6 18:00:39" "Tue Oct 18:00:39 2026" "Tue  6 Oct  7 18:00:39 2026" "6 18:00:39 18:00:40 2026" "Tue Oct  6 18:00:39 2026 2027" "mar. 6. oct. 18:00:39 2026"; do
  [ -z "$(hm_lstart_fp "$j")" ] && ok "no fingerprint: [$j]" || bad "a fingerprint from [$j]: $(hm_lstart_fp "$j")"
done
echo "-- hm_lock_stale: a live pid, judged by the numbers, under readers of other languages"
for rd in en_GB.UTF-8 it_IT.UTF-8; do
  locale -a 2>/dev/null | grep -qix "$rd" || { echo "  SKIP the $rd reader: the locale is not installed"; continue; }
  for loc in C en_GB.UTF-8 it_IT.UTF-8 fr_FR.UTF-8; do
    if [ "$loc" != C ] && ! locale -a 2>/dev/null | grep -qix "$loc"; then echo "  SKIP the $loc record: the locale is not installed"; continue; fi
    live=$(LC_ALL=$loc /bin/ps -o lstart= -p "$p" | trim); old=$(LC_ALL=$loc /bin/ps -o lstart= -p "$pold" | trim)
    rec "$p" "$live"; (export LC_ALL=$rd; hm_lock_stale "$LK"); assert_status "a $loc record of the live holder [$live], read under $rd: busy" $? 1
    rec "$p" "$old";  (export LC_ALL=$rd; hm_lock_stale "$LK"); assert_status "a $loc record of another time [$old], read under $rd: stale (pid reuse)" $? 0
  done
  rec "$p" "xyz"; (export LC_ALL=$rd; hm_lock_stale "$LK"); assert_status "junk, read under $rd: busy" $? 1
done
echo "-- hm_lock_stale: a dead pid's lock is stale whatever the record"
for r in "$qC" "$qL" "$FR" "xyz" ""; do rec "$q" "$r"; hm_lock_stale "$LK"; assert_status "dead pid, record [$r]" $? 0; done

echo "-- the holder record: both forms, for a 0.2.0 reader and a 0.3.0 one"
h=$(hm_holder_json "$p")
assert_eq "lstart is the caller's locale, as 0.2.0 reads it" "$(printf '%s' "$h" | jq -r .lstart)" "$L"
assert_eq "lstart_c is C" "$(printf '%s' "$h" | jq -r .lstart_c)" "$C"
assert_eq "a 0.2.0 reader (plain ps in the caller's locale) matches lstart" "$(/bin/ps -o lstart= -p "$p" | trim)" "$(printf '%s' "$h" | jq -r .lstart)"
rm -rf "$LK"; mkdir -p "$LK"; printf '%s\n' "$h" > "$LK/holder.json"
hm_lock_stale "$LK"; assert_status "a record with both fields: busy" $? 1
jq -c 'del(.lstart)' <<< "$h" > "$LK/holder.json"; hm_lock_stale "$LK"; assert_status "lstart_c alone matches: busy" $? 1
jq -c --arg x "$FR" '.lstart = $x' <<< "$h" > "$LK/holder.json"; hm_lock_stale "$LK"; assert_status "lstart of another locale but lstart_c matches: busy" $? 1
jq -c --arg x "$OTHER_C" '.lstart_c = $x' <<< "$h" > "$LK/holder.json"; hm_lock_stale "$LK"; assert_status "lstart_c names another time but lstart matches: busy (either one)" $? 1
jq -c --arg x "$OTHER_C" --arg y "$OTHER_L" '.lstart_c = $x | .lstart = $y' <<< "$h" > "$LK/holder.json"; hm_lock_stale "$LK"; assert_status "both name another time: stale" $? 0
jq -c --arg x "$OTHER_C" --arg y "$OTHER_L" '.lstart_c = $x | .lstart = $y' <<< "$h" > "$LK/holder.json"
hm_lock_release "$LK" "$p"; assert_status "release refuses a record whose two forms both name another time" $? 1
[ -d "$LK" ] && ok "...and leaves the lock" || bad "release removed a lock that was not its own"
rec "$$" "$(/bin/ps -o lstart= -p $$ | trim)"
hm_lock_release "$LK" "$$"; assert_status "release of a 0.2.0-style record (caller's locale only), by its own process" $? 0
rm -rf "$LK"; mkdir -p "$LK"; hm_holder_json "$$" > "$LK/holder.json"
hm_lock_release "$LK" "$$"; assert_status "release of a record both forms" $? 0
rec "$$" "$OTHER_L"; hm_lock_release "$LK" "$$"; assert_status "release refuses a live pid's record of another time" $? 1
rm -rf "$LK"

echo "-- agents and panes recorded under the caller's locale (0.2.0) are still those"
pane=$(hm_tmux list-panes -t keep -F '#{pane_id}' | head -1); ident=$(hm_pane_identity "$HM_TMUX_SOCKET" "$pane"); pp=${ident%%$'\t'*}
ppC=$(LC_ALL=C /bin/ps -o lstart= -p "$pp" | trim); ppL=$(/bin/ps -o lstart= -p "$pp" | trim)
hm_pane_is "$HM_TMUX_SOCKET" "$pane" "$pp" "$ppC"; assert_status "a pane recorded in C" $? 0
hm_pane_is "$HM_TMUX_SOCKET" "$pane" "$pp" "$ppL"; assert_status "a pane recorded in the caller's locale" $? 0
hm_pane_is "$HM_TMUX_SOCKET" "$pane" "$pp" "$FR"; assert_status "a pane recorded in a third locale's form reads as another pane" $? 1
hm_pane_is "$HM_TMUX_SOCKET" "$pane" "$pp" "$OTHER_L"; assert_status "a pane recorded with another time" $? 1
hm_recorded_pane_is "$HM_TMUX_SOCKET" "$pane" "$pp" "$ppL"; assert_status "hm_recorded_pane_is, caller's locale" $? 0
hm_recorded_pane_is "$HM_TMUX_SOCKET" "$pane" "$pp" "$FR"; assert_status "hm_recorded_pane_is, third locale" $? 1
( exec -a claude sleep 300 ) >/dev/null 2>&1 & cl=$!; t_track "$cl"; sleep 0.3
clC=$(LC_ALL=C /bin/ps -o lstart= -p "$cl" | trim); clL=$(/bin/ps -o lstart= -p "$cl" | trim)
hm_claude_is "$cl" "$clC"; assert_status "a Claude recorded in C" $? 0
hm_claude_is "$cl" "$clL"; assert_status "a Claude recorded in the caller's locale" $? 0
hm_claude_is "$cl" "$FR"; assert_status "a Claude recorded in a third locale's form reads as gone" $? 1
R="$T_TMP/proj"; mkdir -p "$R/$T_STATE"
tj() { jq -nc --arg k "$HM_TMUX_SOCKET" --arg p "$pane" --arg pp "$pp" --arg ps "$1" --arg c "$cl" --arg cs "$2" \
  '{agents:[{name:"impl", pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps, claude_pid:$c, claude_started:$cs}]}' > "$R/$T_STATE/team.json"; }
tj "$ppL" "$clL"; hm_team_agent_is "$R" impl; assert_status "an agent recorded by 0.2.0 (caller's locale) is running" $? 0
tj "$ppC" "$clC"; hm_team_agent_is "$R" impl; assert_status "...recorded in C is running" $? 0
tj "$FR" "$FR"; hm_team_agent_is "$R" impl; assert_status "...recorded in a third locale's form reads as stopped" $? 1
t_done
