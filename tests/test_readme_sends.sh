#!/usr/bin/env bash
# The README says what hivehouse runs and sends, right after the delegate mode section, and the plugin's description is the same text in plugin.json
# and in both places of marketplace.json.
. "$(dirname "$0")/lib.sh"
t_setup
R="$HH_REPO_ROOT/README.md"
heads=$(grep -n '^## ' "$R" | sed 's/^[0-9]*://' | tr '\n' '|')
case "$heads" in *"## Delegate mode|## What hivehouse runs and sends|## Requirements"*) ok "the section sits between Delegate mode and Requirements" ;; *) bad "the section is not right after Delegate mode: $heads" ;; esac
sec=$(sed -n '/^## What hivehouse runs and sends$/,/^## Requirements$/p' "$R")
for w in "makes no network calls of its own" "sends nothing to us" "types into their panes" "Git worktrees and cleanup" "Bypass, only in delegate mode" "7 days at most" "A delete guard first in PATH" "docs/rm-guard.md" "Pushes only on your word" "never forced" "ssh, scp and rsync to your own machines" "remote_hosts" "Local files" "hooks/hub.tsx" "hub_auto_start" "is on by default" "takes one model turn" "The listed files replace what is there" "is never overwritten" "permission_mode_local" "the keys for the option you chose" "away-mcp.json" "mode 0600" "copies four things" "as a git bundle" "Claude memory files" "one secret file you name" "start-agent" "~/.claude.json" "~/.claude/settings.json" "launch environment of other Claude processes"; do
  assert_contains "the section says: $w" "$sec" "$w"
done
[ -f "$HH_REPO_ROOT/docs/rm-guard.md" ] && ok "the page the section links to exists" || bad "docs/rm-guard.md is missing"
EM=$(printf '\xe2\x80\x94'); EN=$(printf '\xe2\x80\x93')   # written as bytes so that this file holds neither character
case "$sec" in *"$EM"*|*"$EN"*) bad "the section has an em or en dash" ;; *) ok "the section has no em or en dash" ;; esac
D=$(jq -r .description "$HH_REPO_ROOT/.claude-plugin/plugin.json")
assert_eq "plugin.json's description" "$D" "An agent hub for Claude Code: one hub session passes each task to that project's team of Claude sessions in tmux, which plan, build, review and test on their own and leave pushes and spending to you."
assert_eq "marketplace.json's description is the same" "$(jq -r .description "$HH_REPO_ROOT/.claude-plugin/marketplace.json")" "$D"
assert_eq "...and so is its plugin entry's" "$(jq -r '.plugins[0].description' "$HH_REPO_ROOT/.claude-plugin/marketplace.json")" "$D"
cd /; t_teardown; t_done
