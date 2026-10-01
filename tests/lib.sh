#!/usr/bin/env bash
# Shared test helpers. Every test runs in its own scratch dirs and its own tmux server.
set -u
HM_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PATH="$HM_REPO_ROOT/tests/bin:$HM_REPO_ROOT/bin:$PATH"   # the fake claude first, so no test can start a real one
FAILS=0
T_TMP=""
t_setup() {
  T_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hmtest.XXXXXX")"; T_TMP="$(cd "$T_TMP" && pwd -P)"
  export HIVEMIND_HOME="$T_TMP/home"; mkdir -p "$HIVEMIND_HOME"
  export HM_TMUX_SOCKET="$T_TMP/tmux.sock"
  unset HM_PROJECT HM_AGENT TMUX TMUX_PANE
  trap t_teardown EXIT
}
t_teardown() {  # idempotent: called by the trap and by tests that end explicitly
  [ -n "$T_TMP" ] || return 0
  tmux -S "$HM_TMUX_SOCKET" kill-server 2>/dev/null || true
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
