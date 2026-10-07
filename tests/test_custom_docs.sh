#!/usr/bin/env bash
# 0.5.1 sections E and C in the docs: the README keeps its promise line and lists every knob in one place, pitches delegate mode, says
# what away mode's allowances are and that an away agent can rewrite future roles and rules in custom/; RULES.md holds the one line
# for contributors. Held by grep so that a later edit cannot drop one silently.
. "$(dirname "$0")/lib.sh"
t_setup
echo "-- the README: the promise, the knobs, the delegate pitch, what an away agent can change"
RD=$(tr '\n' ' ' < "$HH_REPO_ROOT/README.md" | sed 's/  */ /g')
assert_contains "the promise line, word for word" "$RD" "Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you."
sec=$(awk '/^## Customise hivehouse/{f=1;next} /^## /{f=0} f' "$HH_REPO_ROOT/README.md")
[ -n "$sec" ] && ok "the README has a Customise hivehouse section" || bad "the README has a Customise hivehouse section"
for k in $(jq -r '.userConfig | keys[]' "$HH_REPO_ROOT/.claude-plugin/plugin.json"); do
  assert_contains "the Customise section lists the option $k" "$sec" "$k"
done
for w in 'custom/' '--role' '--rules' '--remote-allow' '--allow' 'root-owned' 'plugin cache' 'hh-resolve'; do
  assert_contains "the Customise section mentions $w" "$sec" "$w"
done
assert_contains "the guide says an edit in the plugin cache is lost" "$(printf '%s' "$sec" | tr '\n' ' ' | sed 's/  */ /g')" "replaced by the next plugin update"
assert_contains "the guide says to print the sudo lines to loosen away mode" "$(printf '%s' "$sec" | tr '\n' ' ' | sed 's/  */ /g')" "never edit anything to get round it"
assert_contains "the principle: setup-specific behaviour is configuration, never code" "$(printf '%s' "$sec" | tr '\n' ' ' | sed 's/  */ /g')" "never a code change"
grep -qE '^#+ Delegate mode$|^## Delegate mode' "$HH_REPO_ROOT/README.md" && ok "the README has a Delegate mode pitch near the top" || bad "the README has a Delegate mode pitch near the top"
pitchline=$(grep -nE '^## Delegate mode$' "$HH_REPO_ROOT/README.md" | head -1 | cut -d: -f1); firstsec=$(grep -nE '^## Install$' "$HH_REPO_ROOT/README.md" | head -1 | cut -d: -f1)
[ -n "$pitchline" ] && [ -n "$firstsec" ] && [ "$pitchline" -lt "$firstsec" ] && ok "...above the install steps" || bad "...above the install steps"
pitch=$(awk '/^## Delegate mode$/{f=1;next} /^## /{f=0} f' "$HH_REPO_ROOT/README.md" | tr '\n' ' ' | sed 's/  */ /g')
assert_contains "the pitch: relay mode stays the default" "$pitch" "relay mode"
assert_contains "the pitch: it keeps pushes, deploys and spending for the owner" "$pitch" "pushes, deploys and spending"
grep -qE '^#+ Customising what away mode allows' "$HH_REPO_ROOT/README.md" && ok "the delegate section has Customising what away mode allows" || bad "the delegate section has Customising what away mode allows"
away=$(awk '/^#+ Customising what away mode allows/{f=1;next} /^#+ /{f=0} f' "$HH_REPO_ROOT/README.md" | tr '\n' ' ' | sed 's/  */ /g')
for w in '--remote-allow' '--allow' 'sudo' 'by hand' 'settings'; do assert_contains "Customising what away mode allows mentions $w" "$away" "$w"; done
assert_contains "N2: an away agent can rewrite future roles and rules in custom/" "$RD" "an away agent can rewrite its own team's, and another project's, future roles and rules in custom/"
assert_contains "N2: ...and says no grant is loosened by it" "$RD" "away grants come only from the root-owned delegate file"
assert_contains "D: SendMessage to other machines stays cut off while away" "$RD" "SendMessage to sessions on other machines stays cut off while away"

echo "-- rules/RULES.md: one line for contributors and agents"
RU=$(tr '\n' ' ' < "$HH_REPO_ROOT/rules/RULES.md" | sed 's/  */ /g')
assert_contains "a need specific to one setup is met by an option or a root-owned allowance" "$RU" "A need specific to one setup is met by an option or a root-owned allowance, not by code that names that setup."

t_done
