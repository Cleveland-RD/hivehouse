#!/usr/bin/env bash
# What the rules, roles and skills tell an agent about the slot: queue with --wait, never retry by hand.
. "$(dirname "$0")/lib.sh"
t_setup
for f in rules/RULES.md skills/gate/SKILL.md skills/start/SKILL.md skills/overnight/SKILL.md skills/bubble-review/SKILL.md roles/implementer.md roles/fixer.md roles/reviewer.md; do
  grep -q 'hh-slot run --wait' "$HH_REPO_ROOT/$f" && ok "$f says hh-slot run --wait" || bad "$f does not say hh-slot run --wait"
done
grep -q 'hh-slot run <label>' "$HH_REPO_ROOT/rules/RULES.md" && bad "RULES still gives the form without --wait" || ok "RULES gives only the queueing form"
# no line gives the form without --wait: `hh-slot run <word> --`
for f in rules/RULES.md skills/gate/SKILL.md skills/start/SKILL.md skills/overnight/SKILL.md skills/bubble-review/SKILL.md roles/implementer.md roles/fixer.md roles/reviewer.md; do
  hits=$(grep -nE 'hh-slot run (<[a-z]+>|[a-z]+) --' "$HH_REPO_ROOT/$f")
  [ -z "$hits" ] && ok "$f: no hh-slot run without --wait" || bad "$f: $hits"
done
cd /; t_done
