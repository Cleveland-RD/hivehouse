#!/usr/bin/env bash
# Wording the agents act on, pinned where drift once caused a bug: a builder gated uncommitted work and verified it without
# --commit (its role said nothing of either), and wrapped hm-gate in hm-slot run (the rules said every gate goes through it,
# while hm-gate takes the slot itself).
. "$(dirname "$0")/lib.sh"
cd "$HM_REPO_ROOT"
for f in roles/implementer.md roles/fixer.md; do
  assert_contains "$f: the gate is verified against the commit" "$(cat "$f")" "hm-gate-verify log <file> --commit <tip>"
done
assert_contains "the implementer commits before the gate" "$(cat roles/implementer.md)" "Commit first, then gate the clean, committed tip"
assert_contains "the fixer gates once committed" "$(tr '\n' ' ' < roles/fixer.md | tr -s ' ')" "then, once committed, the gate on the tip"
# no role, rule or skill puts hm-gate under hm-slot run: a list of what goes through the slot names no gate, and no
# example wraps hm-gate in it
OLD='(suites?|builds?), gates?|suite, gate|heavy jobs through `hm-slot`, gate|hm-slot run [^`]*hm-gate|gate under `hm-slot`, then'
hits=$(grep -rnE "$OLD" roles rules skills)
assert_eq "nothing says an hm-gate run goes through hm-slot run" "$hits" ""
for f in rules/RULES.md roles/implementer.md skills/start/SKILL.md skills/gate/SKILL.md; do
  tr '\n' ' ' < "$f" | tr -s ' ' | grep -q "slot itself" && ok "$f: hm-gate takes the slot itself" || bad "$f: does not say hm-gate takes the slot itself"
done
[ "$FAILS" -eq 0 ] || exit 1
