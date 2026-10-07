#!/usr/bin/env bash
# Delegate mode, the part the hub's own commands carry: `away` and `back` print what the owner pastes (never run sudo), status
# shows "away until", `decide` records what the hub decided for the owner, `hold` keeps it off a project, and `recover` says what
# is due on each beat with its caps. The delegate file is a fixture here (t_delegate_bin: a scratch copy of bin/ that reads it as
# this user); the real file, owned by root, is a live check.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
export HM_SUDO_LOG="$T_TMP/sudo.log"; : > "$HM_SUDO_LOG"
env -u HIVEMIND_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/.hivemind-hub"
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
hub() { (cd "$H" && hm-hub "$@"); }
idof() { printf '%s' "${1%%$'\t'*}"; }
ME=$(id -u); REALUID=$(/usr/bin/id -u); NOW=$(date +%s)
DD="$T_TMP/dg/area"; DF="$DD/delegate"
mkdel() {  # mkdel [hub] [until] [mcp list]: the owner's delegate file, as root would have made it
  mkdir -p "$DD"; chmod 755 "$DD" "$T_TMP/dg"
  printf 'hivemind-delegate 1\nhub=%s\nuntil=%s\nmcp=%s\n' "${1:-$H}" "${2:-$((NOW + 3600))}" "${3:-}" > "$DF"; chmod 644 "$DF"
}
mkdel
if ! hm_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1; then
  hm_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1
  echo "  SKIP the fixture folder is not eligible here: $HM_DELEGATE_WHY"; t_done; exit 0
fi
DB=$(t_delegate_bin "$DF"); dhub() { (cd "$H" && "$DB/hm-hub" "$@"); }   # the copy that sees the fixture
mkcl() {  # mkcl <bin dir> [noself]: a stand-in for the hub's Claude: it records itself as the hub (hm-hub self), then runs that bin's hm-hub as its child
  local d; d=$(mktemp -d "$T_TMP/cl.XXXXXX")
  if [ "${2:-}" = noself ]; then printf '#!/usr/bin/env bash\ncd "%s" && "%s/hm-hub" "$@"\n' "$H" "$1" > "$d/claude"
  else printf '#!/usr/bin/env bash\ncd "%s" && "%s/hm-hub" self --name hub >/dev/null && "%s/hm-hub" "$@"\n' "$H" "$1" "$1" > "$d/claude"; fi
  chmod +x "$d/claude"; printf '%s\n' "$d/claude"
}
mkcl_node() {  # mkcl_node <bin dir>: the same stand-in as a node script named claude, which ps -E can show the environment of
  local d; d=$(mktemp -d "$T_TMP/cln.XXXXXX")
  local e; e=$(jq -nc --arg PATH "$PATH" --arg HOME "$HOME" --arg HIVEMIND_HOME "$HIVEMIND_HOME" --arg HM_TMUX_SOCKET "$HM_TMUX_SOCKET" --arg CLAUDE_CONFIG_DIR "$CLAUDE_CONFIG_DIR" --arg HM_MANAGED_SETTINGS "$HM_MANAGED_SETTINGS" '$ARGS.named')
  printf 'const { spawnSync } = require("child_process")\nconst env = Object.assign({}, %s, process.env)\nspawnSync(%s, ["self", "--name", "hub"], { cwd: %s, stdio: "ignore", env })\nconst r = spawnSync(%s, process.argv.slice(2), { cwd: %s, stdio: "inherit", env })\nprocess.exit(r.status === null ? 1 : r.status)\n' "$e" "\"$1/hm-hub\"" "\"$H\"" "\"$1/hm-hub\"" "\"$H\"" > "$d/claude"; printf '%s\n' "$d/claude"
}
CLP=$(mkcl "$HM_REPO_ROOT/bin"); CLD=$(mkcl "$DB")
# where ps -E can show a process's environment (a non-platform binary on macOS: node), the stand-in is a node script and the
# marker is really read; elsewhere it is a bash script, the environment cannot be read, and recover refuses
READABLE=0; ep=$(t_env_probe HM_PROBE=1) || ep=""
if [ -n "$ep" ]; then t_track "$ep"; sleep 0.5; hm_env_has "$ep" HM_PROBE=1 && READABLE=1; kill "$ep" 2>/dev/null; fi
[ "$READABLE" = 1 ] && { CLN=$(mkcl_node "$DB"); NODEBIN=$(command -v node); }
hub init >/dev/null
for n in alpha beta gamma delta; do mk "$n"; hub add "$n" --home "$n" >/dev/null; done
bash "$CLP" self --name hub >/dev/null; assert_status "the hub records itself" $? 0

# ---- away: the lines the owner pastes ----
hub away >/dev/null 2>&1; assert_status "away needs --until" $? 64
hub away --until sometime >/dev/null 2>&1; assert_status "...a time it can read" $? 64
hub away --until "$((NOW - 60))" >/dev/null 2>&1; assert_status "...in the future" $? 4
hub away --until +8d >/dev/null 2>&1; assert_status "...at most 7 days" $? 4
hub away --until +1h --mcp-allow 'x;y' >/dev/null 2>&1; assert_status "...an MCP list it can print safely" $? 4
(cd "$T_TMP" && HM_HUB="$H" hm-hub away --until +1h >/dev/null 2>&1); assert_status "the hub is found from the cwd, never from HM_HUB" $? 2
out=$(hub away --until +2h 2>"$T_TMP/away.err"); assert_status "away" $? 0
assert_eq "...hivemind ran no sudo" "$(cat "$HM_SUDO_LOG")" ""
assert_eq "...only mkdir, tee, chown and chmod are named after sudo" "$(printf '%s\n' "$out" | grep -o 'sudo [a-z]*' | sort -u | tr '\n' ' ')" "sudo chmod sudo chown sudo mkdir sudo tee "
case "$(uname -s)" in
  Darwin) assert_contains "...the folder, quoted for the shell" "$out" 'sudo mkdir -p -- /Library/Application\ Support/hivemind/delegate.d'
          assert_contains "...the user's own file made by tee" "$out" "| sudo tee -- /Library/Application\\ Support/hivemind/delegate.d/$REALUID > /dev/null"
          assert_contains "...owned by root, with the folders above it" "$out" "sudo chown root:wheel -- /Library/Application\\ Support/hivemind /Library/Application\\ Support/hivemind/delegate.d /Library/Application\\ Support/hivemind/delegate.d/$REALUID"
          assert_contains "...the folders at 0755" "$out" 'sudo chmod 0755 -- /Library/Application\ Support/hivemind /Library/Application\ Support/hivemind/delegate.d' ;;
  *)      assert_contains "...the folder" "$out" 'sudo mkdir -p -- /etc/hivemind/delegate.d'
          assert_contains "...the user's own file made by tee" "$out" "| sudo tee -- /etc/hivemind/delegate.d/$REALUID > /dev/null"
          assert_contains "...owned by root, with the folders above it" "$out" "sudo chown root:root -- /etc/hivemind /etc/hivemind/delegate.d /etc/hivemind/delegate.d/$REALUID"
          assert_contains "...the folders at 0755" "$out" 'sudo chmod 0755 -- /etc/hivemind /etc/hivemind/delegate.d' ;;
