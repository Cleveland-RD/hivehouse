#!/usr/bin/env bash
# Shared test helpers. Every test runs in its own scratch dirs and its own tmux server.
set -u
HH_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# PATH: the fake claude first, so no test can start a real one; then this repo's bin; then the caller's PATH without any other plugin's
# bin/ (an entry whose parent holds .claude-plugin/plugin.json), so a suite started from a session that has another generation of
# these tools on its PATH can never reach them by a name this repo's bin does not shadow (the 7 Oct leak). By identity, not by name.
t_path_without_foreign_plugins() {
  local e r out="" IFS=:
  for e in $PATH; do
    [ -n "$e" ] || continue
    if [ -f "$e/../.claude-plugin/plugin.json" ]; then r=$(cd "$e" 2>/dev/null && pwd -P); [ "$r" = "$HH_REPO_ROOT/bin" ] || continue; fi
    out="${out:+$out:}$e"
  done
  printf '%s\n' "$out"
}
export PATH="$HH_REPO_ROOT/tests/bin:$HH_REPO_ROOT/bin:$(t_path_without_foreign_plugins)"
# The names, stated here for every test and spelled in no other test (tests/test_names.sh holds it to that). They are written out,
# not read from bin/, so that a name changed there alone fails the tests. The plugin's name is read from plugin.json, the one
# place it lives.
T_STATE='.hivehouse'                       # a project's state folder
T_HUB='.hivehouse-hub'                     # the hub's folder
T_HOMEDIR='.hivehouse'                     # the per-user home, under $HOME
T_CUSTOM='custom'                           # the override folder, under a project's state folder and under the per-user home
T_MAC_BASE='/Library/Application Support/hivehouse'   # the delegate files' folder, and the machine slot's, on macOS
T_LINUX_BASE='/etc/hivehouse'              # the delegate files' folder on Linux
T_LINUX_SLOT='/var/lib/hivehouse/slot'     # the machine slot on Linux
T_DELEGATE_TAG='hivehouse-delegate'        # the delegate file's first word
T_DELEGATE_LINE1="$T_DELEGATE_TAG 1"        # a version 1 file's first line (0.5.0 wrote it; still read)
T_DELEGATE_LINE2="$T_DELEGATE_TAG 2"        # a version 2 file's first line (0.5.1 wrote it; still read)
T_DELEGATE_LINE3="$T_DELEGATE_TAG 3"        # a version 3 file's first line (0.5.2 wrote it; still read)
T_DELEGATE_LINE4="$T_DELEGATE_TAG 4"        # a version 4 file's first line (0.5.4 writes it: adds peers=)
T_PEER_LOG='peers.jsonl'                  # the hub's audit log of sends to peers, in its folder
T_PREFIX='hivehouse'                       # what a message begins with: "<prefix>: ..."
T_PANE='hivehouse-hub'                     # the hub screen's pane
T_PLUGIN=$(jq -r .name "$HH_REPO_ROOT/.claude-plugin/plugin.json")
T_WINDOW=1000000                           # the one default context window (tokens): Claude Code's own
FAILS=0
T_TMP=""
# A run's ledger: what it started, so that whatever ends it (an assertion, a signal, a kill) the next teardown can
# finish it. A process is recorded as pid TAB start time, the moment $! names it (the start time is fixed at fork and an
# exec does not move it); it is signalled only while that pid still has that start time, which a recycled pid would
# have to share to the second, and never when it is this shell or above it.
t_lstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }   # hh_lstart's reading: the reaper shares no code with what it tests
t_track() {  # t_track <pid>...: record processes the test started
  local p
  for p in "$@"; do printf '%s\t%s\n' "$p" "$(t_lstart "$p")" >> "$T_TMP/run.ledger"; done
}
t_track_group() {  # t_track_group <leader pid>: a process group the test made; teardown kills it while its leader lives
  printf '%s\t%s\n' "$1" "$(t_lstart "$1")" >> "$T_TMP/run.groups"
}
t_outside_tmp() {  # t_outside_tmp -> a fresh dir under /tmp (not under $T_TMP), resolved; teardown removes it
  local d; d=$(mktemp -d /tmp/hhtest-out.XXXXXX) && d=$(cd "$d" && pwd -P) || return 1
  printf '%s\n' "$d" >> "$T_TMP/run.dirs"; printf '%s\n' "$d"
}
# The start time ps prints is written in the language of the caller's locale ("Thu Oct  8 ..." in C, "Thu  8 Oct ..." in en_GB, "jeu.  8 oct. ..."
# in fr_FR), and a run is judged by a later run that may use another one: comparing the text would sweep a live run (KI-28). A start time is
# reduced to the numbers every language shares, its HH:MM:SS, its year and its day, and the pid's own start time is read in C. The same
# reduction as hh_lstart_fp in bin/hh-lib.sh, written out here so that the reaper still shares no code with what it tests.
t_lstart_fp() {  # t_lstart_fp <start time text>: "HH:MM:SS YYYY D", or nothing when it does not hold exactly one of each
  local w t="" y="" d="" nt=0 ny=0 nd=0 ws
  IFS=' ' read -r -a ws <<< "$1"
  for w in ${ws[@]+"${ws[@]}"}; do
    case "$w" in
      [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) t=$w; nt=$((nt + 1)) ;;
      [0-9][0-9][0-9][0-9]) y=$w; ny=$((ny + 1)) ;;
      [0-9]|[0-9][0-9]) d=$((10#$w)); nd=$((nd + 1)) ;;
    esac
  done
  [ "$nt" = 1 ] && [ "$ny" = 1 ] && [ "$nd" = 1 ] && printf '%s %s %s\n' "$t" "$y" "$d"
}
t_same() {  # t_same <pid> <recorded start>: 0 when the pid is alive with that start time, in whatever language it was recorded
  local rec now
  [ -n "$1" ] && [ -n "$2" ] || return 1
  now=$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'); [ -n "$now" ] || return 1
  [ "$now" = "$2" ] && return 0
  rec=$(t_lstart_fp "$2"); [ -n "$rec" ] && [ "$rec" = "$(t_lstart_fp "$now")" ]
}
t_guard() {  # sets T_ABOVE (this shell and everything above it) and T_OWN_PG (its group): never signalled
  # read from inside sh while it runs (bash 3.2 has no BASHPID, and a subshell's $$ is its parent's): sh's parent is this
  # shell, or the command substitution's child of it, which is in this shell's group and is gone once sh returns
  local r
  r=$(sh -c 'p=$PPID; ps -o pgid= -p "$p" | tr -d " "; while [ -n "$p" ] && [ "$p" -gt 1 ]; do printf "%s " "$p"; p=$(ps -o ppid= -p "$p" | tr -d " "); done')
  T_OWN_PG=${r%%$'\n'*}; T_ABOVE=" ${r#*$'\n'} $$ "
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
    case "$d" in /tmp/hhtest-out.??????|/private/tmp/hhtest-out.??????) ;; *) continue ;; esac
    [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] && rm -rf -- "$d"
  done < "$1/run.dirs"
  return 0
}
t_sweep_stale() {  # a run killed outright ran no teardown: the next t_setup finishes it, from what it recorded alone
  local d p s
  for d in "${TMPDIR:-/tmp}"/hhtest.*; do
    # a dir with no owner record (an older run, or one still being set up) or one not ours is never touched
    [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] && [ -f "$d/run.owner" ] || continue
    IFS=$'\t' read -r p s < "$d/run.owner" || continue
    [ -n "$p" ] && [ -n "$s" ] || continue      # an owner it cannot judge is treated as alive
    t_same "$p" "$s" && continue                # its test is still running
    t_reap "$d"                                 # by recorded pid and start time only: no group, no pattern
    [ -S "$d/tmux.sock" ] && tmux -S "$d/tmux.sock" kill-server 2>/dev/null
    t_remove_dirs "$d"
    rm -rf -- "$d" && echo "  (finished a stopped run's leftovers: $d)" >&2
  done
  return 0
}
# The run's environment is an allowlist: everything else the caller exported is unset, so no variable of any plugin or tool (this one's
# own, an earlier generation's, a Git or Claude Code one) reaches a test, whatever prefix it has. What is kept: the user and shell
# basics, a locale, the timezone, the PATH built above, and the opt-in switch of the one test that signals real processes.
t_allowlist_env() {
  local v
  for v in $(compgen -e); do
    case "$v" in
      HOME|PATH|USER|LOGNAME|SHELL|TERM|TMPDIR|TZ|LANG|LC_*|PWD|OLDPWD|SHLVL|_|HH_CLEANUP_TEST) ;;
      *) unset "$v" ;;
    esac
  done
}
# The test tmux server's socket is <TMPDIR>/hhtest.XXXXXX/tmux.sock, and a unix socket path holds at most 103 characters on macOS: past
# that no tmux server starts and the hub, spawn and rotate tests fail as "unknown" or exit 2 with nothing wrong in the code (KI-30).
t_check_socket_path() {
  local base n
  base=$(cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || base=${TMPDIR:-/tmp}
  n=$(( ${#base} + ${#T_SOCKET_TAIL} ))
  if [ "$n" -gt 103 ]; then
    echo "tests: TMPDIR is too long: the test tmux socket would be $n characters ($base$T_SOCKET_TAIL), over the 103 a socket path may have. Set a shorter one: at most 79 characters once resolved (/tmp is /private/tmp, 12), for example mkdir -p /tmp/hh-test && TMPDIR=/tmp/hh-test" >&2
    exit 2
  fi
}
T_SOCKET_TAIL="/hhtest.XXXXXX/tmux.sock"
t_setup() {
  t_allowlist_env
  t_sweep_stale
  t_check_socket_path
  T_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hhtest.XXXXXX")"; T_TMP="$(cd "$T_TMP" && pwd -P)"
  printf '%s\t%s\n' "$$" "$(t_lstart $$)" > "$T_TMP/run.owner"
  export HIVEHOUSE_HOME="$T_TMP/home"; mkdir -p "$HIVEHOUSE_HOME"
  export HH_TMUX_SOCKET="$T_TMP/tmux.sock"
  # Claude Code's settings are the run's own, never the machine's: the user's, through CLAUDE_CONFIG_DIR, and managed
  export CLAUDE_CONFIG_DIR="$T_TMP/claude-config" HH_MANAGED_SETTINGS="$T_TMP/managed-settings.json"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export HH_SLOT_LOCAL=1   # no test meets the machine's real slot folder
  trap t_teardown EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP   # exit runs the EXIT trap, so a signal tears down too
}
t_teardown() {  # idempotent: called by the trap and by tests that end explicitly
  [ -n "$T_TMP" ] || return 0
  t_reap_groups "$T_TMP"; t_reap "$T_TMP"
  tmux -S "$HH_TMUX_SOCKET" kill-server 2>/dev/null || true
  t_remove_dirs "$T_TMP"
  rm -rf "$T_TMP"; T_TMP=""
}
t_plugin_beside() {  # t_plugin_beside <a copy of bin/>: plugin.json where bin/hh-lib.sh looks for it, one folder up (hh_plugin_name)
  mkdir -p "$1/../.claude-plugin" && cp "$HH_REPO_ROOT/.claude-plugin/plugin.json" "$1/../.claude-plugin/plugin.json"
}
# t_run_printed <lines>: runs each command line a tool printed for an administrator (sudo lines) or for the owner, as this user: sudo
# dropped and root:<group> read as this user and group, so a line that BSD chmod, chown or mkdir cannot read (an option after its
# argument, say) fails here as it would on the owner's Mac. Prints each line that failed with its error and returns their count.
t_run_printed() {
  local line n=0 me; me="$(id -un):$(id -gn)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line=$(printf '%s' "$line" | sed -e 's/sudo //g' -e "s/root:[A-Za-z0-9_-]*/$me/g")
    bash -c "$line" >/dev/null 2>"$T_TMP/printed.err" || { printf 'FAILED: %s: %s\n' "$line" "$(cat "$T_TMP/printed.err")" >&2; n=$((n + 1)); }
  done <<< "$1"
  return "$n"
}
t_repo() {  # t_repo <name> -> prints path of a fresh git repo with one commit
  local d="$T_TMP/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init
  echo "$d"
}
# t_delegate_bin <delegate file>: a scratch copy of bin/ in which the one production line that names the delegate file and
# its required owner reads <delegate file> as this user instead, so the executables can be tested with a fixture. The
# line is replaced only if it is found exactly once; production has no override of its own. Prints the copy's folder.
t_delegate_bin() {
  local d="$T_TMP/delegate-bin" n
  rm -rf "$d"; mkdir -p "$d"; cp -R "$HH_REPO_ROOT/bin/." "$d/"; t_plugin_beside "$d"
  n=$(grep -c '^hh_delegate_now() { hh_delegate_read "$(hh_delegate_path)" 0; }$' "$d/hh-lib.sh")
  [ "$n" = 1 ] || { echo "t_delegate_bin: the production line matched $n times" >&2; return 1; }
  awk -v f="$1" -v u="$(id -u)" '/^hh_delegate_now\(\) \{ hh_delegate_read / { print "hh_delegate_now() { hh_delegate_read \"" f "\" " u "; }"; next } { print }' "$d/hh-lib.sh" > "$d/hh-lib.sh.new" && mv "$d/hh-lib.sh.new" "$d/hh-lib.sh"
  printf '%s\n' "$d"
}
# t_slot_bin <machine slot folder> [<owner uid>]: a scratch copy of bin/ in which the two one-line functions that name the machine's
# slot folder and the uid that must own it name a fixture and this user (or <owner uid>) instead. Each line is replaced only if
# it is found exactly once; production has no override of its own. Prints the copy's folder.
t_slot_bin() {
  local d n; d=$(mktemp -d "$T_TMP/slot-bin.XXXXXX") || return 1
  rm -rf "$d"; mkdir -p "$d"; cp -R "$HH_REPO_ROOT/bin/." "$d/"; t_plugin_beside "$d"
  for n in 'hh_machine_slot_dir() { if ' 'hh_machine_slot_owner() { echo 0; }'; do
    [ "$(grep -c -F -- "$n" "$d/hh-lib.sh")" = 1 ] || { echo "t_slot_bin: the production line '$n' did not match once" >&2; return 1; }
  done
  awk -v f="$1" -v u="${2:-$(id -u)}" '/^hh_machine_slot_dir\(\) \{ if / { print "hh_machine_slot_dir() { echo \047" f "\047; }"; next }
    /^hh_machine_slot_owner\(\) \{ echo 0; \}$/ { print "hh_machine_slot_owner() { echo " u "; }"; next } { print }' "$d/hh-lib.sh" > "$d/hh-lib.sh.new" && mv "$d/hh-lib.sh.new" "$d/hh-lib.sh"
  printf '%s\n' "$d"
}
# t_base_bin <folder name> <base>: a scratch copy of bin/ in which the one line that names the folder of the delegate files gives <base>
# instead, so the lines `hh-hub away` and `back` print can be tested against a folder the test controls. Found exactly once. Prints the copy.
t_base_bin() {
  local d="$T_TMP/$1" n
  rm -rf "$d"; mkdir -p "$d"; cp -R "$HH_REPO_ROOT/bin/." "$d/"; t_plugin_beside "$d"
  n=$(grep -c '^hh_delegate_base() { if ' "$d/hh-lib.sh")
  [ "$n" = 1 ] || { echo "t_base_bin: the production line matched $n times" >&2; return 1; }
  awk -v b="$2" '/^hh_delegate_base\(\) \{ if / { print "hh_delegate_base() { echo \"" b "\"; }"; next } { print }' "$d/hh-lib.sh" > "$d/hh-lib.sh.new" && mv "$d/hh-lib.sh.new" "$d/hh-lib.sh"
  printf '%s\n' "$d"
}
# t_jq_bin <folder name> <candidates>: a scratch copy of bin/ in which the one line that lists where a root-owned jq may be found lists
# <candidates> (space-separated paths) instead, so the resolver can be tested with paths the test controls. Found exactly once.
t_jq_bin() {
  local d="$T_TMP/$1" n
  rm -rf "$d"; mkdir -p "$d"; cp -R "$HH_REPO_ROOT/bin/." "$d/"; t_plugin_beside "$d"
  n=$(grep -c '^hh_jq_candidates() { echo ' "$d/hh-lib.sh")
  [ "$n" = 1 ] || { echo "t_jq_bin: the production line matched $n times" >&2; return 1; }
  awk -v c="$2" '/^hh_jq_candidates\(\) \{ echo / { print "hh_jq_candidates() { echo \"" c "\"; }"; next } { print }' "$d/hh-lib.sh" > "$d/hh-lib.sh.new" && mv "$d/hh-lib.sh.new" "$d/hh-lib.sh"
  printf '%s\n' "$d"
}
# t_env_probe <NAME=value>: starts a process launched with that variable and prints its pid. macOS shows no environment for
# Apple platform binaries (sleep, bash) in ps -E, so a non-platform one (node) is used; prints nothing, and fails, when only
# platform binaries are found.
t_env_probe() {  # t_env_probe <NAME=value> [argument]...: the arguments become the process's own arguments
  local n v="$1"; shift; n=$(command -v node) || return 1
  if command -v codesign >/dev/null 2>&1 && codesign -dv "$n" 2>&1 | grep -q 'Platform identifier'; then return 1; fi
  ( env "$v" "$n" -e 'setTimeout(() => {}, 60000)' "$@" >/dev/null 2>&1 & echo $! )
}
# t_node_claude <cwd> [<hh-hub to register the hub with>]: a node script named claude, which runs its arguments as a command in <cwd>
# (after `hh-hub self --name hub`, when a hh-hub is given), with this test's environment as defaults under whatever the launch gives
# it. Launched as `[VAR=x] node <script> <command>...`, it is a Claude whose launch environment ps -E can show. Prints its path.
t_node_claude() {
  local d e; d=$(mktemp -d "$T_TMP/ncl.XXXXXX")
  e=$(jq -nc --arg PATH "$PATH" --arg HOME "$HOME" --arg HIVEHOUSE_HOME "${HIVEHOUSE_HOME:-}" --arg HH_TMUX_SOCKET "${HH_TMUX_SOCKET:-}" --arg CLAUDE_CONFIG_DIR "${CLAUDE_CONFIG_DIR:-}" --arg HH_MANAGED_SETTINGS "${HH_MANAGED_SETTINGS:-}" '$ARGS.named')
  if [ -n "${2:-}" ]; then
    printf 'const { spawnSync } = require("child_process")\nconst env = Object.assign({}, %s, process.env)\nspawnSync(%s, ["self", "--name", "hub"], { cwd: %s, stdio: "ignore", env })\nconst r = spawnSync(process.argv[2], process.argv.slice(3), { cwd: %s, stdio: "inherit", env })\nprocess.exit(r.status === null ? 1 : r.status)\n' "$e" "\"$2\"" "\"$1\"" "\"$1\"" > "$d/claude"
  else
    printf 'const { spawnSync } = require("child_process")\nconst env = Object.assign({}, %s, process.env)\nconst r = spawnSync(process.argv[2], process.argv.slice(3), { cwd: %s, stdio: "inherit", env })\nprocess.exit(r.status === null ? 1 : r.status)\n' "$e" "\"$1\"" > "$d/claude"
  fi
  printf '%s\n' "$d/claude"
}
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
assert_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$3] got [$2]"; fi; }
assert_contains() { case "$2" in *"$3"*) ok "$1";; *) bad "$1: [$2] lacks [$3]";; esac; }
assert_status()   { if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1: exit $2, expected $3"; fi; }
t_done() { t_teardown; [ "$FAILS" -eq 0 ] || exit 1; }
