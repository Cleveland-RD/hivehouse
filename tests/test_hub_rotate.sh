#!/usr/bin/env bash
# The hub rotates itself like an orchestrator: hh-hub rotate waits until its recorded pane is idle, checks it is still that pane and
# process, types /clear, then its pickup line (from hh-resolve, so a custom/ file overrides it). One code path with hh-rotate.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P)
hub() { (cd "$H" && hh-hub "$@"); }
P="$H/$T_HUB"
paneof() { hh_tmux list-panes -t "=$1" -F '#{pane_id}' | head -1; }
screen() { hh_tmux capture-pane -p -J -S - -t "$(paneof "$1")"; }
log() { cat "$P/rotate.log" 2>/dev/null; }
assert_not() { case "$2" in *"$3"*) bad "$1" ;; *) ok "$1" ;; esac; }
startfake() {  # startfake <mode>: the hub in tmux, its Claude a stand-in in that mode that records the pane
  hh_tmux kill-session -t =hub 2>/dev/null
  hh_tmux set-environment -g HH_FAKE_CLAUDE "$1"; hh_tmux set-environment -g HH_FAKE_HUBSELF 1; hub start >/dev/null 2>&1; hh_tmux set-environment -g -u HH_FAKE_CLAUDE; hh_tmux set-environment -g -u HH_FAKE_HUBSELF
  local p i=0; p=$(paneof hub)
  while [ "$(jq -r '.pane // empty' "$P/hub.json" 2>/dev/null)" != "$p" ] && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
}
hub init >/dev/null
HANDOFF="$P/memory/hub-handoff.md"

# ---- hh-resolve: the pickup line and the handoff template, a custom/ file first ----
PLUGIN_DIR="$HH_REPO_ROOT"
assert_eq "hub-pickup resolves to the plugin's own file" "$(cd "$H" && HH_PROJECT="$H" hh-resolve hub-pickup 2>/dev/null)" "$PLUGIN_DIR/rules/hub-pickup.md"
assert_eq "hub-handoff resolves to the plugin's own file" "$(cd "$H" && HH_PROJECT="$H" hh-resolve hub-handoff 2>/dev/null)" "$PLUGIN_DIR/rules/hub-handoff.md"
mkdir -p "$H/$T_STATE/$T_CUSTOM/rules"; chmod 755 "$H/$T_STATE" "$H/$T_STATE/$T_CUSTOM" "$H/$T_STATE/$T_CUSTOM/rules"
printf 'MY PICKUP {name} {handoff}\n' > "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"; chmod 644 "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"
assert_eq "a custom hub-pickup overrides it (the hub's folder is the project level)" "$(cd "$H" && HH_PROJECT="$H" hh-resolve hub-pickup 2>/dev/null)" "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"
(cd "$H" && HH_PROJECT="$H" hh-resolve hub-nothing >/dev/null 2>&1); assert_status "any other name is usage" $? 64
assert_contains "the plugin's pickup line names the hub, its handoff and the hub skill" "$(cat "$PLUGIN_DIR/rules/hub-pickup.md")" "{handoff}"
assert_contains "the handoff template has a START HERE block" "$(cat "$PLUGIN_DIR/rules/hub-handoff.md")" "## START HERE"

# ---- one code path with hh-rotate ----
for f in hh-rotate hh-hub; do
  case "$(cat "$HH_REPO_ROOT/bin/$f")" in *"'/clear'"*) bad "bin/$f types /clear itself: the send belongs to hh-lib.sh" ;; *) ok "bin/$f has no copy of the /clear send" ;; esac
done
case "$(cat "$HH_REPO_ROOT/bin/hh-lib.sh")" in *"'/clear'"*) ok "hh-lib.sh holds the one send" ;; *) bad "hh-lib.sh has no /clear send" ;; esac

# ---- rotate ----
hub rotate >/dev/null 2>&1; assert_status "rotate with no hub pane recorded" $? 2
startfake hubself
cat > "$HANDOFF" <<'EOF'
# hub handoff

