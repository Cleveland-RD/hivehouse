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
# a hub with no handoff, or one with no START HERE block, is not cleared: it would wake with nothing to read
mv "$HANDOFF" "$HANDOFF.saved"
hub rotate --still 2 --settle 1 --max 30 >"$T_TMP/r.out" 2>&1; assert_status "rotate with no handoff file refuses" $? 4
assert_contains "...saying why" "$(cat "$T_TMP/r.out")" "hub-handoff.md"
printf 'no block here\n' > "$HANDOFF"
hub rotate --still 2 --settle 1 --max 30 >"$T_TMP/r.out" 2>&1; assert_status "rotate with a handoff that has no START HERE block refuses" $? 4
sleep 1; assert_not "...and nothing was typed" "$(screen hub)" "/clear"
mv "$HANDOFF.saved" "$HANDOFF"
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
assert_not "a custom pickup of two lines is never typed" "$(screen hub)" "GOT: two"
assert_contains "a custom pickup of two lines is refused, the plugin's is used" "$(screen hub)" "GOT: /$T_PLUGIN:hub You are hub."
# a custom line may only start with a letter or digit, or with "/<plugin>:": a "!" is bash mode, "/login" and "/plugin" are commands
cnt=3
for bad in '!touch /tmp/x' '/login' '/plugin list' '#note' '&x' '  !x'; do
  printf '%s {name}\n' "$bad" > "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"
  (cd "$H" && HH_PROJECT="$H" hh-hub rotate --still 2 --settle 1 --max 30 >/dev/null 2>&1)
  cnt=$((cnt + 1)); rotated $((cnt - 1))
  assert_not "a custom pickup line starting with [$bad] is never typed" "$(screen hub)" "GOT: $bad"
done
assert_contains "...the plugin's own line is typed instead" "$(screen hub)" "GOT: /$T_PLUGIN:hub You are hub."
printf '/%s:hub custom {name}\n' "$T_PLUGIN" > "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"
(cd "$H" && HH_PROJECT="$H" hh-hub rotate --still 2 --settle 1 --max 30 >/dev/null 2>&1); cnt=$((cnt + 1)); rotated $((cnt - 1))
assert_contains "a custom line starting with /<plugin>: is typed" "$(screen hub)" "GOT: /$T_PLUGIN:hub custom hub"
rm -f "$H/$T_STATE/$T_CUSTOM/rules/hub-pickup.md"

# the shared rotation checks the identity before it types /clear, not only after the wait
vno() { return 1; }; pk() { echo x; }
startfake hubself
hh_rotate_pane "$(jq -r .pane "$P/hub.json")" "$HH_TMUX_SOCKET" 2 6 1 vno pk; assert_status "an identity that fails before the clear exits 6" $? 6
assert_not "...and nothing was typed" "$(screen hub)" "/clear"

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
rm -f "$P/rotate.log"
hub context >/dev/null 2>&1; assert_status "context with no transcript" $? 2
mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"
jq -nc '{type:"assistant", isSidechain:false, message:{model:"claude-sonnet-5-5", usage:{input_tokens:100000, cache_read_input_tokens:0, cache_creation_input_tokens:0, output_tokens:0}}}' > "$CLAUDE_CONFIG_DIR/projects/p/$sid.jsonl"
assert_eq "context is a percent of the window it is given" "$(hub context --window 400000 2>/dev/null)" "25"
assert_eq "...and says when the window is only assumed" "$(hub context 2>/dev/null)" "10 (window assumed 1000000)"
hub context --window x >/dev/null 2>&1; assert_status "a window that is no number" $? 4
# S4: the window the hub recorded for itself (hh-hub self --window), as hh-spawn --self records an orchestrator's
mkdir -p "$T_TMP/cl2"; printf '#!/usr/bin/env bash\ncd "%s" && hh-hub self "$@"\n' "$H" > "$T_TMP/cl2/claude"
bash "$T_TMP/cl2/claude" --name hub --window 400000 >/dev/null 2>&1; assert_status "self --window" $? 0
assert_eq "...is recorded in hub.json" "$(jq -r .window "$P/hub.json")" "400000"
bash "$T_TMP/cl2/claude" --name hub --window abc >/dev/null 2>&1; assert_status "a window that is no number is refused" $? 4
bash "$T_TMP/cl2/claude" --name hub >/dev/null 2>&1
assert_eq "registering again without --window keeps it" "$(jq -r .window "$P/hub.json")" "400000"
jq --arg s "$sid" '.session_id = $s' "$P/hub.json" > "$P/hub.json.n" && mv "$P/hub.json.n" "$P/hub.json"
assert_eq "context uses the recorded window, and says it was not measured" "$(hub context 2>/dev/null)" "25 (window assumed 400000)"
assert_eq "...unless it is given one" "$(hub context --window 200000 2>/dev/null)" "50"
# S2: a rotate that sent nothing is told at the next level check
printf '%s rotated hub\n' "2026-10-08T10:00:00Z" > "$P/rotate.log"
assert_eq "context says nothing about a rotation that worked" "$(hub context 2>/dev/null | wc -l | tr -d ' ')" "1"
printf '%s not-idle hub (nothing sent)\n' "2026-10-08T10:05:00Z" >> "$P/rotate.log"
assert_contains "a refusal after the last success shows with the level" "$(hub context 2>/dev/null | tail -1)" "not-idle hub (nothing sent)"
assert_eq "...the level is still the first line" "$(hub context 2>/dev/null | head -1)" "25 (window assumed 400000)"
printf '%s rotated hub\n' "2026-10-08T10:09:00Z" >> "$P/rotate.log"
assert_eq "...and is gone once a rotation worked again" "$(hub context 2>/dev/null | wc -l | tr -d ' ')" "1"
# S5: the used tokens of a transcript are read in one place
for f in hh-context hh-hub; do case "$(cat "$HH_REPO_ROOT/bin/$f")" in *isSidechain*) bad "bin/$f reads a transcript's usage itself: it belongs to hh-lib.sh" ;; *) ok "bin/$f has no copy of the transcript reading" ;; esac; done
case "$(cat "$HH_REPO_ROOT/bin/hh-lib.sh")" in *isSidechain*) ok "hh-lib.sh holds it" ;; *) bad "hh-lib.sh does not read a transcript's usage" ;; esac