esac
assert_contains "...a comment names the user and the uid" "$out" "# This file is for $(/usr/bin/id -un) (uid $REALUID)"
assert_contains "...and says an administrator can paste the lines from another account" "$out" "an administrator can paste these lines from another account"
assert_contains "...mode 0644" "$out" 'sudo chmod 0644 -- '
assert_contains "...the content names this hub" "$out" "hub=$H"
assert_contains "...and its MCP list (empty here) as the fourth line" "$out" "mcp= | sudo tee"
until_epoch=$(printf '%s\n' "$out" | sed -n 's/.*until=\([0-9]*\).*/\1/p' | head -1)
[ "$until_epoch" -ge $((NOW + 7190)) ] && [ "$until_epoch" -le $((NOW + 7500)) ] && ok "...and the time asked for" || bad "until=$until_epoch is not about +2h"
assert_contains "...the hub's start line is marked, in bypass, with only its allowed MCP servers" "$out" "HM_AWAY_BYPASS=1 HM_PROJECT=$H HM_AWAY_HUB=$H HM_AWAY_MCP_ALLOW='' claude --name hub --permission-mode bypassPermissions --no-chrome --strict-mcp-config --mcp-config $P/away-mcp.json /hivemind:hub"
assert_contains "...with the hub's own project and hub folders for the away hook" "$out" "HM_PROJECT=$H HM_AWAY_HUB=$H"
assert_contains "...before leaving: the one-time bypass warning, when it has not been accepted" "$out" "one-time warning"
assert_contains "...and the folder trust, when the folder is not trusted" "$out" "not trusted by Claude Code yet"
printf '{"skipDangerousModePermissionPrompt":true}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$T_TMP" > "$CLAUDE_CONFIG_DIR/.claude.json"
out2=$(hub away --until +1h)
assert_contains "...a project's repository does not inherit it: it is named, with the fix" "$out2" "$H/alpha is not trusted by Claude Code yet"
assert_contains "......saying what to start and where" "$out2" "Start claude in $H/alpha once and accept"
case "$out2" in *"$H is not trusted"*) bad "the hub's plain folder under a trusted one is called untrusted" ;; *) ok "......and the hub's own folder, under the trusted one, is not" ;; esac
jq -nc --arg t "$T_TMP" --arg h "$H" '{projects: ({($t):{hasTrustDialogAccepted:true}} + ([$h+"/alpha",$h+"/beta",$h+"/gamma",$h+"/delta"] | map({(.):{hasTrustDialogAccepted:true}}) | add))}' > "$CLAUDE_CONFIG_DIR/.claude.json"
out2=$(hub away --until +1h)
case "$out2" in *"one-time warning"*) bad "the bypass warning is asked for once it is accepted" ;; *) ok "...not asked again once it is accepted" ;; esac
case "$out2" in *"not trusted by Claude Code yet"*) bad "a folder under a trusted one is called untrusted" ;; *) ok "...a folder under a trusted one is trusted" ;; esac
rm -f "$CLAUDE_CONFIG_DIR/settings.json" "$CLAUDE_CONFIG_DIR/.claude.json"
assert_eq "...its MCP file lets no server in" "$(jq -c . "$P/away-mcp.json")" '{"mcpServers":{}}'
assert_eq "...at mode 0600" "$(stat -f '%Lp' "$P/away-mcp.json" 2>/dev/null || stat -c '%a' "$P/away-mcp.json")" "600"
assert_contains "...it says away is capped at 7 days" "$out" "at most 7 days"
assert_contains "...that a reboot ends it" "$out" "after a reboot"
assert_contains "...that messages to the hub are information only" "$out" "information only"
assert_contains "...that the MCP allowlist stops browser checks and computer-use unless allowed" "$out" "browser automation and computer-use"
assert_contains "...and that SendMessage is held to the hub and its teams, so peers on other machines are cut off" "$out" "SendMessage is held to the hub and its teams"
assert_contains "...and that no remote host is used" "$out" "No remote host"
assert_eq "...the time away began is kept for the screen" "$(jq -r '.since | length' "$P/away.json")" "20"
jq '.session_id = "sess-hub-1"' "$P/hub.json" > "$P/hub.json.t" && mv "$P/hub.json.t" "$P/hub.json"
out=$(hub away --until +1d); assert_contains "with a session recorded, the hub is resumed" "$out" "claude --permission-mode bypassPermissions --no-chrome --strict-mcp-config --mcp-config $P/away-mcp.json --resume sess-hub-1"
printf '{"mcpServers":{"docs":{"command":"docs-mcp","args":["--x"]}}}\n' > "$CLAUDE_CONFIG_DIR/.claude.json"
out=$(hub away --until +1h --mcp-allow docs,nothere)
assert_eq "an allowed server's definition is copied into the hub's MCP file" "$(jq -c '.mcpServers | keys' "$P/away-mcp.json")" '["docs"]'
assert_contains "...one that is not found is said so" "$out" "Not found (not loaded): nothere"
assert_contains "...and the list is the delegate file's fourth line" "$out" "mcp=docs\\,nothere | sudo tee"
out=$(hub back); assert_status "back" $? 0
assert_contains "...prints the line that removes the file" "$out" "sudo rm -f -- "
assert_contains "......the user's own, under delegate.d" "$out" "/delegate.d/$REALUID"
case "$out" in *HM_AWAY_BYPASS*|*bypassPermissions*) bad "the restart line after away is marked or in bypass" ;; *) ok "...and a restart line with no marker and no bypass" ;; esac
assert_contains "...which resumes the hub" "$out" "claude --resume sess-hub-1"
# the 0.3.0 file, <base>/delegate: no longer read, so both commands say so and print the line that removes it
OB="$T_TMP/oldbase"; mkdir -p "$OB"
OBIN=$(t_base_bin oldbin "$OB") || bad "t_base_bin"
out=$(cd "$H" && "$OBIN/hm-hub" away --until +1h); assert_status "away with no old shared file" $? 0
case "$out" in *"$OB/delegate"$'\n'*|*"$OB/delegate "*) bad "away names an old shared file that is not there" ;; *) ok "...names no old shared file" ;; esac
out=$(cd "$H" && "$OBIN/hm-hub" back); case "$out" in *"$OB/delegate"$'\n'*) bad "back names an old shared file that is not there" ;; *) ok "back names no old shared file either" ;; esac
printf 'hivemind-delegate 1\n' > "$OB/delegate"
out=$(cd "$H" && "$OBIN/hm-hub" away --until +1h); assert_status "away with the 0.3.0 shared file present" $? 0
assert_contains "...says it is no longer read" "$out" "$OB/delegate is no longer read"
assert_contains "...and prints the line that removes it" "$out" "sudo rm -f -- $OB/delegate"
out=$(cd "$H" && "$OBIN/hm-hub" back); assert_contains "back says it too" "$out" "$OB/delegate is no longer read"
assert_contains "...with the line that removes it" "$out" "sudo rm -f -- $OB/delegate"
assert_contains "...and the user's own file's line" "$out" "sudo rm -f -- $OB/delegate.d/$REALUID"
rm -f "$OB/delegate"
assert_eq "...and still no sudo ran" "$(cat "$HM_SUDO_LOG")" ""

