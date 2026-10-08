#!/usr/bin/env bash
# The hub in tmux: hh-hub start opens (or reattaches to) a tmux session named after the hub, and the hub records its own pane.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P)
hub() { (cd "$H" && hh-hub "$@"); }
P="$H/$T_HUB"
sessions() { hh_tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -cx "$1"; }
paneof() { hh_tmux list-panes -t "=$1" -F '#{pane_id}' | head -1; }
screen() { hh_tmux capture-pane -p -J -S - -t "$(paneof "$1")"; }
setfake() { hh_tmux set-environment -g HH_FAKE_CLAUDE "$1"; }
unsetfake() { hh_tmux set-environment -g -u HH_FAKE_CLAUDE; }
waitfor() {  # waitfor <session> <text>: the pane shows it within 10 s
  local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do screen "$1" 2>/dev/null | grep -qF -- "$2" && return 0; sleep 0.5; done; return 1
}

hub start >/dev/null 2>&1; assert_status "start with no hub here" $? 2
hub init >/dev/null

# ---- start: the hub in a tmux session named after it ----
setfake idle
hh_tmux set-environment -g HH_AWAY_BYPASS 1; hh_tmux set-environment -g HH_AWAY_HUB "$T_TMP"   # a server first started by a marked caller carries the marker
out=$(hub start 2>&1); assert_status "start" $? 0
unsetfake; hh_tmux set-environment -g -u HH_AWAY_BYPASS; hh_tmux set-environment -g -u HH_AWAY_HUB
assert_eq "...one tmux session, named after the hub" "$(sessions hub)" "1"
waitfor hub "ARGV: /$T_PLUGIN:hub"; assert_status "...running claude for the hub" $? 0
assert_contains "...named" "$(screen hub)" "ARGV: hub"
assert_contains "...in the work folder" "$(hh_tmux display-message -p -t "$(paneof hub)" '#{pane_current_path}')" "$H"
assert_contains "...with the hub's folder as its project, for custom/" "$(screen hub)" "HH_PROJECT=$H"
assert_contains "...and not away: no marker, whatever the tmux server carries" "$(screen hub)" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
assert_contains "...it says how to attach (no terminal here to attach)" "$out" "tmux -S $HH_TMUX_SOCKET attach -t hub"
hub name lead >/dev/null; setfake idle; hub start >/dev/null 2>&1; assert_status "a hub named by its folder gets a session of that name" $? 0; unsetfake
assert_eq "...lead" "$(sessions lead)" "1"
hh_tmux kill-session -t =lead; rm -f "$P/name"

# ---- start again: reattach to a session that runs the hub, never a second ----
setfake hubself; hh_tmux kill-session -t =hub; hub start >/dev/null 2>&1; unsetfake
pane=$(paneof hub); i=0; while [ "$(jq -r '.pane // empty' "$P/hub.json" 2>/dev/null)" != "$pane" ] && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
out=$(hub start 2>&1); assert_status "start while the hub runs in that session" $? 0
assert_eq "...makes no second session" "$(sessions hub)" "1"
assert_contains "...and says how to attach" "$out" "attach -t hub"
jq '.pane_pid = "1"' "$P/hub.json" > "$P/hub.json.n" && mv "$P/hub.json.n" "$P/hub.json"
hub start >/dev/null 2>&1; assert_status "a recorded pane whose process is not the pane's now (an id handed out again) is no hub to reattach to" $? 4
assert_eq "...and no second session was made" "$(sessions hub)" "1"
hh_tmux kill-session -t =hub
hh_tmux new-session -d -s hub 'sleep 600'
hub start >/dev/null 2>"$T_TMP/err"; assert_status "a session of that name that is not the hub is refused" $? 4
assert_contains "...and says so" "$(cat "$T_TMP/err")" "not the hub"
hh_tmux kill-session -t =hub
setfake hubself; hh_tmux new-session -d -s other -c "$H" 'exec claude --name x'; unsetfake
i=0; while [ "$(jq -r '.pane // empty' "$P/hub.json")" = "" ] || ! hh_tmux list-panes -s -t =other -F '#{pane_id}' | grep -qx "$(jq -r .pane "$P/hub.json")"; do sleep 0.5; i=$((i + 1)); [ "$i" -lt 20 ] || break; done
hub start >/dev/null 2>"$T_TMP/err"; assert_status "a hub that runs in another tmux session is not started twice" $? 4
assert_contains "...it is told which, once" "$(cat "$T_TMP/err")" "in tmux session other:"
hh_tmux kill-session -t =other

