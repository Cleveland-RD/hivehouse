#!/usr/bin/env bash
# KI-36: Claude Code fills a skill's ${user_config.X} only from a saved value, so a skill that holds one must say what to do when it reads
# literally (run hh-settings option X), and must be allowed to run that command.
. "$(dirname "$0")/lib.sh"
t_setup
n=0
for f in "$HH_REPO_ROOT"/skills/*/SKILL.md; do
  grep -q '\${user_config\.' "$f" || continue
  n=$((n + 1)); s=$(basename "$(dirname "$f")")
  assert_contains "skill $s: says what to do with a placeholder that reads literally" "$(tr '\n' ' ' < "$f" | tr -s ' ')" 'still reads literally'
  assert_contains "skill $s: ...naming hh-settings option" "$(tr '\n' ' ' < "$f" | tr -s ' ')" 'hh-settings option'
  assert_contains "skill $s: ...and allowed to run it" "$(sed -n 1,12p "$f" | grep '^allowed-tools:')" 'Bash(hh-settings option *)'
done
[ "$n" -ge 6 ] && ok "$n skills hold a \${user_config.*} placeholder" || bad "only $n skills hold a placeholder"
t_teardown; t_done