# ---- status shows away, from the file ----
case "$(hub status --json | jq -c '.hub | has("away")')" in false) ok "no valid file for this hub: not away" ;; *) bad "away shown with no valid file" ;; esac
s=$(dhub status --json); assert_eq "with a valid file for this hub, status says until when" "$(printf '%s' "$s" | jq -r .hub.away.until)" "$((NOW + 3600))"
assert_contains "...and the plain status" "$(dhub status)" "away until"
mkdel "$T_TMP"; case "$(dhub status --json | jq -c '.hub | has("away")')" in false) ok "a file naming another hub is not this hub's away" ;; *) bad "away shown for another hub's file" ;; esac
mkdel "$H" "$((NOW - 10))"; case "$(dhub status --json | jq -c '.hub | has("away")')" in false) ok "an expired file is not away" ;; *) bad "away shown for an expired file" ;; esac
mkdel; chmod 666 "$DF"; case "$(dhub status --json | jq -c '.hub | has("away")')" in false) ok "a file anyone could write is not away" ;; *) bad "away shown for a writable file" ;; esac
mkdel
# a file at the user's path that is refused says why in status (away_refused): the owner who pasted the lines and still sees "not away"
refused() { dhub status --json | jq -r '.hub.away_refused // empty'; }
assert_eq "a valid file: nothing is refused" "$(refused)" ""
rm -f "$DF"; assert_eq "no file at all: nothing is refused" "$(refused)" ""
mkdel "$H" "$((NOW - 10))"; assert_contains "a file the check refuses by its own content (expired): the reason reaches status" "$(refused)" "the file has expired"
assert_contains "...and the plain status" "$(dhub status 2>&1)" "away refused: the file has expired"
mkdel; chmod 664 "$P/projects.json"; assert_contains "a file refused for an ownership check (projects.json): its reason reaches status" "$(refused)" "projects.json is writable by group or others"
chmod 644 "$P/projects.json"; assert_eq "...and goes when the records are put right" "$(refused)" ""
mkdel "$T_TMP"; assert_eq "a file naming another hub says nothing about this one" "$(refused)" ""
mkdel

# the last away period stays in status after away has ended (for the screen and the hub's return)
assert_eq "the last away period is in status, with no valid file" "$(hub status --json | jq -c '.hub.last_away | [has("since"), (.until | type)]')" '[true,"number"]'
# ---- nothing in the environment revives an expired file (A76) ----
mkdel "$H" "$((NOW - 10))"
fk="$T_TMP/fk"; mkdir -p "$fk"; printf '#!/bin/sh\necho %s\n' "$((NOW - 100000))" > "$fk/date"; chmod +x "$fk/date"
printf 'date() { echo %s; }\n' "$((NOW - 100000))" > "$T_TMP/benv.sh"
printf '#!/bin/sh\necho "$*" >> "%s/fakebash.ran"\nBASH_ENV="%s" exec /bin/bash "$@"\n' "$T_TMP" "$T_TMP/benv.sh" > "$fk/bash"; chmod +x "$fk/bash"
is_away() { jq -c '.hub | has("away")'; }
assert_eq "an expired file is not away" "$(dhub status --json | is_away)" "false"
assert_eq "...with a fake date first on PATH" "$(PATH="$fk:$PATH" dhub status --json | is_away)" "false"
assert_eq "...with a date() from BASH_ENV" "$(BASH_ENV="$T_TMP/benv.sh" dhub status --json | is_away)" "false"
assert_eq "...with an exported function date" "$( ( date() { echo "$((NOW - 100000))"; }; export -f date; dhub status --json ) | is_away)" "false"
assert_eq "...with a fake bash first on PATH" "$( (cd "$H" && PATH="$fk:$PATH" "$DB/hm-hub" status --json) | is_away)" "false"
# (a sibling script such as hm-context may still use the bash on PATH: it decides nothing about the away file)
{ [ ! -e "$T_TMP/fakebash.ran" ] || ! grep -q 'hm-hub' "$T_TMP/fakebash.ran"; } && ok "...hm-hub itself was never run by it" || bad "hm-hub ran under the bash found on PATH"
assert_eq "hm-hub starts as /bin/bash -p, which skips BASH_ENV and imports no functions" "$(head -1 "$HM_REPO_ROOT/bin/hm-hub")" "#!/bin/bash -p"
mkdel

