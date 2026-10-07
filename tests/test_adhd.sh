#!/usr/bin/env bash
# The optional i-have-adhd output style: used when Claude Code lists it as enabled, never installed or switched on.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
export HH_FAKE_PLUGIN_LIST="$T_TMP/plugins.json" HH_FAKE_PLUGIN_CALLS="$T_TMP/calls"
plug() {  # plug <dir>: an installed copy of the plugin with its skill file
  mkdir -p "$1/skills/i-have-adhd"; echo "rules" > "$1/skills/i-have-adhd/SKILL.md"
}
list() { printf '%s\n' "$1" > "$HH_FAKE_PLUGIN_LIST"; }
A="$T_TMP/cache/i-have-adhd/0.3.0"; plug "$A"
before=$(find "$CLAUDE_CONFIG_DIR" | sort)

list "[{\"id\":\"$T_PLUGIN@$T_PLUGIN\",\"enabled\":true,\"installPath\":\"/x\"},{\"id\":\"i-have-adhd@i-have-adhd\",\"enabled\":true,\"installPath\":\"$A\"}]"
assert_eq "enabled: its SKILL.md" "$(hh-adhd)" "$A/skills/i-have-adhd/SKILL.md"
assert_status "...exit 0" $? 0
assert_eq "it asks Claude Code one thing: plugin list --json" "$(cat "$T_TMP/calls")" "plugin list --json"
list "[{\"id\":\"i-have-adhd@i-have-adhd\",\"enabled\":false,\"installPath\":\"$A\"}]"
out=$(hh-adhd 2>/dev/null); rc=$?; assert_eq "disabled: nothing" "$out" ""; assert_status "...exit 1" $rc 1
list "[{\"id\":\"i-have-adhd@someone-else\",\"enabled\":true,\"installPath\":\"$A\"}]"
assert_eq "from another marketplace: found" "$(hh-adhd)" "$A/skills/i-have-adhd/SKILL.md"
list "[{\"id\":\"not-i-have-adhd@x\",\"enabled\":true,\"installPath\":\"$A\"}]"
hh-adhd >/dev/null 2>&1; assert_status "another plugin's name is not it" $? 1
B="$T_TMP/cache/other copy/0.2.0"; plug "$B"
list "[{\"id\":\"i-have-adhd@a\",\"enabled\":false,\"installPath\":\"$A\"},{\"id\":\"i-have-adhd@b\",\"enabled\":true,\"installPath\":\"$B\"}]"
assert_eq "two installs: the enabled one (a space in its path)" "$(hh-adhd)" "$B/skills/i-have-adhd/SKILL.md"
list "[{\"id\":\"i-have-adhd@i-have-adhd\",\"enabled\":true,\"installPath\":\"$T_TMP/gone\"}]"
hh-adhd >/dev/null 2>&1; assert_status "enabled but its file is missing: none" $? 1
list "[{\"id\":\"i-have-adhd@i-have-adhd\",\"enabled\":true}]"
hh-adhd >/dev/null 2>&1; assert_status "no install path: none" $? 1
list "not json"
out=$(hh-adhd 2>&1); rc=$?; assert_status "a listing that is not JSON: none" $rc 1; assert_eq "...quietly" "$out" ""
list "[{\"id\":\"i-have-adhd@i-have-adhd\",\"enabled\":true,\"installPath\":\"$A\"}]"
env PATH="$(getconf PATH)" sh -c "command -v claude" >/dev/null 2>&1 && bad "a claude on the system PATH spoils the next check" || ok "no claude on the system PATH"
out=$(env PATH="$HH_REPO_ROOT/bin:$(getconf PATH)" "$HH_REPO_ROOT/bin/hh-adhd" 2>&1); rc=$?
assert_status "no claude at all: none" $rc 1; assert_eq "...quietly" "$out" ""
# the always-on flag: the plugin applies itself to every session already, so it is not loaded twice
touch "$CLAUDE_CONFIG_DIR/.i-have-adhd-always"
out=$(hh-adhd 2>"$T_TMP/err"); rc=$?; assert_eq "always on: nothing" "$out" ""; assert_status "...exit 1" $rc 1
assert_contains "...and says why" "$(cat "$T_TMP/err")" "always on"
rm "$CLAUDE_CONFIG_DIR/.i-have-adhd-always"
assert_eq "it wrote nothing in the Claude config dir (no flag, ever)" "$(find "$CLAUDE_CONFIG_DIR" | sort)" "$before"

# the orchestrator's own pickup line reads it again after every clear; a spawned agent's never does
r=$(t_repo proj); mkdir -p "$r/$T_STATE"
echo '{"agents":[{"name":"orchestrator","claude_pid":"1","claude_started":"x","name_full":"orch"},{"name":"impl","pane":"%1"}]}' > "$r/$T_STATE/team.json"
assert_eq "the --self line names the style to follow" "$(hh_pickup_line proj "$r" orchestrator)" \
  "You are orch. Read $r/$T_STATE/handoffs/orchestrator.md from the top: its START HERE block is your prompt. Read $A/skills/i-have-adhd/SKILL.md and follow it for every message to the owner."
case "$(hh_pickup_line proj "$r" impl)" in *i-have-adhd*) bad "a spawned agent's line names the style" ;; *) ok "a spawned agent's line does not" ;; esac
list "[{\"id\":\"i-have-adhd@i-have-adhd\",\"enabled\":false,\"installPath\":\"$A\"}]"
assert_eq "not enabled: the short line alone" "$(hh_pickup_line proj "$r" orchestrator)" \
  "You are orch. Read $r/$T_STATE/handoffs/orchestrator.md from the top: its START HERE block is your prompt."
Q="$T_TMP/quo\"te"; plug "$Q"
list "$(jq -nc --arg p "$Q" '[{id:"i-have-adhd@i-have-adhd",enabled:true,installPath:$p}]')"
out=$(hh_pickup_line proj "$r" orchestrator 2>"$T_TMP/err")
assert_eq "a path with a quote is not typed: the short line" "$out" \
  "You are orch. Read $r/$T_STATE/handoffs/orchestrator.md from the top: its START HERE block is your prompt."
assert_eq "...and one line on stderr" "$(grep -c 'not one hivehouse will type' "$T_TMP/err")" "1"
cd /; t_teardown; t_done
