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
# every place the orchestrator is told how to talk to the owner says how a message ends
for f in rules/RULES.md skills/start/SKILL.md skills/overnight/SKILL.md skills/overnight/morning-report.md skills/cleanup/SKILL.md; do
  grep -q '"Nothing needed from you."' "$f" && ok "$f: a message to the owner ends with what is needed" || bad "$f: does not say how a message to the owner ends"
done
# the two skills the hub starts for the owner say how the owner is reached through it, and with which words
for f in skills/overnight/SKILL.md skills/cleanup/SKILL.md; do
  t=$(tr '\n' ' ' < "$f" | tr -s ' ')
  for w in "Working through the owner's hub" "TASK <id>: HM-CLARIFY" "TASK <id>: HM-PLAN" "TASK <id>: DONE" "OWNER on TASK <id>:"; do
    assert_contains "$f: $w" "$t" "$w"
  done
done
assert_contains "overnight tells the hub a blocker" "$(tr '\n' ' ' < skills/overnight/SKILL.md | tr -s ' ')" "TASK <id>: BLOCKED"
assert_contains "a woken overnight orchestrator checks its heartbeat" "$(tr '\n' ' ' < skills/overnight/SKILL.md | tr -s ' ')" "run \`CronList\`"
# the hub skill says how a dialog is read and answered, and what it never picks
hubskill=$(tr '\n' ' ' < skills/hub/SKILL.md | tr -s ' ')
for w in "hm-hub dialog" "hm-hub answer" "--seen <fingerprint>" "Type something." "Tab to amend" "saves a permission rule" "Never pick for them" "already in an overnight run" "same fingerprint" "multi-select"; do
  assert_contains "the hub skill: $w" "$hubskill" "$w"
done
# delegate mode: every skill that takes replies from the hub can tell the hub's own decision from the owner's words
for f in skills/hub/SKILL.md skills/start/SKILL.md skills/overnight/SKILL.md skills/cleanup/SKILL.md; do
  assert_contains "$f: HUB on TASK <id>: is the hub's, not the owner's" "$(tr '\n' ' ' < "$f" | tr -s ' ')" "HUB on TASK <id>:"
done
for w in "hm-hub away" "hm-hub recover" "hm-hub decide" "printenv HM_AWAY_BYPASS" "never \`OWNER on TASK\`" "--max-starts" "decided while you were away" "hm-hub hold"; do
  assert_contains "the hub skill (delegate mode): $w" "$hubskill" "$w"
done
[ "$FAILS" -eq 0 ] || exit 1