# ---- decide: what the hub decided for the owner, word for word, only while away ----
ta=$(idof "$(hub task alpha --text "Add the export button")"); hub log "$ta" plan >/dev/null
printf 'Which of the two layouts?\nA or B.\n=== ANSWER ===\nB, as the existing pages do.\n' | hub decide "$ta" --reason "matches the existing pages" >/dev/null 2>&1
assert_status "decide while the owner is home (no valid delegate file for this hub)" $? 4
dout=$(printf 'Which of the two layouts?\nA or B.\n=== ANSWER ===\nB, as the existing pages do.\n' | dhub decide "$ta" --reason "matches the existing pages"); assert_status "decide while away" $? 0
assert_contains "...says it is decided" "$dout" "$ta decided"
assert_contains "...and which reply to send next, the answer's first line" "$dout" "now send the answer you recorded: HUB on TASK $ta: B, as the existing pages do."
assert_eq "...the question and answer, word for word" "$(grep -c -e 'Which of the two layouts?' -e 'B, as the existing pages do.' "$P/decisions/$ta.md")" "2"
assert_contains "...with its reason" "$(cat "$P/decisions/$ta.md")" "matches the existing pages"
assert_eq "...a decided event" "$(dhub tasks --json | jq -r --arg i "$ta" '.[] | select(.id==$i) | [.state, .needs_owner] | map(tostring) | join(" ")')" "decided false"
assert_eq "...with its reason in tasks --json" "$(dhub tasks --json | jq -r --arg i "$ta" '.[] | select(.id==$i) | .decisions[0].reason')" "matches the existing pages"
assert_eq "...the task stays open" "$(dhub tasks --open | grep -c "^$ta")" "1"
printf 'Q\n' | dhub decide "$ta" --reason r >/dev/null 2>&1; assert_status "a decision with no answer" $? 64
printf 'Q\n=== ANSWER ===\nA\n' | dhub decide "$ta" --reason "" >/dev/null 2>&1; assert_status "...no reason" $? 64
printf 'Q\n=== ANSWER ===\nA\n' | dhub decide "$ta" --reason $'two\nlines' >/dev/null 2>&1; assert_status "...a reason of two lines" $? 64
printf 'Q\n=== ANSWER ===\nA\n' | dhub decide nope-9 --reason r >/dev/null 2>&1; assert_status "...a task nobody asked" $? 2
hub log "$ta" decided >/dev/null 2>&1; assert_status "log never writes a decision: only decide, which asks the delegate file" $? 4
tc=$(idof "$(hub task alpha --text "Second")"); hub log "$tc" done >/dev/null
printf 'Q\n=== ANSWER ===\nA\n' | dhub decide "$tc" --reason r >/dev/null 2>&1; assert_status "...a closed task" $? 4
hub log "$ta" answered >/dev/null

# ---- the sessions the hub starts or wakes are recorded, for the caps ----
rj="$P/recovery.jsonl"
: > "$rj"; mk eps; hub add eps --home eps >/dev/null; te=$(idof "$(hub task eps --text "New")")
hub start eps "$te" --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "a start" $? 0
assert_eq "...is recorded with its time" "$(jq -s '[.[] | select(.action == "start" and .item == "eps" and (.epoch | type) == "number")] | length' "$rj")" "1"

# recover (and what follows) needs a Claude whose launch environment can be read: where it cannot, recover refuses, and these are skipped
if [ "$READABLE" != 1 ]; then
  echo "  SKIP only Apple platform binaries were found (no node): macOS shows no environment for them in ps -E, so recover (which refuses an unreadable environment) cannot be tested here"
  bash "$CLD" recover --json >/dev/null 2>"$T_TMP/m.err"; assert_status "recover refuses where the environment cannot be read" $? 4
  assert_contains "...and says why" "$(cat "$T_TMP/m.err")" "cannot be read"
  assert_eq "...hivemind ran no sudo anywhere" "$(cat "$HM_SUDO_LOG")" ""
  t_done; exit 0
