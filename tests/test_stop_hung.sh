#!/usr/bin/env bash
# hm_stop_hung (bin/hm-lib.sh): the one place hivemind stops a process it did not just start, for a session whose working line
# has not moved (Phase 4.3, A10). It stops the recorded pid only while that pid still has its recorded start time, is still
# Claude, and its pane still shows the same working line; TERM, up to 10 s, then KILL only the same process. The frozen screen is
# a REAL capture (tests/fixtures/working/06-working-7s.ansi, "6s") drawn in a tmux pane; the "frozen for 15 minutes" is the hung
# state in test_away.sh, so a still screen here stands for it. The processes are `sleep` run under the name claude.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
W="$HM_REPO_ROOT/tests/fixtures/working"; D="$HM_REPO_ROOT/tests/fixtures/dialogs"
env -u HIVEMIND_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
# frozen <fixture> [trap]: a pane that draws the capture, then is a process named claude (TERM ignored when trap is given); sets PANE, PID, STARTED
frozen() {
  local pre=""; [ "${2:-}" = trap ] && pre="trap '' TERM; "
  PANE=$(hm_tmux new-window -d -P -F '#{pane_id}' -t keep: -n w "exec bash -c \"cat '$1'; ${pre}exec -a claude sleep 600\""); sleep 1
  local ident; ident=$(hm_pane_identity "$HM_TMUX_SOCKET" "$PANE"); PID=${ident%%$'\t'*}; STARTED=${ident#*$'\t'}
  t_track "$PID"
}
alive() { hm_alive "$1" && [ "$(hm_lstart "$1")" = "$2" ]; }

frozen "$W/06-working-7s.ansi"
assert_eq "the fixture pane reads as working, 6s" "$(hm_pane_text "$PANE" "$HM_TMUX_SOCKET" | hm_pane_working_seconds)" "6"
echo "-- the checks before TERM: nothing is sent when one fails"
hm_stop_hung "$PID" "Mon Jan  1 00:00:00 2001" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "another start time (a reused pid)" $? 1
alive "$PID" "$STARTED" && ok "...the process is untouched" || bad "a process with another start time was stopped"
hm_stop_hung "$PID" "$STARTED" "$HM_TMUX_SOCKET" "$PANE" 5; assert_status "the screen moved since it was read (5s read, 6s now)" $? 2
alive "$PID" "$STARTED" && ok "...the process is untouched" || bad "a session whose screen moved was stopped"
sv=("$PANE" "$PID" "$STARTED"); frozen "$D/07-idle-after-answer.ansi"; ip=$PANE; ipid=$PID; istart=$STARTED; PANE=${sv[0]}; PID=${sv[1]}; STARTED=${sv[2]}
hm_stop_hung "$ipid" "$istart" "$HM_TMUX_SOCKET" "$ip" 6; assert_status "a pane that shows no working line is unknown" $? 2
alive "$ipid" "$istart" && ok "...the process is untouched" || bad "an unknown screen was stopped"
sleep 600 >/dev/null 2>&1 & sl=$!; t_track "$sl"; sls=$(hm_lstart "$sl")
hm_stop_hung "$sl" "$sls" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "a process that is not Claude" $? 1
alive "$sl" "$sls" && ok "...is never stopped" || bad "a process that is not Claude was stopped"
hm_stop_hung "$$" "$(hm_lstart "$$")" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "this shell" $? 1
# the caller's own Claude (the hub's, in production): a bash named claude runs the stop on its own pid, and on its own parent's
out=$(exec -a claude bash -c ". '$HM_REPO_ROOT/bin/hm-lib.sh'; export HM_TMUX_SOCKET='$HM_TMUX_SOCKET'; hm_stop_hung \$\$ \"\$(hm_lstart \$\$)\" '$HM_TMUX_SOCKET' '$PANE' 6; echo rc=\$?; echo alive"); 
assert_eq "the Claude that is running the stop is never stopped" "$out" "$(printf 'rc=1\nalive')"
hm_stop_hung 1 "$(hm_lstart 1)" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "pid 1" $? 1
hm_stop_hung "" "" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "an empty record" $? 1
hm_stop_hung "$PID" "$STARTED" "$HM_TMUX_SOCKET" "$PANE" six; assert_status "a seconds value that is not a number" $? 1
alive "$PID" "$STARTED" && ok "...nothing was stopped by any of these" || bad "a refused stop still stopped it"

echo "-- TERM, then wait, then KILL only the same process"
t0=$(date +%s); hm_stop_hung "$PID" "$STARTED" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "a hung session that ends on TERM" $? 0
t1=$(date +%s)
alive "$PID" "$STARTED" && bad "it is still alive" || ok "...is gone"
[ $((t1 - t0)) -le 4 ] && ok "...without waiting out the 10 s" || bad "waited $((t1 - t0)) s for a process that ends on TERM"
frozen "$W/06-working-7s.ansi" trap
t0=$(date +%s); hm_stop_hung "$PID" "$STARTED" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "one that ignores TERM" $? 0
t1=$(date +%s)
alive "$PID" "$STARTED" && bad "it survived" || ok "...is killed"
[ $((t1 - t0)) -ge 10 ] && ok "...after the 10 s wait" || bad "killed after only $((t1 - t0)) s"
# the Claude must be the pane's own process or run under it: a screen read from one pane never stops another live Claude
frozen "$W/06-working-7s.ansi"
( exec -a claude sleep 600 ) >/dev/null 2>&1 & OTH=$!; t_track "$OTH"; sleep 0.3; OTHS=$(hm_lstart "$OTH")
hm_stop_hung "$OTH" "$OTHS" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "a Claude that is not under the pane whose screen was read" $? 1
alive "$OTH" "$OTHS" && ok "...is left running" || bad "a Claude that is not under the pane was stopped"
printf 'cat "$1"; (exec -a claude sleep 600) & echo $! > "$2"; wait; exec sleep 600\n' > "$T_TMP/orch.sh"
OP=$(hm_tmux new-window -d -P -F '#{pane_id}' -t keep: -n o "exec bash '$T_TMP/orch.sh' '$W/06-working-7s.ansi' '$T_TMP/oc.pid'"); sleep 1
OCP=$(cat "$T_TMP/oc.pid"); t_track "$OCP"; OCS=$(hm_lstart "$OCP")
hm_stop_hung "$OCP" "$OCS" "$HM_TMUX_SOCKET" "$OP" 6; assert_status "a Claude running under the pane's shell (a --self orchestrator)" $? 0
alive "$OCP" "$OCS" && bad "it is still alive" || ok "...is stopped"
hm_stop_hung "$PID" "$STARTED" "$HM_TMUX_SOCKET" "%99999" 6; assert_status "a pane that is not there" $? 1
alive "$PID" "$STARTED" && ok "...stops nothing" || bad "a process was stopped for a pane that is not there"
# rc 3: a stop that does not take. kill is a function that does nothing, so TERM and KILL both leave the process running
kill() { :; }
t0=$(date +%s); hm_stop_hung "$PID" "$STARTED" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "still running after TERM, the wait and KILL" $? 3
t1=$(date +%s); [ $((t1 - t0)) -ge 10 ] && ok "...after the 10 s wait" || bad "gave up after $((t1 - t0)) s"
unset -f kill
kill -9 "$PID" 2>/dev/null
# A83: a start time 0.2.0 recorded, in the caller's locale, is still that process's
if locale -a 2>/dev/null | grep -qix en_GB.UTF-8; then
  frozen "$W/06-working-7s.ansi"
  loc=$(LC_ALL=en_GB.UTF-8 /bin/ps -o lstart= -p "$PID" | sed 's/^ *//;s/ *$//')
  [ "$loc" != "$STARTED" ] && ok "(en_GB prints this start time differently: $loc / $STARTED)" || bad "en_GB prints the same as C: the next check proves nothing"
  kill() { :; }
  LC_ALL=en_GB.UTF-8 hm_stop_hung "$PID" "$loc" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "a record in the caller's locale: still running after KILL is rc 3" $? 3
  unset -f kill
  LC_ALL=en_GB.UTF-8 hm_stop_hung "$PID" "$loc" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "a record in the caller's locale is stopped" $? 0
  alive "$PID" "$STARTED" && bad "it is still alive" || ok "...it is gone"
else echo "  SKIP the en_GB.UTF-8 locale is not installed"; fi
# a pid that is another process by the time of the KILL is not killed: hm_claude_is is replaced by one that says the process
# changed from its second call on (a pid reused during the wait, which a stand-in cannot force); the process ignores TERM
frozen "$W/06-working-7s.ansi" trap
eval "real_$(declare -f hm_claude_is)"; CALLS=0
hm_claude_is() { CALLS=$((CALLS + 1)); [ "$CALLS" -lt 2 ] && real_hm_claude_is "$@"; }
hm_stop_hung "$PID" "$STARTED" "$HM_TMUX_SOCKET" "$PANE" 6; assert_status "the pid is no longer the recorded process at the KILL" $? 0
alive "$PID" "$STARTED" && ok "...it is not killed" || bad "a process that was no longer the recorded one was killed"
hm_claude_is() { real_hm_claude_is "$@"; }
kill -9 "$PID" 2>/dev/null
t_done
