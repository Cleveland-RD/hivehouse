#!/usr/bin/env bash
# Shared by every hm-* executable. bash 3.2 compatible. Never reads plugin variables: settings arrive as arguments
# or HM_* environment set by hm-spawn.
# A command substitution does not stop its caller: write x=$(hm_project_root) || exit $?, never a bare x=$(...).
hm_die()  { echo "hivemind: $2" >&2; exit "$1"; }
hm_home() { printf '%s\n' "${HIVEMIND_HOME:-$HOME/.hivemind}"; }
hm_now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
hm_project_root() {
  if [ -n "${HM_PROJECT:-}" ]; then
    [ -d "$HM_PROJECT" ] || hm_die 2 "HM_PROJECT is not a directory: $HM_PROJECT"
    (cd "$HM_PROJECT" && pwd -P); return
  fi
  local common; common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || hm_die 2 "not inside a git repository and HM_PROJECT is not set"
  case "$common" in */.git) (cd "${common%/.git}" && pwd -P) ;; *) hm_die 2 "unsupported repository layout: $common" ;; esac
}
hm_project_key() {  # basename plus a short hash of the full path: webapp and webapp-impl never clash
  local p="$1"; printf '%s-%s\n' "$(basename "$p")" "$(printf '%s' "$p" | shasum | cut -c1-6)"
}
hm_state() { local root; root=$(hm_project_root) || exit $?; printf '%s/.hivemind\n' "$root"; }
hm_ensure_state() {  # creates .hivemind/, excludes it through info/exclude, refuses if any of it is tracked
  local root common excl
  root=$(hm_project_root) || exit $?
  common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir) || exit $?
  if [ -n "$(git -C "$root" ls-files -- .hivemind)" ]; then
    hm_die 3 "files under .hivemind/ are tracked by git; untrack them before using hivemind here"
  fi
  mkdir -p "$root/.hivemind" "$common/info"
  excl="$common/info/exclude"; touch "$excl"
  grep -qx '/.hivemind/' "$excl" || echo '/.hivemind/' >> "$excl"
}
hm_json_get() { jq -r "$2 // empty" "$1" 2>/dev/null; }   # hm_json_get <file> <jq path>
hm_registry_dir() { printf '%s/registry/panes\n' "$(hm_home)"; }
hm_pane_key() {  # hm_pane_key <socket> <pane id> -> filename-safe key
  printf '%s' "$1|$2" | shasum | cut -c1-16
}
hm_tmux() { if [ -n "${HM_TMUX_SOCKET:-}" ]; then tmux -S "$HM_TMUX_SOCKET" "$@"; else tmux "$@"; fi; }
hm_socket() { if [ -n "${HM_TMUX_SOCKET:-}" ]; then echo "$HM_TMUX_SOCKET"; else tmux display -p '#{socket_path}'; fi; }