fi
# ---- recover: what is due on each beat, capped ----
cp "$P/tasks.jsonl" "$T_TMP/tasks.saved"
kp=$(hm_tmux list-panes -t keep -F '#{pane_id}' | head -1); ki=$(hm_pane_identity "$HM_TMUX_SOCKET" "$kp")
mkorch() {  # mkorch <project> <claude pid>: a registered orchestrator on the keep pane
  local S="$H/$1/.hivemind"; mkdir -p "$S/team/orchestrator"
  jq -nc --arg k "$HM_TMUX_SOCKET" --arg kp "$kp" --arg p "${ki%%$'\t'*}" --arg s "${ki#*$'\t'}" --arg c "$2" --arg cs "$( [ "$2" = 99999 ] && echo 'Mon Jan  1 00:00:00 2001' || hm_lstart "$2")" --arg n "$1-orchestrator" \
    '{agents:[{name:"orchestrator", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s, claude_pid:$c, claude_started:$cs, name_full:$n}]}' > "$S/team.json"
  jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"sess-x", transcript_path:$t}' > "$S/team/orchestrator/session.json"
}
tb=$(idof "$(hub task beta --text "Work")"); tg=$(idof "$(hub task gamma --text "Held work")"); td=$(idof "$(hub task delta --text "Needs you")"); hub log "$td" plan >/dev/null
mkorch alpha 99999; mkorch gamma 99999; mkorch delta 99999
( exec -a claude sleep 600 ) >/dev/null 2>&1 & bpid=$!; disown "$bpid"; t_track "$bpid"; sleep 0.3
mkorch beta "$bpid"
# beta's one agent runs in a window of its own
aw=$(hm_tmux new-window -d -P -F '#{pane_id}' -t keep: -n impl 'sleep 600'); ai=$(hm_pane_identity "$HM_TMUX_SOCKET" "$aw")
jq --arg k "$HM_TMUX_SOCKET" --arg p "$aw" --arg pp "${ai%%$'\t'*}" --arg ps "${ai#*$'\t'}" '.agents += [{name:"impl", pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps}]' "$H/beta/.hivemind/team.json" > "$T_TMP/tj" && mv "$T_TMP/tj" "$H/beta/.hivemind/team.json"
rec() { if [ "$READABLE" = 1 ]; then HM_AWAY_BYPASS=1 node "$CLN" recover "$@" 2>/dev/null; else HM_AWAY_BYPASS=1 bash "$CLD" recover "$@" 2>/dev/null; fi; }
act() { printf '%s' "$1" | jq -r '[.actions[] | "\(.action):\(.project)"] | join(",")'; }
blk() { printf '%s' "$1" | jq -r '[.blocked[] | "\(.action):\(.project)"] | join(",")'; }
r=$(hub recover --json); assert_eq "recover with the owner home: nothing is due" "$r" '{"away":false,"actions":[],"blocked":[]}'
assert_contains "...and says so in plain words" "$(hub recover)" "not away"
mkdel "$H" "$((NOW + 3600))"
r=$(rec --json); assert_status "recover while away" $? 0
assert_eq "...a stopped orchestrator with an open task is woken, alone among these" "$(act "$r")" "wake:alpha,wake:gamma"
assert_eq "...nothing is blocked" "$(blk "$r")" ""
assert_eq "...the task it is woken for" "$(printf '%s' "$r" | jq -r '.actions[0].task')" "$ta"
assert_eq "...a project whose only task waits on the owner is left alone" "$(printf '%s' "$r" | jq -r '[.actions[] | select(.project == "delta")] | length')" "0"
hub hold gamma >/dev/null; assert_status "hold" $? 0
assert_eq "...status shows it held" "$(hub status gamma --json | jq -r '.projects[0].held')" "true"
r=$(rec --json); assert_eq "a held project is never woken" "$(act "$r")" "wake:alpha"
hub hold gamma --off >/dev/null; assert_eq "...released" "$(hub status gamma --json | jq -r '.projects[0].held')" "false"
# agents: RESPAWN once, when one goes from running to stopped since the previous beat
r=$(rec --json); assert_eq "an agent that runs is left alone (first beat)" "$(act "$r" | tr ',' '\n' | grep -c respawn)" "0"
hm_tmux kill-pane -t "$aw"; sleep 0.5
r=$(rec --json); assert_eq "an agent that stopped since the last beat: its orchestrator is told" "$(act "$r" | tr ',' '\n' | grep respawn)" "respawn:beta"
assert_eq "...naming it" "$(printf '%s' "$r" | jq -r '[.actions[] | select(.action == "respawn")][0].agents | join(",")')" "impl"
r=$(rec --json); assert_eq "...and once: the next beat does not say it again" "$(act "$r" | tr ',' '\n' | grep -c respawn)" "0"
# an agent of a team that sits in a worktree of the project's home is seen too
mk eps; hub add eps --home eps >/dev/null
( exec -a claude sleep 600 ) >/dev/null 2>&1 & epid=$!; disown "$epid"; t_track "$epid"; sleep 0.3
mkorch eps "$epid"
EW="$H/eps-wt"; git -C "$H/eps" worktree add -q "$EW" -b eps-team; EW=$(cd "$EW" && pwd -P); mkdir -p "$EW/.hivemind"
ew=$(hm_tmux new-window -d -P -F '#{pane_id}' -t keep: -n wimpl 'sleep 600'); ei=$(hm_pane_identity "$HM_TMUX_SOCKET" "$ew")
jq -nc --arg k "$HM_TMUX_SOCKET" --arg p "$ew" --arg pp "${ei%%$'\t'*}" --arg ps "${ei#*$'\t'}" '{agents:[{name:"wimpl", pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps}]}' > "$EW/.hivemind/team.json"
rec --json >/dev/null
hm_tmux kill-pane -t "$ew"; sleep 0.5
r=$(rec --json); assert_eq "an agent of a worktree team that stopped since the last beat: its orchestrator is told" "$(act "$r" | tr ',' '\n' | grep 'respawn:eps')" "respawn:eps"
assert_eq "...naming it" "$(printf '%s' "$r" | jq -r '[.actions[] | select(.action == "respawn" and .project == "eps")][0].agents | join(",")')" "wimpl"
# a Claude that is not the hub hub.json records does not recover, marker or not
CLX=$(mkcl "$DB" noself)
HM_AWAY_BYPASS=1 bash "$CLX" recover --json >/dev/null 2>"$T_TMP/n2.err"; assert_status "recover from a Claude that is not the recorded hub" $? 4
assert_contains "...says so" "$(cat "$T_TMP/n2.err")" "hub.json records"
# ...even when a jq first on PATH swears the caller is the recorded hub: the identity is read with the root-owned jq, never one from PATH
FJ="$T_TMP/fakejq"; mkdir -p "$FJ"
cat > "$FJ/jq" <<'J'
#!/bin/sh
# prints the nearest claude process above it as hub.json's claude_pid, and its start time as claude_started
c=$(ps -o ppid= -p $$ | tr -d ' ')   # from its parent up: its own arguments name claude_pid
while [ "$c" -gt 1 ]; do
  case "$(ps -o command= -p "$c")" in *claude*) break ;; esac
  c=$(ps -o ppid= -p "$c" | tr -d ' ')
done
case "$*" in
  *claude_pid*) echo "$c" ;;
  *claude_started*) LC_ALL=C ps -o lstart= -p "$c" | sed 's/^ *//;s/ *$//' ;;
