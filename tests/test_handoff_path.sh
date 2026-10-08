#!/usr/bin/env bash
# The pickup line names the handoff the project keeps: hh-spawn --self --handoff <path> (and --handoff for a spawned agent) records the
# path in team.json, hh-rotate's pickup line and a respawn read it; without it the default stays.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
mkdir -p "$r/notes"; HP="$r/notes/orch-handoff.md"; AP="$r/notes/agent-handoff.md"
spawn() { hh-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 6 "${@:2}" 2>&1; }
paneof() { jq -r --arg a "$1" '.agents[]|select(.name==$a).pane' $T_STATE/team.json; }
screen() { hh_tmux capture-pane -p -J -S - -t "$(paneof "$1")"; }
getteam() { jq -r --arg a "$1" ".agents[] | select(.name == \$a) | $2" $T_STATE/team.json; }

# the default stays
spawn plain >/dev/null
assert_eq "no --handoff: no handoff recorded" "$(getteam plain 'has("handoff")')" "false"
assert_contains "...and the pickup line names the default" "$(hh_pickup_line proj "$r" plain)" "Read $r/$T_STATE/handoffs/plain.md from the top"

# a spawned agent
out=$(spawn kept --handoff "$AP"); assert_eq "spawn --handoff" "$(printf '%s' "$out" | tail -1 | grep -c '^%')" "1"
assert_eq "...is recorded in team.json" "$(getteam kept .handoff)" "$AP"
assert_contains "...its START HERE block is written there when none exists" "$(cat "$AP" 2>/dev/null)" "## START HERE"
assert_contains "...the pickup line names it" "$(hh_pickup_line proj "$r" kept)" "Read $AP from the top"
assert_eq "...and not the default" "$(hh_pickup_line proj "$r" kept | grep -c "$T_STATE/handoffs/kept.md")" "0"
hh-rotate kept --still 2 --settle 1 >/dev/null 2>&1; assert_eq "the spawn typed it, and hh-rotate types it again" "$(screen kept | grep -c "GOT: You are proj-kept. Read $AP from the top")" "2"
printf 'mine\n' > "$AP"
hh_tmux kill-pane -t "$(paneof kept)"; sleep 1
hh-spawn --respawn kept --still 2 --max-wait 6 >/dev/null 2>&1; assert_eq "a respawn keeps the path" "$(getteam kept .handoff)" "$AP"
assert_eq "...leaves the file as it was" "$(cat "$AP")" "mine"
assert_contains "...and sends the pickup line with it" "$(screen kept)" "Read $AP from the top"

# a respawn whose recorded handoff folder is gone falls back to the default, with a note
hh_tmux kill-pane -t "$(paneof kept)"; sleep 1
mv "$r/notes" "$r/notes.away"
out=$(hh-spawn --respawn kept --still 2 --max-wait 6 2>&1 >/dev/null); mv "$r/notes.away" "$r/notes"
assert_contains "a respawn whose handoff folder is gone says so" "$out" "default"
assert_eq "...and records the default" "$(getteam kept 'has("handoff")')" "false"

