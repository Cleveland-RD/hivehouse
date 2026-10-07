#!/usr/bin/env bash
# hung_try (bin/hm-hub): what recover does with a hung session whose stop did not take (hm_stop_hung's rc 3). hung_try is loaded from
# the script and hm_stop_hung is replaced by a stand-in that fails and counts its calls: a real process that survives KILL cannot be
# made here. The screen is a REAL capture (tests/fixtures/working/06-working-7s.ansi, "6s"); "frozen for 16 minutes" is HAND-BUILT in the
# state passed in. A stop that did not take is blocked once, and the next beat does not TERM, wait and KILL again (R3 of the review).
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
eval "$(sed -n '/^hung_try() {/,/^}/p' "$HM_REPO_ROOT/bin/hm-hub")"
env -u HIVEHOUSE_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
PANE=$(hm_tmux new-window -d -P -F '#{pane_id}' -t keep: -n w "exec bash -c \"cat '$HM_REPO_ROOT/tests/fixtures/working/06-working-7s.ansi'; exec -a claude sleep 600\""); sleep 1
ident=$(hm_pane_identity "$HM_TMUX_SOCKET" "$PANE"); PID=${ident%%$'\t'*}; STARTED=${ident#*$'\t'}; t_track "$PID"
RJ="$T_TMP/recovery.jsonl"; : > "$RJ"
begin() {  # a beat: its clock, caps and the state last beat saw (the working line unchanged since 16 minutes ago)
  now=$(date +%s); since=$((now - 86400)); starts=0; max=10; rjf="$RJ"; newhs='{}'; newrec=""; actions='[]'; blocked='[]'
  hstates=$(jq -nc --arg p "$PID" --arg s "$STARTED" --argjson t "$((now - 960))" '{"beta/impl": {pid:$p, started:$s, secs:6, since:$t}}')
}
CALLS=0; RC=3
hm_stop_hung() { CALLS=$((CALLS + 1)); return "$RC"; }
begin; hung_try beta agent impl tk "$HM_TMUX_SOCKET" "$PANE" "$PID" "$STARTED"
assert_eq "a stop that did not take is tried once" "$CALLS" "1"
assert_eq "...nothing was restarted" "$HUNG_STOPPED$(printf '%s' "$actions" | jq -r 'length')" "00"
assert_eq "...it is blocked, for the owner" "$(printf '%s' "$blocked" | jq -r '[.[] | select(.action == "restart")][0].agents | join(",")')" "impl"
assert_contains "...saying it did not stop" "$(printf '%s' "$blocked" | jq -r '.[0].reason')" "did not stop when asked"
assert_eq "...and recorded, against the session" "$(printf '%s' "$newrec" | jq -s -r '[.[] | select(.action == "blocked-stop" and .item == "beta/impl")] | length')" "1"
printf '%s' "$newrec" >> "$RJ"
begin; hung_try beta agent impl tk "$HM_TMUX_SOCKET" "$PANE" "$PID" "$STARTED"
assert_eq "the next beat does not try it again" "$CALLS" "1"
assert_eq "...and says nothing new" "$(printf '%s' "$blocked" | jq -r 'length')$(printf '%s' "$newrec" | grep -c .)" "00"
: > "$RJ"; jq -nc --argjson e "$(( $(date +%s) - 90000 ))" '{epoch:$e, action:"blocked-stop", item:"beta/impl"}' >> "$RJ"
begin; hung_try beta agent impl tk "$HM_TMUX_SOCKET" "$PANE" "$PID" "$STARTED"
assert_eq "after 24 hours it is tried again" "$CALLS" "2"
t_done