esac
J
chmod +x "$FJ/jq"
PATH="$FJ:$PATH" HM_AWAY_BYPASS=1 bash "$CLX" recover --json >/dev/null 2>"$T_TMP/n3.err"; assert_status "recover from a Claude that is not the hub, with a fake jq first on PATH" $? 4
assert_contains "...is still refused as another session" "$(cat "$T_TMP/n3.err")" "hub.json records"
# recover reads every project's state without the hub's lock: a log meanwhile is not held up
tmx=$(command -v tmux); slow="$T_TMP/slow"; mkdir -p "$slow"; rm -f "$T_TMP/slow.done"
printf '#!/bin/sh\nif [ ! -e "%s/slow.done" ]; then touch "%s/slow.done"; sleep 4; fi\nexec "%s" "$@"\n' "$T_TMP" "$T_TMP" "$tmx" > "$slow/tmux"; chmod +x "$slow/tmux"
( PATH="$slow:$PATH" HM_AWAY_BYPASS=1 node "$CLN" recover --json > "$T_TMP/slowrec.out" 2>/dev/null ) & sr=$!; t_track "$sr"; sleep 1
t0=$(date +%s); hub log "$ta" note --note "while recover reads" >/dev/null 2>&1; lrc=$?; t1=$(date +%s)
assert_status "a log while recover is still reading state" "$lrc" 0
[ $((t1 - t0)) -le 2 ] && ok "...is not held up by it" || bad "the log waited $((t1 - t0)) s for the lock"
wait "$sr"; assert_eq "...and recover still finishes" "$(jq -r .away "$T_TMP/slowrec.out")" "true"
# a start waiting on a dialog is the owner's
dp=$(hm_open_window delta orchestrator "$H/delta" "exec claude" -e "HM_FAKE_CLAUDE=dialog" -e "HIVEMIND_HOME=$HIVEMIND_HOME" -e "HM_TMUX_SOCKET=$HM_TMUX_SOCKET"); sleep 1
di=$(hm_pane_identity "$HM_TMUX_SOCKET" "$dp"); mkdir -p "$P/panes"
jq -nc --arg p "$dp" --arg s "$HM_TMUX_SOCKET" --arg i "${di%%$'\t'*}" --arg t "${di#*$'\t'}" '{pane:$p, socket:$s, pane_pid:$i, pane_started:$t, kind:"wake", line:"x", typed:false, sender_pid:"1", sender_started:"x", at:"2026-10-06T00:00:00Z"}' > "$P/panes/delta.json"
r=$(rec --json)
assert_eq "a wake stopped at a dialog is listed for the owner" "$(printf '%s' "$r" | jq -r '[.actions[] | select(.action == "list" and .project == "delta")] | length')" "1"
rm -f "$P/panes/delta.json"; hm_tmux kill-pane -t "$dp"
# the caps count within a rolling 24 hours
rj="$P/recovery.jsonl"; : > "$rj"
for i in 1 2 3; do jq -nc --argjson e "$((NOW - 100 * i))" '{epoch:$e, action:"wake", item:"alpha"}' >> "$rj"; done
r=$(rec --json); assert_eq "woken 3 times in 24 hours and still stopped: blocked, not woken a fourth time" "$(act "$r" | tr ',' '\n' | grep -c wake:alpha)" "0"
assert_eq "...reported blocked, for the owner" "$(blk "$r" | tr ',' '\n' | grep wake:alpha)" "wake:alpha"
assert_contains "...with its reason" "$(printf '%s' "$r" | jq -r '[.blocked[] | select(.project == "alpha")][0].reason')" "3 times"
r=$(rec --json); assert_eq "...and said once: the next beat does not repeat it" "$(blk "$r" | tr ',' '\n' | grep -c wake:alpha)" "0"
: > "$rj"
for i in 1 2 3; do jq -nc --argjson e "$((NOW - 90000 - i))" '{epoch:$e, action:"wake", item:"alpha"}' >> "$rj"; done
r=$(rec --json); assert_eq "wakes older than 24 hours do not count" "$(act "$r" | tr ',' '\n' | grep -c wake:alpha)" "1"
: > "$rj"
jq -nc --argjson e "$((NOW - 50))" '{epoch:$e, action:"start", item:"beta"}' >> "$rj"; jq -nc --argjson e "$((NOW - 60))" '{epoch:$e, action:"wake", item:"gamma"}' >> "$rj"
r=$(rec --json --max-starts 2); assert_eq "the daily cap on sessions started or woken: blocked" "$(act "$r" | tr ',' '\n' | grep -c wake:alpha)" "0"
assert_contains "...with its reason" "$(printf '%s' "$r" | jq -r '[.blocked[] | select(.project == "alpha")][0].reason')" "daily cap of 2"
: > "$rj"; r=$(rec --json --max-starts 2); assert_eq "...under the cap it is woken" "$(act "$r" | tr ',' '\n' | grep -c wake:alpha)" "1"
r=$(rec --json --max-starts 1); assert_eq "two stopped orchestrators and room for one session: one is woken in this beat" "$(act "$r" | tr ',' '\n' | grep -c '^wake:')" "1"
assert_contains "...and the other is blocked on the daily cap" "$(printf '%s' "$r" | jq -r '[.blocked[] | select(.action == "wake")][0].reason')" "daily cap of 1"
hub recover --max-starts x >/dev/null 2>&1; assert_status "a daily cap that is a number" $? 4
t=$(rec); case "$t" in *"wake alpha (task $ta)"*) ok "the plain output names each action" ;; *) bad "plain recover: $t" ;; esac
# a hub started without the away marker does not recover; one started with it does; one whose environment cannot be read is refused
node "$CLN" recover --json >/dev/null 2>"$T_TMP/m.err"; assert_status "recover without the away marker" $? 4; assert_contains "...says why" "$(cat "$T_TMP/m.err")" "away marker"
HM_AWAY_BYPASS=1 node "$CLN" recover --json >/dev/null 2>"$T_TMP/m.err"; assert_status "recover with the away marker" $? 0
assert_eq "...and nothing said on stderr" "$(cat "$T_TMP/m.err")" ""
HM_AWAY_BYPASS=0 node "$CLN" recover --json >/dev/null 2>&1; assert_status "...a marker with another value is none" $? 4
env -i HM_AWAY_BYPASS=1 "$NODEBIN" "$CLN" recover --json >/dev/null 2>"$T_TMP/m.err"; assert_status "recover from a Claude whose environment shows no variables at all (cannot be read)" $? 4
assert_contains "...is refused, saying it cannot be read" "$(cat "$T_TMP/m.err")" "cannot be read"
# trust, for a project with a second repository (distinct from its home) and a worktree of its home
mk zeta; mk "zeta api"; git -C "$H/zeta" worktree add -q -b zwt "$H/zeta-wt"
hub add zeta --home zeta --repo "zeta api" --repo zeta-wt >/dev/null; assert_status "a project with a second repository and a worktree of its home" $? 0
jq -nc --arg t "$T_TMP" --arg h "$H" '{projects: ({($t):{hasTrustDialogAccepted:true}} + ([$h+"/alpha",$h+"/beta",$h+"/gamma",$h+"/delta",$h+"/zeta"] | map({(.):{hasTrustDialogAccepted:true}}) | add))}' > "$CLAUDE_CONFIG_DIR/.claude.json"
out3=$(hub away --until +1h)
assert_contains "away names a project's second repository that is not trusted, escaped for the shell the owner pastes it into" "$out3" "$H/zeta\\ api is not trusted by Claude Code yet"
case "$out3" in *"zeta-wt is not trusted"*) bad "a worktree whose main repository is trusted is named" ;; *) ok "...and not a worktree of the trusted home" ;; esac
jq -nc --arg t "$T_TMP" '{projects:{($t):{hasTrustDialogAccepted:true}}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
out4=$(hub away --until +1h)
assert_eq "a worktree and its main repository listed together give one line (one key)" "$(printf '%s\n' "$out4" | grep -c "Start claude in $H/zeta once")" "1"
rm -f "$CLAUDE_CONFIG_DIR/.claude.json"
# ---- hung sessions: positive evidence, then the stop (Phase 4.3, A10, A27) ----
# The screens are REAL captures (tests/fixtures/working/06-working-7s.ansi, "6s"; dialogs/07-idle-after-answer.ansi) drawn in a pane whose
# process is a `sleep` named claude. "Frozen for 15 minutes" is HAND-BUILT: a beat records the elapsed time it saw and when it first saw it
# (hung-state.json), and the test moves that time back, since waiting 15 real minutes is not a test.
HS="$P/hung-state.json"; WF="$HM_REPO_ROOT/tests/fixtures/working/06-working-7s.ansi"; IF="$HM_REPO_ROOT/tests/fixtures/dialogs/07-idle-after-answer.ansi"
: > "$rj"
hpane() {  # hpane <fixture> [trap] [claude]: a pane drawing the capture, then a process named claude (TERM ignored with "trap"); sets HPANE HPID HSTART
  local pre=""; [ "${2:-}" = trap ] && pre="trap '' TERM; "
  HPANE=$(hm_tmux new-window -d -P -F '#{pane_id}' -t keep: -n h "exec bash -c \"cat '$1'; ${pre}exec -a claude sleep 600\""); sleep 1
  local id; id=$(hm_pane_identity "$HM_TMUX_SOCKET" "$HPANE"); HPID=${id%%$'\t'*}; HSTART=${id#*$'\t'}; t_track "$HPID"
}
hagent() {  # hagent <project> <agent> <fixture> [trap]: a registered agent on such a pane
  hpane "$3" "${4:-}"
  jq --arg k "$HM_TMUX_SOCKET" --arg p "$HPANE" --arg pp "$HPID" --arg ps "$HSTART" --arg n "$2" '.agents += [{name:$n, pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps}]' \
    "$H/$1/.hivemind/team.json" > "$T_TMP/tj" && mv "$T_TMP/tj" "$H/$1/.hivemind/team.json"
}
ago() { jq --arg k "$1" --argjson d "$2" '.[$k].since -= $d' "$HS" > "$T_TMP/hs" && mv "$T_TMP/hs" "$HS"; }   # ago <key> <seconds>: first seen that long ago
restarts() { printf '%s' "$1" | jq -r '[.actions[] | select(.action == "restart") | .agents[]] | join(",")'; }
live() { hm_alive "$1" && [ "$(hm_lstart "$1")" = "$2" ]; }
hagent beta hung "$WF"; HUNG_PID=$HPID; HUNG_START=$HSTART
r=$(rec --json)
assert_eq "a frozen working line seen for the first time is not hung" "$(restarts "$r")" ""
assert_eq "...its elapsed time and the moment it was first seen are kept" "$(jq -r '.["beta/hung"] | "\(.pid) \(.secs)"' "$HS")" "$HUNG_PID 6"
ago beta/hung 850; r=$(rec --json)
assert_eq "frozen for 14 minutes: not yet hung" "$(restarts "$r")" ""
live "$HUNG_PID" "$HUNG_START" && ok "...and not stopped" || bad "stopped after 14 minutes"
ago beta/hung 110; r=$(rec --json)
assert_eq "frozen for 15 minutes: hung, and the agent is named for a restart" "$(restarts "$r")" "hung"
live "$HUNG_PID" "$HUNG_START" && bad "the hung session is still running" || ok "...its Claude was stopped"
assert_eq "...logged against the session, for the cap" "$(jq -s '[.[] | select(.action == "restart" and .item == "beta/hung")] | length' "$rj")" "1"
assert_eq "...its hung state is dropped" "$(jq -r '.["beta/hung"] // "none"' "$HS")" "none"
assert_contains "...and a hung agent is told as a restart, in plain words" "$(printf '%s' "$r" | jq -r '.actions[] | select(.action == "restart") | .why')" "hung"
r=$(rec --json); assert_eq "...once: the next beat does not restart or respawn it again" "$(restarts "$r")$(act "$r" | tr ',' '\n' | grep -c respawn)" "0"
# a hung agent of a team that sits in a worktree is found through that root's own team.json, and stopped
hpane "$WF"; WH_PID=$HPID; WH_START=$HSTART
jq --arg k "$HM_TMUX_SOCKET" --arg p "$HPANE" --arg pp "$HPID" --arg ps "$HSTART" '.agents += [{name:"whung", pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps}]' \
  "$EW/.hivemind/team.json" > "$T_TMP/tj" && mv "$T_TMP/tj" "$EW/.hivemind/team.json"
r=$(rec --json); ago eps/whung 1000; r=$(rec --json)
assert_eq "a frozen agent of a worktree team: named for a restart" "$(restarts "$r")" "whung"
live "$WH_PID" "$WH_START" && bad "the hung worktree agent is still running" || ok "...and its Claude was stopped"
# a timer that moved is not hung (A27): the state says 5s was seen 16 minutes ago, the screen now says 6s
hagent beta moving "$WF"; MV_PID=$HPID; MV_START=$HSTART
rec --json >/dev/null; ago beta/moving 960; jq '.["beta/moving"].secs = 5' "$HS" > "$T_TMP/hs" && mv "$T_TMP/hs" "$HS"
r=$(rec --json); assert_eq "a working line whose time moved is not hung" "$(restarts "$r")" ""
live "$MV_PID" "$MV_START" && ok "...and not stopped" || bad "a session whose timer moved was stopped"
assert_eq "...and counted again from now" "$(jq -r '.["beta/moving"].since >= '"$(( $(date +%s) - 5 ))"'' "$HS")" "true"
# a process that is not the one seen frozen (the pid reused, or the agent restarted by hand) starts the count again
ago beta/moving 960; jq '.["beta/moving"].started = "Mon Jan  1 00:00:00 2001"' "$HS" > "$T_TMP/hs" && mv "$T_TMP/hs" "$HS"
r=$(rec --json); assert_eq "frozen state recorded for another process (same pid, another start time) is not this one's" "$(restarts "$r")" ""
live "$MV_PID" "$MV_START" && ok "...and nothing was stopped" || bad "a process was stopped on another process's evidence"
# an unrecognised screen is unknown: never hung
hagent beta calm "$IF"; CALM_PID=$HPID; CALM_START=$HSTART
jq --arg p "$CALM_PID" --arg s "$CALM_START" '.["beta/calm"] = {pid:$p, started:$s, secs:6, since:1}' "$HS" > "$T_TMP/hs" && mv "$T_TMP/hs" "$HS"
r=$(rec --json); assert_eq "a screen with no working line is unknown, never hung, however long it has been still" "$(restarts "$r")" ""
live "$CALM_PID" "$CALM_START" && ok "...and not stopped" || bad "an unknown screen was stopped"
assert_eq "...and nothing is kept for it" "$(jq -r '.["beta/calm"] // "none"' "$HS")" "none"
# a project the owner holds is left alone
hagent beta held "$WF"; HELD_PID=$HPID; HELD_START=$HSTART
rec --json >/dev/null; ago beta/held 960; hub hold beta >/dev/null
r=$(rec --json); live "$HELD_PID" "$HELD_START" && ok "a held project's hung session is left alone" || bad "a held project's session was stopped"
hub hold beta --off >/dev/null
r=$(rec --json); assert_eq "...and when released it is watched afresh, not hung at once" "$(restarts "$r")" ""
ago beta/held 960; r=$(rec --json); assert_eq "...then hung" "$(restarts "$r")" "held"
# the caps: 3 restarts of one session in 24 hours, then blocked
hagent beta capd "$WF"; CAP_PID=$HPID; CAP_START=$HSTART
rec --json >/dev/null; ago beta/capd 960
for i in 1 2 3; do jq -nc --argjson e "$((NOW - 100 * i))" '{epoch:$e, action:"restart", item:"beta/capd"}' >> "$rj"; done
r=$(rec --json); assert_eq "restarted 3 times in 24 hours and hung again: not stopped" "$(restarts "$r")" ""
live "$CAP_PID" "$CAP_START" && ok "...it is left running" || bad "a session at its cap was stopped"
assert_eq "...and reported blocked, for the owner" "$(printf '%s' "$r" | jq -r '[.blocked[] | select(.action == "restart")][0].agents | join(",")')" "capd"
assert_contains "...with its reason" "$(printf '%s' "$r" | jq -r '[.blocked[] | select(.action == "restart")][0].reason')" "3 times"
r=$(rec --json); assert_eq "...said once: the next beat does not repeat it" "$(printf '%s' "$r" | jq -r '[.blocked[] | select(.action == "restart")] | length')" "0"
: > "$rj"; for i in 1 2 3; do jq -nc --argjson e "$((NOW - 90000 - i))" '{epoch:$e, action:"restart", item:"beta/capd"}' >> "$rj"; done; ago beta/capd 0
r=$(rec --json); assert_eq "three restarts older than 24 hours do not count" "$(restarts "$r")" "capd"
# an orchestrator is a session too: its Claude is the recorded claude pid, its screen the registered pane (the Claude runs under that pane's
# shell, as a --self orchestrator's does); it is woken, not respawned
printf 'cat "$1"; (exec -a claude sleep 600) & echo $! > "$2"; wait; exec sleep 600\n' > "$T_TMP/orch.sh"
opane=$(hm_tmux new-window -d -P -F '#{pane_id}' -t keep: -n orch "exec bash '$T_TMP/orch.sh' '$WF' '$T_TMP/oclaude.pid'"); sleep 1; oi=$(hm_pane_identity "$HM_TMUX_SOCKET" "$opane")
OC=$(cat "$T_TMP/oclaude.pid"); t_track "$OC"; OCS=$(hm_lstart "$OC"); BPS=$(jq -r '.agents[] | select(.name == "orchestrator") | .claude_started' "$H/beta/.hivemind/team.json")
setorch() {  # setorch <claude pid> <its start>: beta's orchestrator on the orch pane, with that Claude
  jq --arg p "$opane" --arg pp "${oi%%$'\t'*}" --arg ps "${oi#*$'\t'}" --arg c "$1" --arg cs "$2" \
    '(.agents[] | select(.name == "orchestrator")) |= (.pane = $p | .pane_pid = $pp | .pane_started = $ps | .claude_pid = $c | .claude_started = $cs)' \
    "$H/beta/.hivemind/team.json" > "$T_TMP/tj" && mv "$T_TMP/tj" "$H/beta/.hivemind/team.json"
}
# a frozen screen on a pane the recorded Claude is not under (a stale or edited team.json) stops nothing
setorch "$bpid" "$BPS"; : > "$rj"; rec --json >/dev/null; ago beta/orchestrator 960
r=$(rec --json); live "$bpid" "$BPS" && ok "a frozen pane tied to a Claude that is not under it stops nothing" || bad "a Claude that is not under the frozen pane was stopped"
assert_eq "...and no wake is asked" "$(act "$r" | tr ',' '\n' | grep -c wake:beta)" "0"
setorch "$OC" "$OCS"; rec --json >/dev/null; ago beta/orchestrator 960
# the daily cap of 3.3 applies to the wake that follows
jq -nc --argjson e "$((NOW - 50))" '{epoch:$e, action:"start", item:"alpha"}' >> "$rj"; jq -nc --argjson e "$((NOW - 60))" '{epoch:$e, action:"wake", item:"gamma"}' >> "$rj"
r=$(rec --json --max-starts 2); assert_eq "a hung orchestrator is not stopped when the daily cap of wakes is reached" "$(act "$r" | tr ',' '\n' | grep -c wake:beta)" "0"
live "$OC" "$OCS" && ok "...it is left running" || bad "an orchestrator was stopped with no room to wake it"
assert_contains "...and reported blocked, with the cap named" "$(printf '%s' "$r" | jq -r '[.blocked[] | select(.project == "beta")][0].reason')" "daily cap of 2"
r=$(rec --json --max-starts 2); assert_eq "...said once" "$(blk "$r" | tr ',' '\n' | grep -c wake:beta)" "0"
: > "$rj"
hub hold alpha >/dev/null   # beta (hung) comes before gamma (stopped); room for one session in this beat
r=$(rec --json --max-starts 1); assert_eq "a hung orchestrator is stopped and woken for its open task" "$(act "$r" | tr ',' '\n' | grep -c wake:beta)" "1"
assert_contains "...saying why" "$(printf '%s' "$r" | jq -r '[.actions[] | select(.action == "wake" and .project == "beta")][0].why')" "hung"
live "$OC" "$OCS" && bad "the orchestrator's Claude is still running" || ok "...its Claude was stopped"
hm_alive "${oi%%$'\t'*}" && ok "...its pane (the owner's shell) was not" || bad "the orchestrator's pane process was stopped: only its Claude is"
assert_eq "...logged against the session" "$(jq -s '[.[] | select(.action == "restart" and .item == "beta/orchestrator")] | length' "$rj")" "1"
assert_eq "...its wake took the last session of the day: the stopped orchestrator after it is not woken in the same beat" "$(act "$r" | tr ',' '\n' | grep -c wake:gamma)" "0"
assert_contains "...it is blocked on the daily cap" "$(printf '%s' "$r" | jq -r '[.blocked[] | select(.project == "gamma")][0].reason')" "daily cap of 1"
hub hold alpha --off >/dev/null
assert_eq "...hivemind ran no sudo anywhere" "$(cat "$HM_SUDO_LOG")" ""
t_done