# ---- the hub skill: handoff, when to rotate, the beat after a restart ----
SK=$(cat "$HH_REPO_ROOT/skills/hub/SKILL.md")
assert_contains "the skill may run rotate and context" "$(head -5 "$HH_REPO_ROOT/skills/hub/SKILL.md" | grep '^allowed-tools')" "Bash(hh-hub rotate*) Bash(hh-hub context*)"
assert_contains "it keeps the handoff in the hub's memory" "$SK" "$T_HUB/memory/hub-handoff.md"
assert_contains "...from the template hh-resolve finds" "$SK" "hh-resolve hub-handoff"
assert_contains "it checks its own level after each task it hands on and on every beat" "$SK" "after each task you hand on and on every beat"
assert_contains "...at the plugin's one rotation level" "$SK" 'user_config.rotate_at_percent'
assert_contains "...updates the handoff, then rotates as its last act" "$SK" "hh-hub rotate"
assert_contains "the beat is recreated at every start when away and CronList lacks the job" "$SK" "CronList"
assert_contains "...which says so in the start steps" "$(sed -n '/^## 1\. At every start/,/^## 2\./p' "$HH_REPO_ROOT/skills/hub/SKILL.md")" "recreate"
assert_contains "the start line the owner is given is hh-hub start" "$(sed -n '/^## 1\. At every start/,/^## 2\./p' "$HH_REPO_ROOT/skills/hub/SKILL.md")" "hh-hub start"
assert_contains "the owner is told to start the hub with a path that works in their terminal" "$SK" 'bin/hh-hub start'
assert_contains "the skill records the window with self" "$SK" 'hh-hub self --window ${user_config.window_orchestrator}'
assert_contains "...and says what to do with a window that is unknown" "$(sed -n '/^## 5b/,/^## 6/p' "$HH_REPO_ROOT/skills/hub/SKILL.md")" "window unknown"
assert_contains "...and tells the owner once of a refused rotation" "$(sed -n '/^## 5b/,/^## 6/p' "$HH_REPO_ROOT/skills/hub/SKILL.md")" "last rotate"
for f in README.md docs/hub.md; do assert_contains "$f gives hh-hub start as a path that works" "$(cat "$HH_REPO_ROOT/$f")" "<installPath>/bin/hh-hub start"; done
case "$(cat "$HH_REPO_ROOT/README.md")" in *'`claude` in the'*'work folder is the hub'*) bad "README step 5 still says claude is the hub" ;; *) ok "README step 5 names hh-hub start too" ;; esac
for f in skills/handoff/SKILL.md rules/RULES.md; do assert_contains "$f says the handoff is the file the pickup line names" "$(cat "$HH_REPO_ROOT/$f")" "the file its pickup line names"; done
case "$SK" in *"rotate_at_percent"*"rotate_at_percent"*) ok "...the level is read from the one option" ;; *) bad "the skill names rotate_at_percent fewer than twice" ;; esac

t_done
