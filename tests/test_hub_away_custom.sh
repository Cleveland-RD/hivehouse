#!/usr/bin/env bash
# custom/ is writable by an away agent, so while the owner is away the hub's pickup line and the handoff template hh-hub self writes come from the
# plugin's own files, never custom/: a line typed into the hub after a /clear is read by the hub as the owner's. Outside away mode custom/ works.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/$T_HUB"
ME=$(id -u); NOW=$(date +%s); DD="$T_TMP/dg/area"; DF="$DD/delegate"
mkdel() {  # mkdel <until>: the owner's delegate file, as root would have made it
  mkdir -p "$DD"; chmod 755 "$DD" "$T_TMP/dg"
  printf "$T_DELEGATE_LINE1"'\nhub=%s\nuntil=%s\nmcp=\n' "$H" "$1" > "$DF"; chmod 644 "$DF"
}
mkdel "$((NOW + 3600))"
if ! hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1; then echo "  SKIP the fixture folder is not eligible here"; t_done; exit 0; fi
DB=$(t_delegate_bin "$DF"); export PATH="$DB:$PATH"
cp -R "$HH_REPO_ROOT/rules" "$T_TMP/rules"   # the scratch copy of bin/ finds the plugin's own rules one folder up
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
hub() { (cd "$H" && "$DB/hh-hub" "$@"); }
paneof() { hh_tmux list-panes -t "=$1" -F '#{pane_id}' | head -1; }
screen() { hh_tmux capture-pane -p -J -S - -t "$(paneof "$1")"; }
log() { cat "$P/rotate.log" 2>/dev/null; }
rotated() { local i=0 n=$1; while [ "$(log | grep -c 'rotated hub')" -le "$n" ] && [ "$i" -lt 60 ]; do sleep 0.5; i=$((i + 1)); done; sleep 1; }
assert_not() { case "$2" in *"$3"*) bad "$1" ;; *) ok "$1" ;; esac; }
hub init >/dev/null
hh_tmux set-environment -g HH_FAKE_CLAUDE hubself; hh_tmux set-environment -g HH_FAKE_HUBSELF 1; hub start >/dev/null 2>&1
hh_tmux set-environment -g -u HH_FAKE_CLAUDE; hh_tmux set-environment -g -u HH_FAKE_HUBSELF
pane=$(paneof hub); i=0; while [ "$(jq -r '.pane // empty' "$P/hub.json" 2>/dev/null)" != "$pane" ] && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
CU="$H/$T_STATE/$T_CUSTOM/rules"; mkdir -p "$CU"; chmod 755 "$H/$T_STATE" "$H/$T_STATE/$T_CUSTOM" "$CU"
printf 'CUSTOM-PICKUP {name}\n' > "$CU/hub-pickup.md"; chmod 644 "$CU/hub-pickup.md"
printf '# custom handoff\n\n## START HERE\nCUSTOM-TEMPLATE\n' > "$CU/hub-handoff.md"; chmod 644 "$CU/hub-handoff.md"

# away (a valid delegate file naming this hub): the plugin's own pickup line and template
hub rotate --still 2 --settle 1 --max 30 >/dev/null 2>"$T_TMP/rot.err"; rotated 0
assert_not "away: a custom pickup line is not typed" "$(screen hub)" "GOT: CUSTOM-PICKUP"
assert_contains "...the plugin's own is" "$(screen hub)" "GOT: /$T_PLUGIN:hub You are hub."
assert_contains "...and the log of the detached rotation says custom/ was ignored while away" "$(cat "$P/rotate.out" 2>/dev/null)" "the owner is away"
printf '#!/usr/bin/env bash\ncd "%s" && "%s/hh-hub" self "$@"\n' "$H" "$DB" > "$T_TMP/cl.sh"; rm -f "$P/memory/hub-handoff.md"; bash "$T_TMP/cl.sh" --name hub >/dev/null 2>&1
assert_contains "away: the handoff written when it is missing is the plugin's own template" "$(cat "$P/memory/hub-handoff.md" 2>/dev/null)" "## START HERE"
assert_not "...not custom/'s" "$(cat "$P/memory/hub-handoff.md" 2>/dev/null)" "CUSTOM-TEMPLATE"

# a delegate file that is there but refused (expired) is no leave to read custom/ either
mkdel "$((NOW - 10))"
rm -f "$P/memory/hub-handoff.md"; bash "$T_TMP/cl.sh" --name hub >/dev/null 2>&1
assert_not "an expired delegate file: custom/ is still not read for the template" "$(cat "$P/memory/hub-handoff.md" 2>/dev/null)" "CUSTOM-TEMPLATE"

# not away (no delegate file): custom/ works as before
rm -f "$DF"
rm -f "$P/memory/hub-handoff.md"; bash "$T_TMP/cl.sh" --name hub >/dev/null 2>&1
assert_contains "not away: the custom template is used" "$(cat "$P/memory/hub-handoff.md" 2>/dev/null)" "CUSTOM-TEMPLATE"
printf '# custom handoff\n\n## START HERE\nCUSTOM-TEMPLATE\n' > "$P/memory/hub-handoff.md"
hh_tmux kill-session -t =hub; rm -f "$P/hub.json"   # the stand-in Claude above was this very session: forget it
hh_tmux set-environment -g HH_FAKE_CLAUDE hubself; hh_tmux set-environment -g HH_FAKE_HUBSELF 1; hub start >/dev/null 2>&1
hh_tmux set-environment -g -u HH_FAKE_CLAUDE; hh_tmux set-environment -g -u HH_FAKE_HUBSELF   # the hub in its pane again: the self calls above ran outside tmux
pane=$(paneof hub); i=0; while [ "$(jq -r '.pane // empty' "$P/hub.json" 2>/dev/null)" != "$pane" ] && [ "$i" -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
hub rotate --still 2 --settle 1 --max 30 >/dev/null 2>&1; rotated 1
assert_contains "not away: the custom pickup line is typed" "$(screen hub)" "GOT: CUSTOM-PICKUP hub"
t_done