# ---- inside tmux already: no nesting, the line to start it there ----
out=$(cd "$H" && TMUX=/tmp/x,1,0 hh-hub start 2>&1); assert_status "start inside tmux" $? 0
assert_eq "...starts nothing" "$(sessions hub)" "0"
assert_contains "...says how to start it there" "$out" "new-session -d -s hub -c $H"
assert_contains "...and to switch to it" "$out" "switch-client -t hub"
assert_contains "...the line unsets the away marker for the hub it starts" "$out" "env -u HH_AWAY_BYPASS -u HH_AWAY_HUB -u HH_AWAY_MCP_ALLOW claude --name hub"
out=$(hub 2>&1); assert_contains "the usage lists hh-hub start with no arguments" "$out" "hh-hub start  "

# ---- self: the hub records its own pane ----
setfake hubself; hub start >/dev/null 2>&1; unsetfake
pane=$(paneof hub)
i=0; while [ "$(jq -r '.pane // empty' "$P/hub.json" 2>/dev/null)" != "$pane" ] && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
 ppid=$(hh_tmux display-message -p -t "$pane" '#{pane_pid}')
assert_eq "self records the pane" "$(jq -r .pane "$P/hub.json")" "$pane"
assert_eq "...and the server's socket" "$(jq -r .socket "$P/hub.json")" "$HH_TMUX_SOCKET"
assert_eq "...the pane's process" "$(jq -r .pane_pid "$P/hub.json")" "$ppid"
assert_eq "...and when it started" "$(jq -r .pane_started "$P/hub.json")" "$(hh_lstart "$ppid")"
[ -n "$(jq -r '.claude_pid // empty' "$P/hub.json")" ] && [ -n "$(jq -r '.claude_started // empty' "$P/hub.json")" ] && ok "...and the Claude process, as before" || bad "no claude pid"
assert_eq "...the name too" "$(jq -r .name "$P/hub.json")" "hub"
hh_tmux kill-session -t =hub
mkdir -p "$T_TMP/cl"; printf '#!/usr/bin/env bash\ncd "%s" && hh-hub self "$@"\n' "$H" > "$T_TMP/cl/claude"
out=$(bash "$T_TMP/cl/claude" --name hub 2>&1 >/dev/null); assert_status "self outside tmux" $? 0
assert_contains "...says so, with the line that starts the hub" "$out" "hh-hub start"
assert_contains "...as a path that works in the owner's own terminal" "$out" "$HH_REPO_ROOT/bin/hh-hub start"
assert_eq "...says it once" "$(printf '%s\n' "$out" | grep -c 'hh-hub start')" "1"
assert_eq "...and records no pane (a stale one is dropped)" "$(jq -r '.pane // "none"' "$P/hub.json")" "none"
setfake hubself; hub start >/dev/null 2>&1; unsetfake; pane=$(paneof hub)
i=0; while [ "$(jq -r '.pane // empty' "$P/hub.json" 2>/dev/null)" != "$pane" ] && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
out=$(TMUX_PANE="$pane" TMUX=/nonexistent/sock,1,0 bash "$T_TMP/cl/claude" --name hub 2>&1 >/dev/null); assert_status "self from a pane of another server (TMUX names it)" $? 0
assert_eq "...records no pane: the socket is the one TMUX names" "$(jq -r '.pane // "none"' "$P/hub.json")" "none"
assert_contains "...and says it is a tmux server hivehouse does not use" "$out" "tmux server hivehouse does not use"
case "$out" in *"not in a tmux pane"*) bad "...and not that it is no tmux pane at all" ;; *) ok "...and not that it is no tmux pane at all" ;; esac
hh_tmux kill-session -t =hub
out=$(TMUX_PANE=%99 bash "$T_TMP/cl/claude" --name hub 2>&1 >/dev/null); assert_status "a pane id this server does not have" $? 0
assert_contains "...is no pane to record" "$out" "hh-hub start"
assert_eq "...nothing recorded" "$(jq -r '.pane // "none"' "$P/hub.json")" "none"

# ---- the hub's handoff: written from the template when absent, kept when there ----
rm -f "$P/memory/hub-handoff.md"; bash "$T_TMP/cl/claude" --name hub >/dev/null 2>&1
assert_contains "self writes the handoff from the template when it is absent" "$(cat "$P/memory/hub-handoff.md" 2>/dev/null)" "## START HERE"
printf '# mine\n\n## START HERE\nkeep me\n' > "$P/memory/hub-handoff.md"; bash "$T_TMP/cl/claude" --name hub >/dev/null 2>&1
assert_contains "...and keeps one that is there" "$(cat "$P/memory/hub-handoff.md")" "keep me"

t_done
