#!/usr/bin/env bash
# 0.5.1 section E: every skill that names a role, the rules or the brief template asks the one resolver (hh-resolve) for it, and
# grants itself that command. The list is the plan's S1 list, found by grep of roles/, RULES.md and brief-template over skills/ and bin/.
. "$(dirname "$0")/lib.sh"
t_setup
echo "-- every skill that names a role, the rules or the brief template asks the resolver (the plan's S1 list)"
for s in start overnight bubble-review handoff cleanup gate hub; do
  f="$HH_REPO_ROOT/skills/$s/SKILL.md"
  assert_eq "skills/$s names no plugin file for a role, rules or brief directly" "$(grep -cE '\$\{CLAUDE_PLUGIN_ROOT\}/(rules|roles)/' "$f")" 0
  assert_contains "skills/$s asks hh-resolve" "$(cat "$f")" "hh-resolve"
  assert_contains "skills/$s grants it to itself" "$(sed -n 's/^allowed-tools: //p' "$f" | head -1)" "Bash(hh-resolve *)"
done
assert_contains "the start skill passes the resolved role and rules to hh-spawn" "$(cat "$HH_REPO_ROOT/skills/start/SKILL.md")" "hh-resolve role"
assert_contains "the bubble-review skill resolves the reviewer role" "$(cat "$HH_REPO_ROOT/skills/bubble-review/SKILL.md")" "hh-resolve role reviewer"
assert_contains "the overnight skill resolves the brief template" "$(cat "$HH_REPO_ROOT/skills/overnight/SKILL.md")" "hh-resolve brief"
assert_contains "the start skill resolves the brief template" "$(cat "$HH_REPO_ROOT/skills/start/SKILL.md")" "hh-resolve brief"
assert_eq "no other skill or executable names the plugin's roles or rules folder to read from" \
  "$(cd "$HH_REPO_ROOT" && grep -rnE 'CLAUDE_PLUGIN_ROOT\}?/(rules|roles)/' skills bin | grep -v 'hh-resolve' | wc -l | tr -d ' ')" 0

t_done
