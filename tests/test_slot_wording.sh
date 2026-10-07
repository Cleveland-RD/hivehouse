#!/usr/bin/env bash
# What the rules, roles and skills tell an agent about the slot: queue with --wait, never retry by hand.
. "$(dirname "$0")/lib.sh"
t_setup
for f in rules/RULES.md skills/gate/SKILL.md skills/start/SKILL.md skills/overnight/SKILL.md skills/bubble-review/SKILL.md roles/implementer.md roles/fixer.md roles/reviewer.md; do
  grep -q 'hm-slot run --wait' "$HM_REPO_ROOT/$f" && ok "$f says hm-slot run --wait" || bad "$f does not say hm-slot run --wait"
done
grep -q 'hm-slot run <label>' "$HM_REPO_ROOT/rules/RULES.md" && bad "RULES still gives the form without --wait" || ok "RULES gives only the queueing form"
cd /; t_done