## START HERE
x
EOF
rm -f "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"
t0=$(date +%s)
out=$(hub rotate --still 2 --settle 1 --max 30 2>&1); assert_status "rotate" $? 0
t1=$(date +%s)
[ $((t1 - t0)) -le 2 ] && ok "...returns at once: the rotation runs detached" || bad "rotate took $((t1 - t0)) s"
rotated() { local i=0 n=$1; while [ "$(log | grep -c 'rotated hub')" -le "$n" ] && [ "$i" -lt 60 ]; do sleep 0.5; i=$((i + 1)); done; sleep 1; }   # rotated <rotations logged before>: the next one is done
rotated 0
assert_contains "the pane was cleared" "$(screen hub)" "CLEARED"
assert_contains "the pickup line followed, the hub skill first" "$(screen hub)" "GOT: /$T_PLUGIN:hub You are hub. Read $HANDOFF from the top: its START HERE block is your prompt."
assert_contains "rotate.log has the rotation" "$(log)" "rotated hub"

# a custom pickup line overrides the plugin's
printf 'CUSTOM {name} reads {handoff}\n' > "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"; chmod 644 "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"
(cd "$H" && HH_PROJECT="$H" hh-hub rotate --still 2 --settle 1 --max 30 >/dev/null 2>&1)
rotated 1
assert_contains "a custom pickup line is typed, its words filled in" "$(screen hub)" "GOT: CUSTOM hub reads $HANDOFF"
# ...but only one line of plain text: anything else is ignored with a note, and the plugin's own is typed
printf 'two\nlines {name}\n' > "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"
(cd "$H" && HH_PROJECT="$H" hh-hub rotate --still 2 --settle 1 --max 30 >/dev/null 2>&1)
rotated 2
assert_contains "a custom pickup of two lines is refused, the plugin's is used" "$(screen hub)" "GOT: /$T_PLUGIN:hub You are hub."
rm -f "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"

# only on idle: a busy pane is never typed into
startfake busy
hub rotate --still 2 --settle 1 --max 4 >/dev/null 2>&1; assert_status "a busy hub's rotate still returns at once" $? 0
sleep 7
assert_not "...and nothing was typed into the busy pane" "$(screen hub)" "/clear"
assert_contains "...the refusal is logged" "$(log | tail -1)" "not-idle hub"
# a dialog on screen: nothing typed either
startfake dialog
hub rotate --still 2 --settle 1 --max 6 >/dev/null 2>&1
sleep 6
assert_not "nothing was typed into a dialog" "$(screen hub)" "/clear"
assert_contains "...it is logged" "$(log | tail -1)" "dialog hub"

# only into the pane and process that were recorded
startfake hubself
setrec() { jq "$1" "$P/hub.json" > "$P/hub.json.n" && mv "$P/hub.json.n" "$P/hub.json"; }
cp "$P/hub.json" "$T_TMP/hub.json.saved"
setrec '.pane_pid = "1"'
hub rotate --still 2 --settle 1 --max 6 >/dev/null 2>&1; sleep 3
assert_not "a pane whose process is not the recorded one gets nothing" "$(screen hub)" "/clear"
assert_contains "...and it is logged" "$(log | tail -1)" "identity hub"
cp "$T_TMP/hub.json.saved" "$P/hub.json"
setrec '.claude_started = "Mon Jan  1 00:00:00 2001"'
hub rotate --still 2 --settle 1 --max 6 >/dev/null 2>&1; sleep 3
assert_not "a Claude that is not the recorded one gets nothing" "$(screen hub)" "/clear"
cp "$T_TMP/hub.json.saved" "$P/hub.json"
hh_tmux kill-session -t =hub
hub rotate --still 2 --settle 1 --max 6 >/dev/null 2>&1; assert_status "a pane that is gone" $? 2

# ---- context: the hub's own level, for the rotation check ----
startfake hubself
sid=$(printf 'hub-sess-1')
jq --arg s "$sid" '.session_id = $s' "$P/hub.json" > "$P/hub.json.n" && mv "$P/hub.json.n" "$P/hub.json"
hub context >/dev/null 2>&1; assert_status "context with no transcript" $? 2
mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"
jq -nc '{type:"assistant", isSidechain:false, message:{model:"claude-sonnet-5-5", usage:{input_tokens:100000, cache_read_input_tokens:0, cache_creation_input_tokens:0, output_tokens:0}}}' > "$CLAUDE_CONFIG_DIR/projects/p/$sid.jsonl"
assert_eq "context is a percent of the window it is given" "$(hub context --window 400000 2>/dev/null)" "25"
assert_eq "...and says when the window is only assumed" "$(hub context 2>/dev/null)" "50 (window assumed 200000)"
hub context --window x >/dev/null 2>&1; assert_status "a window that is no number" $? 4

t_done
