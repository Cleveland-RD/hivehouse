#!/usr/bin/env bash
# 0.5.1 sections E and C in the docs: the README keeps its promise line and lists every knob in one place, pitches delegate mode, says
# what away mode's allowances are and that an away agent can rewrite future roles and rules in custom/; RULES.md holds the one line
# for contributors. Held by grep so that a later edit cannot drop one silently.
. "$(dirname "$0")/lib.sh"
t_setup
echo "-- the README: the promise, the knobs, the delegate pitch, what an away agent can change"
RD=$(cat "$HH_REPO_ROOT/README.md" "$HH_REPO_ROOT/docs/hub.md" "$HH_REPO_ROOT/docs/away-mode.md" "$HH_REPO_ROOT/docs/customise.md" | tr '\n' ' ' | sed 's/  */ /g')
assert_contains "the promise line, word for word" "$RD" "Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you."
assert_eq "...once at the top of the README" "$(tr '\n' ' ' < "$HH_REPO_ROOT/README.md" | sed 's/  */ /g' | grep -o "Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you." | wc -l | tr -d ' ')" 1
assert_eq "...and once in docs/customise.md" "$(tr '\n' ' ' < "$HH_REPO_ROOT/docs/customise.md" | sed 's/  */ /g' | grep -o "Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you." | wc -l | tr -d ' ')" 1
sec=$(awk '/^# Customise hivehouse/{f=1;next} /^## /{f=0} f' "$HH_REPO_ROOT/docs/customise.md")
[ -n "$sec" ] && ok "docs/customise.md has a Customise hivehouse section" || bad "docs/customise.md has a Customise hivehouse section"
for k in $(jq -r '.userConfig | keys[]' "$HH_REPO_ROOT/.claude-plugin/plugin.json"); do
  assert_contains "the Customise section lists the option $k" "$sec" "$k"
done
for w in 'custom/' '--role' '--rules' '--remote-allow' '--allow' 'root-owned' 'plugin cache' 'hh-resolve'; do
  assert_contains "the Customise section mentions $w" "$sec" "$w"
done
assert_contains "the guide says an edit in the plugin cache is lost" "$(printf '%s' "$sec" | tr '\n' ' ' | sed 's/  */ /g')" "replaced by the next plugin update"
assert_contains "the guide says to print the sudo lines to loosen away mode" "$(printf '%s' "$sec" | tr '\n' ' ' | sed 's/  */ /g')" "never edit anything to get round it"
assert_contains "the hub's project level follows HH_PROJECT" "$(printf '%s' "$sec" | tr '\n' ' ' | sed 's/  */ /g')" "The project level follows \`hh_project_root\`, which honours \`HH_PROJECT\`; the away hub's start line sets \`HH_PROJECT=<the hub's folder>\`"
assert_contains "the principle: setup-specific behaviour is configuration, never code" "$(printf '%s' "$sec" | tr '\n' ' ' | sed 's/  */ /g')" "never a code change"
grep -qE '^#+ Delegate mode$|^## Delegate mode' "$HH_REPO_ROOT/README.md" && ok "the README has a Delegate mode pitch near the top" || bad "the README has a Delegate mode pitch near the top"
pitchline=$(grep -nE '^## Delegate mode$' "$HH_REPO_ROOT/README.md" | head -1 | cut -d: -f1); firstsec=$(grep -nE '^## Install$' "$HH_REPO_ROOT/README.md" | head -1 | cut -d: -f1)
[ -n "$pitchline" ] && [ -n "$firstsec" ] && [ "$pitchline" -lt "$firstsec" ] && ok "...above the install steps" || bad "...above the install steps"
pitch=$(awk '/^## Delegate mode$/{f=1;next} /^## /{f=0} f' "$HH_REPO_ROOT/README.md" | tr '\n' ' ' | sed 's/  */ /g')
assert_contains "the pitch: relay mode stays the default" "$pitch" "relay mode"
assert_contains "the pitch: it keeps pushes, deploys and spending for the owner" "$pitch" "pushes, deploys and spending"
grep -qE '^#+ Customising what away mode allows' "$HH_REPO_ROOT/docs/away-mode.md" && ok "the delegate section has Customising what away mode allows" || bad "the delegate section has Customising what away mode allows"
away=$(awk '/^#+ Customising what away mode allows/{f=1;next} /^#+ /{f=0} f' "$HH_REPO_ROOT/docs/away-mode.md" | tr '\n' ' ' | sed 's/  */ /g')
for w in '--remote-allow' '--allow' 'sudo' 'by hand' 'settings'; do assert_contains "Customising what away mode allows mentions $w" "$away" "$w"; done
assert_contains "the delegate file's version 5 is described" "$RD" "Line 1 is \`$T_DELEGATE_LINE5\`"
assert_contains "...with its allowance lines" "$RD" "\`hosts=<list>\`"
assert_contains "...and the tools line" "$RD" "\`tools=<list>\`"
assert_contains "...and the peers line" "$RD" "\`peers=<list>\`"
assert_contains "the docs state the hook's time limit and why" "$RD" "its check took longer than 20 seconds, so the call is refused"
assert_contains "the docs say the answer comes first on the pipes too, with a process group and temporary files" "$RD" "no leftover of the check can keep Claude Code's stdout or stderr open after the answer"
assert_contains "...and that a late hook does not stop the call" "$RD" "a hook that answers after its \`timeout\` does not stop the call"
assert_contains "the docs say hook=off acts after the call and the launch variables are read" "$RD" "after it has read the call and the session's launch variables"
assert_contains "...and the hook line" "$RD" "\`hook=on\` or \`hook=off\` (line 9"
assert_contains "...and a version 4 file is still read, with the hook on" "$RD" "version 4 file (0.5.4, the first eight lines) is still read, with the hook on"
assert_contains "--no-hook is in the switching-on usage line" "$(grep '^\*\*Switching it on and off.\*\*' "$HH_REPO_ROOT/docs/away-mode.md")" "[--no-hook]"
assert_contains "the docs say what hook=off turns off" "$RD" "makes none of its checks"
assert_contains "...and what stays" "$RD" "bypass launches still need the valid delegate file"
assert_contains "...and that the owner's own guard has to check" "$RD" "so the owner's own guard has to"
assert_contains "the switching-on usage line names --tools" "$(grep '^\*\*Switching it on and off.\*\*' "$HH_REPO_ROOT/docs/away-mode.md")" "[--tools <list>]"
assert_contains "...and version 1 is still read" "$RD" "is still read, with no hosts"
assert_contains "...and a file is exactly the lines of its version" "$RD" "exactly the lines of its version (four for version 1, six for version 2, seven for version 3, eight for version 4, nine for version 5, whose line 9 must be exactly \`hook=on\` or \`hook=off\`)"
assert_eq "...and no longer says the file is exactly four lines" "$(printf '%s' "$RD" | grep -c 'exactly those four lines')" 0
for w in '`ssh -F none [-T] [-o ConnectTimeout=<digits>] [-o BatchMode=yes] <host> <command>`' 'names from your `~/.ssh/config` are not usable while away' \
         '`git status` and `git diff` are not allowed' 'its first word must be one of a read-only list' '`~/.ssh/` is protected in away sessions' \
         '`--allow` is reserved in this release' 'refuses to print (exit 4, "allow= is reserved; no command is allowable in this version")' '`hh-hub status --json` shows the hosts in force' 'names `hh-hub away --tools`' '`CronCreate` and `ScheduleWakeup` always pass'; do
  assert_contains "Customising what away mode allows says: $w" "$away" "$w"
