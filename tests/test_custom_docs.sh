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
assert_contains "the delegate file's version 2 is described" "$RD" "Line 1 is \`hivehouse-delegate 2\`"
assert_contains "...with its two allowance lines" "$RD" "\`hosts=<list>\`"
assert_contains "...and version 1 is still read" "$RD" "is still read, with no hosts and no allowed words"
assert_contains "...and a file is exactly the lines of its version" "$RD" "exactly the lines of its version (four for version 1, six for version 2)"
assert_eq "...and no longer says the file is exactly four lines" "$(printf '%s' "$RD" | grep -c 'exactly those four lines')" 0
for w in '`ssh -F none [-T] [-o ConnectTimeout=<digits>] [-o BatchMode=yes] <host> <command>`' 'names from your `~/.ssh/config` are not usable while away' \
         '`git status` and `git diff` are not allowed' 'its first word must be one of a read-only list' '`~/.ssh/` is protected in away sessions' \
         '`scp`, `rsync` or `sftp` from the refusal' '`hh-hub away` refuses to print (exit 4, naming the word or host)' '`hh-hub status --json` shows the hosts and words in force'; do
  assert_contains "Customising what away mode allows says: $w" "$away" "$w"
done
assert_contains "the remote git reads need the three flags" "$away" "must carry \`--no-ext-diff --no-textconv --no-show-signature\`"
assert_contains "hh-hub status is not on the remote read list" "$away" "\`hh-hub status\` is not on the list: it runs \`git status\`"
assert_eq "...and the list names hh-hub tasks alone" "$(printf '%s' "$away" | grep -c 'hh-slot status\` and \`hh-hub tasks\`')" 1
assert_contains "an allowed word lets only that command past its command-position refusal" "$away" "an allowed word lets only that command past its command-position refusal, every other rule still runs on the command, and it never applies to the remote part of an ssh command"
HUBSK=$(tr '\n' ' ' < "$HH_REPO_ROOT/skills/hub/SKILL.md" | sed 's/  */ /g')
assert_eq "the hub skill no longer says no remote host is used while away" "$(printf '%s' "$HUBSK" | grep -c 'no remote host is used')" 0
assert_contains "...it names the read-only ssh checks the owner allowed" "$HUBSK" "the only reach to a remote host is the read-only ssh checks the owner allowed with \`hh-hub away --remote-allow\`"
assert_contains "the hook list names the ssh exception" "$RD" "\`ssh\` (except the reads the owner allowed with \`--remote-allow\`, below)"
assert_contains "the hook list protects ~/.ssh/" "$RD" "a project's \`.mcp.json\` and \`~/.ssh/\`"
assert_contains "the heredoc rule is stated" "$RD" "A heredoc body is data, never commands, only when the command in front of"
assert_contains "N2: an away agent can rewrite future roles and rules in custom/" "$RD" "an away agent can rewrite its own team's, and another project's, future roles and rules in custom/"
assert_contains "N2: ...and says no grant is loosened by it" "$RD" "away grants come only from the root-owned delegate file"
assert_contains "D: SendMessage to other machines stays cut off while away" "$RD" "SendMessage to sessions on other machines stays cut off while away"

echo "-- rules/RULES.md: one line for contributors and agents"
RU=$(tr '\n' ' ' < "$HH_REPO_ROOT/rules/RULES.md" | sed 's/  */ /g')
assert_contains "a need specific to one setup is met by an option or a root-owned allowance" "$RU" "A need specific to one setup is met by an option or a root-owned allowance, not by code that names that setup."

t_done