# refused values
out=$(spawn rel1 --handoff notes/rel.md | tail -1); assert_eq "a relative path is taken from the project root" "$(getteam rel1 .handoff)" "$r/notes/rel.md"
assert_contains "...and the file is made there" "$(cat "$r/notes/rel.md" 2>/dev/null)" "## START HERE"
(cd "$r/notes" && hh-spawn --agent rel2 --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 6 --handoff r2.md >/dev/null 2>&1)
assert_eq "...whatever folder it is run from" "$(getteam rel2 .handoff)" "$r/r2.md"
mkdir -p "$T_TMP/outside"; git -C "$r" worktree add -q "$T_TMP/proj-wt" -b wt1; mkdir -p "$T_TMP/proj-wt/notes"
out=$(spawn wt1 --handoff "$T_TMP/proj-wt/notes/h.md" | tail -1); assert_eq "a folder of one of the project's worktrees is allowed" "$(getteam wt1 .handoff)" "$T_TMP/proj-wt/notes/h.md"
out=$(spawn bad1 --handoff "$T_TMP/outside/h.md"); assert_contains "a path outside the project and its worktrees is refused" "$out" "inside the project"
out=$(spawn bad1 --handoff "../outside/h.md"); assert_contains "a relative path that leaves the project is refused" "$out" "no . or .. in it"
out=$(spawn bad1 --handoff "$r/notes/../../outside/h.md"); assert_contains "a .. that escapes the project is refused" "$out" "no . or .. in it"
out=$(spawn bad1 --handoff "$r/notes/../notes/h2.md"); assert_contains "any .. is refused, even one that stays inside" "$out" "no . or .. in it"
ln -s "$T_TMP/outside/target.md" "$r/notes/dangling.md"; out=$(spawn bad1 --handoff "$r/notes/dangling.md"); assert_contains "a path whose last part is a link (dangling) is refused" "$out" "link"
echo x > "$r/notes/real.md"; ln -s "$r/notes/real.md" "$r/notes/linked.md"; out=$(spawn bad1 --handoff "$r/notes/linked.md"); assert_contains "...and one that points at a file is refused too" "$out" "link"
assert_eq "...nothing was written through the link" "$(ls "$T_TMP/outside" | wc -l | tr -d ' ')" "0"
ln -s "$T_TMP/outside" "$r/linkdir"; out=$(spawn bad1 --handoff "$r/linkdir/h.md"); assert_contains "a folder that is a link out of the project is refused" "$out" "inside the project"
out=$(spawn bad2 --handoff "$r/no;such.md"); assert_contains "a path hivehouse will not type" "$out" "type"
out=$(spawn bad3 --handoff "$r/nofolder/h.md"); assert_contains "a path whose folder is missing" "$out" "folder does not exist"
out=$(hh-spawn --respawn kept --handoff "$AP" 2>&1); assert_contains "--respawn takes no --handoff" "$out" "--respawn takes only"

# the orchestrator, registered with --handoff
mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
cat > "$T_TMP/claude" <<'EOS'
#!/usr/bin/env bash
jq -nc --argjson p $$ '{pid:$p, name:"orch", sessionId:"s1"}' > "$CLAUDE_CONFIG_DIR/sessions/$$.json"
hh-spawn "$@" 2>"$OUT.err"; echo "rc=$?" >> "$OUT"
exec sleep 30
EOS
selfrun() { hh_tmux new-session -d -c "$r" -e "HIVEHOUSE_HOME=$HIVEHOUSE_HOME" -e "OUT=$1" "bash $T_TMP/claude --self --agent orchestrator ${2:-} >/dev/null"; sleep 2; }
selfrun "$T_TMP/o1.out" "--handoff $HP"
assert_contains "--self --handoff ran" "$(cat "$T_TMP/o1.out")" "rc=0"
assert_eq "...records the path" "$(getteam orchestrator .handoff)" "$HP"
assert_contains "...and the orchestrator's pickup line names it" "$(hh_pickup_line proj "$r" orchestrator)" "Read $HP from the top: its START HERE block is your prompt."
selfrun "$T_TMP/o2.out" ""
assert_eq "registering again without --handoff keeps it" "$(getteam orchestrator .handoff)" "$HP"
selfrun "$T_TMP/o3.out" "--handoff $r/notes/other.md"
assert_eq "registering again with another path replaces it" "$(getteam orchestrator .handoff)" "$r/notes/other.md"
selfrun "$T_TMP/o4.out" "--handoff notes/rel-o.md"
assert_eq "--self takes a relative path from the project root too" "$(getteam orchestrator .handoff)" "$r/notes/rel-o.md"
selfrun "$T_TMP/o5.out" "--handoff $T_TMP/outside/h.md"
assert_contains "--self refuses a path outside the project" "$(cat "$T_TMP/o5.out.err")" "inside the project"
# a record that is no longer a path hivehouse types falls back to the default
jq '(.agents[] | select(.name == "orchestrator") | .handoff) = "/abs;x.md"' $T_STATE/team.json > $T_TMP/t.json && mv $T_TMP/t.json $T_STATE/team.json
assert_contains "a bad recorded path is ignored" "$(hh_pickup_line proj "$r" orchestrator)" "Read $r/$T_STATE/handoffs/orchestrator.md from the top"
jq --arg p "$T_TMP/outside/h.md" '(.agents[] | select(.name == "orchestrator") | .handoff) = $p' $T_STATE/team.json > $T_TMP/t.json && mv $T_TMP/t.json $T_STATE/team.json
assert_contains "...and so is a recorded path outside the project" "$(hh_pickup_line proj "$r" orchestrator)" "Read $r/$T_STATE/handoffs/orchestrator.md from the top"
t_done