done
assert_contains "a script the call runs is read first" "$RD" "is read first and its text is checked by the same rules"
assert_contains "...and what the hook cannot read is refused" "$RD" "The hook refuses what it cannot read first: a shell fed by a pipe"
assert_contains "a program that runs another is not read" "$RD" "program that runs another (\`python -c\`, \`perl -e\`, \`awk\` with \`system()\`, \`make\`, a git alias) is not read"
assert_contains "\"| bash\" inside quoted text is refused too" "$RD" "\`| bash\` inside quoted text is refused the same way"
assert_contains "hh-hub start with no arguments is refused for every away session" "$RD" "\`hh-hub start\` with no arguments (it starts or attaches a hub) is refused for every away session, the hub included"
assert_contains "rotate, self and context are the hub's own" "$RD" "\`hh-hub rotate\`, \`hh-hub self\` and \`hh-hub context\` are refused for every away session except the hub's own"
assert_contains "the hub reads no custom file while away" "$RD" "gives the plugin's own file and never a custom one, and a delegate file that exists but is refused counts as away"
assert_contains "WebFetch is allowed only when listed" "$RD" "\`WebFetch\` is allowed only when the owner listed it with \`--tools\`"
assert_eq "...and the docs no longer say WebFetch stays allowed" "$(printf '%s' "$RD" | grep -c 'WebFetch\` and \`WebSearch\` stay allowed')" 0
assert_contains "the remote git reads need the three flags" "$away" "must carry \`--no-ext-diff --no-textconv --no-show-signature\`"
assert_contains "hh-hub status is not on the remote read list" "$away" "\`hh-hub status\` is not on the list: it runs \`git status\`"
assert_eq "...and the list names hh-hub tasks alone" "$(printf '%s' "$away" | grep -c 'hh-slot status\` and \`hh-hub tasks\`')" 1
assert_contains "scp, sftp and rsync to a remote stay refused whatever the file says" "$away" '`scp`, `sftp` and `rsync` to a remote stay refused while away, whatever the file says'
HUBSK=$(tr '\n' ' ' < "$HH_REPO_ROOT/skills/hub/SKILL.md" | sed 's/  */ /g')
assert_eq "the hub skill no longer says no remote host is used while away" "$(printf '%s' "$HUBSK" | grep -c 'no remote host is used')" 0
assert_contains "...it names the read-only ssh checks the owner allowed" "$HUBSK" "the only reach to a remote host is the read-only ssh checks the owner allowed with \`hh-hub away --remote-allow\`"
assert_contains "the hook list names the ssh exception" "$RD" "\`ssh\` (except the reads the owner allowed with \`--remote-allow\`, below)"
assert_contains "the hook list protects ~/.ssh/" "$RD" "a project's \`.mcp.json\` and \`~/.ssh/\`"
assert_contains "the heredoc rule is stated" "$RD" "Heredoc bodies are data, never commands, only when every command in the whole call"
assert_contains "N2: an away agent can rewrite future roles and rules in custom/" "$RD" "an away agent can rewrite its own team's, and another project's, future roles and rules in custom/"
assert_contains "N2: ...and says no grant is loosened by it" "$RD" "away grants come only from the root-owned delegate file"
assert_contains "D: messages to other machines stay cut off while away, said once" "$RD" "Messages to sessions on other machines stay cut off while away"
assert_eq "...and not said a second time" "$(printf '%s' "$RD" | grep -o 'sessions on other machines stay' | wc -l | tr -d ' ')" "1"

echo "-- rules/RULES.md: one line for contributors and agents"
RU=$(tr '\n' ' ' < "$HH_REPO_ROOT/rules/RULES.md" | sed 's/  */ /g')
assert_contains "a need specific to one setup is met by an option or a root-owned allowance" "$RU" "A need specific to one setup is met by an option or a root-owned allowance, not by code that names that setup."

t_done
