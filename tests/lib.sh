#!/usr/bin/env bash
# Shared test helpers. Every test runs in its own scratch dirs and its own tmux server.
set -u
HM_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PATH="$HM_REPO_ROOT/tests/bin:$HM_REPO_ROOT/bin:$PATH"   # the fake claude first, so no test can start a real one
FAILS=0
T_TMP=""
# A run's ledger: what it started, so that whatever ends it (an assertion, a signal, a kill) the next teardown can
# finish it. A process is recorded as pid TAB start time, the moment $! names it (the start time is fixed at fork and an
# exec does not move it); it is signalled only while that pid still has that start time, which a recycled pid would
# have to share to the second, and never when it is this shell or above it.
t_lstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }
t_track() {  # t_track <pid>...: record processes the test started
  local p
  for p in "$@"; do printf '%s\t%s\n' "$p" "$(t_lstart "$p")" >> "$T_TMP/run.ledger"; done
}
t_track_group() {  # t_track_group <leader pid>: a process group the test made; teardown kills it while its leader lives
  printf '%s\t%s\n' "$1" "$(t_lstart "$1")" >> "$T_TMP/run.groups"
}
t_outside_tmp() {  # t_outside_tmp -> a fresh dir under /tmp (not under $T_TMP), resolved; teardown removes it
  local d; d=$(mktemp -d /tmp/hmtest-out.XXXXXX) && d=$(cd "$d" && pwd -P) || return 1
  printf '%s\n' "$d" >> "$T_TMP/run.dirs"; printf '%s\n' "$d"
}
t_same() {  # t_same <pid> <recorded start>: 0 when the pid is alive with that start time
  [ -n "$1" ] && [ -n "$2" ] && [ "$(t_lstart "$1")" = "$2" ]
}
t_guard() {  # sets T_ABOVE (this shell and everything above it) and T_OWN_PG (its group): never signalled
  # walked from inside sh while it runs: bash 3.2 has no BASHPID, and a subshell's $$ is its parent's
  T_ABOVE=" $(sh -c 'p=$PPID; while [ -n "$p" ] && [ "$p" -gt 1 ]; do printf "%s " "$p"; p=$(ps -o ppid= -p "$p" | tr -d " "); done') $$ "
  T_OWN_PG=$(set -- $T_ABOVE; ps -o pgid= -p "$1" 2>/dev/null | tr -d ' ')
}
t_reap_groups() {  # t_reap_groups <run dir>: kill -9 each recorded group whose leader is still the one recorded
  local p s
  [ -f "$1/run.groups" ] || return 0
  t_guard
  while IFS=$'\t' read -r p s; do
    case "$T_ABOVE" in *" $p "*) continue ;; esac
    [ "$p" != "$T_OWN_PG" ] && t_same "$p" "$s" && kill -9 -- "-$p" 2>/dev/null
  done < "$1/run.groups"
  return 0
}
t_reap() {  # t_reap <run dir> [first ledger line]: kill -9 each recorded pid that still has its recorded start time
  local p s
  [ -f "$1/run.ledger" ] || return 0
  t_guard
  while IFS=$'\t' read -r p s; do
    case "$T_ABOVE" in *" $p "*) continue ;; esac
    t_same "$p" "$s" && kill -9 "$p" 2>/dev/null
  done < <(tail -n "+${2:-1}" "$1/run.ledger")
  return 0
}
t_remove_dirs() {  # t_remove_dirs <run dir>: the run's t_outside_tmp dirs, each only by the name that helper gives
  local d
  [ -f "$1/run.dirs" ] || return 0
  while IFS= read -r d; do
    case "$d" in /tmp/hmtest-out.??????|/private/tmp/hmtest-out.??????) ;; *) continue ;; esac
    [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] && rm -rf -- "$d"
  done < "$1/run.dirs"
  return 0
}
t_setup() {
  T_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hmtest.XXXXXX")"; T_TMP="$(cd "$T_TMP" && pwd -P)"
  printf '%s\t%s\n' "$$" "$(t_lstart $$)" > "$T_TMP/run.owner"
  export HIVEMIND_HOME="$T_TMP/home"; mkdir -p "$HIVEMIND_HOME"
  export HM_TMUX_SOCKET="$T_TMP/tmux.sock"
  unset HM_PROJECT HM_AGENT TMUX TMUX_PANE
  trap t_teardown EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP   # exit runs the EXIT trap, so a signal tears down too
}
t_teardown() {  # idempotent: called by the trap and by tests that end explicitly
  [ -n "$T_TMP" ] || return 0
  t_reap_groups "$T_TMP"; t_reap "$T_TMP"
  tmux -S "$HM_TMUX_SOCKET" kill-server 2>/dev/null || true
  t_remove_dirs "$T_TMP"
  rm -rf "$T_TMP"; T_TMP=""
}
t_repo() {  # t_repo <name> -> prints path of a fresh git repo with one commit
  local d="$T_TMP/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init
  echo "$d"
}
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
assert_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$3] got [$2]"; fi; }
assert_contains() { case "$2" in *"$3"*) ok "$1";; *) bad "$1: [$2] lacks [$3]";; esac; }
assert_status()   { if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1: exit $2, expected $3"; fi; }
t_done() { t_teardown; [ "$FAILS" -eq 0 ] || exit 1; }
