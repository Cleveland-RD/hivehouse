#!/usr/bin/env bash
# hh-away-hook: the PreToolUse hook of a session launched in bypass while the owner is away. It reads the launch marker and
# the launch env, never the Bash env; it matches by tokens and does not claim to be complete (A43).
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
proj=$(t_repo proj); hub="$T_TMP/hub"; mkdir -p "$hub/$T_HUB" "$proj/$T_STATE"
other=$(t_repo other); mkdir -p "$other/$T_STATE"
# Stand-ins for Claude sessions: an interpreter running a script named claude (what hh_is_claude reads as one).
mkdir -p "$T_TMP/cl"; printf '#!/usr/bin/env bash\nfor i in $(seq 120); do sleep 1; done\n' > "$T_TMP/cl/claude"
SP=""; SS=""
spawn() {  # spawn <session name or empty>: sets SP (pid) and SS (start time); records the session as Claude Code does
  bash "$T_TMP/cl/claude" & SP=$!; t_track "$SP"; sleep 0.2; SS=$(hh_lstart "$SP")
  mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
  [ -z "$1" ] || jq -nc --argjson p "$SP" --arg n "$1" '{pid:$p,name:$n}' > "$CLAUDE_CONFIG_DIR/sessions/$SP.json"
}
spawn hub1; HP=$SP; HS=$SS
spawn proj-orchestrator; OP=$SP; OS=$SS
spawn proj-implementer; IP=$SP; IS=$SS
spawn other-orchestrator; XP=$SP; XS=$SS
sleep 1.1; spawn stranger; SGP=$SP; SGS=$SS
jq -nc --arg p "$HP" --arg s "$HS" '{name:"hub1",claude_pid:$p,claude_started:$s}' > "$hub/$T_HUB/hub.json"
jq -nc --arg a "$proj" --arg b "$other" '{projects:[{name:"proj",home:$a,repos:[]},{name:"other",home:$b,repos:[]}]}' > "$hub/$T_HUB/projects.json"
jq -nc --arg op "$OP" --arg os "$OS" --arg ip "$IP" --arg is "$IS" --arg sg "$SGP" \
  '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"proj-orchestrator",pane_pid:"1",pane_started:"x"},
            {name:"implementer",pane_pid:$ip,pane_started:$is},
            {name:"reused",pane_pid:$sg,pane_started:"Mon Jan  1 00:00:00 2001"}]}' > "$proj/$T_STATE/team.json"
jq -nc --arg op "$XP" --arg os "$XS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"other-orchestrator",pane_pid:"1",pane_started:"x"}]}' > "$other/$T_STATE/team.json"
HOOK="${HH_AWAY_HOOK_TEST:-$HH_REPO_ROOT/bin/hh-away-hook}"
ALLOW=""; ROLE=proj
hook() {  # hook <json>: the hook as a marked session of $ROLE; sets RC and ERR
  local pr="$proj"; [ "$ROLE" != hub ] || pr="$hub"
  ERR=$(printf '%s' "$1" | HH_AWAY_BYPASS=1 HH_PROJECT="$pr" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW="$ALLOW" "$HOOK" 2>&1 >/dev/null); RC=$?
}
tc() { jq -nc --arg c "$1" --arg d "$proj" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
denied()  { hook "$(tc "$2")"; [ "$RC" -eq 2 ] && [ -n "$ERR" ] && ok "$1" || bad "$1: exit $RC [$ERR]"; }
allowed() { hook "$(tc "$2")"; [ "$RC" -eq 0 ] && ok "$1" || bad "$1: exit $RC [$ERR]"; }
tool_denied()  { hook "$2"; [ "$RC" -eq 2 ] && [ -n "$ERR" ] && ok "$1" || bad "$1: exit $RC [$ERR]"; }
tool_allowed() { hook "$2"; [ "$RC" -eq 0 ] && ok "$1" || bad "$1: exit $RC [$ERR]"; }
mcp() { jq -nc --arg t "$1" '{tool_name:$t,cwd:"/",tool_input:{}}'; }
msg() { jq -nc --arg t "$1" '{tool_name:"SendMessage",cwd:"/",tool_input:{to:$t,message:"hi"}}'; }
fileop() { jq -nc --arg t "$1" --arg f "$2" --arg d "$proj" '{tool_name:$t,cwd:$d,tool_input:{file_path:$f,content:"x"}}'; }

echo "-- no marker: exits 0 at once, whatever it is given"
r=$(printf 'not json' | env -u HH_AWAY_BYPASS "$HOOK" 2>&1); assert_status "no marker, bad input" $? 0
assert_eq "no marker, silent" "$r" ""
printf '%s' "$(tc 'git push')" | env -u HH_AWAY_BYPASS "$HOOK" 2>&1; assert_status "no marker, git push" $? 0
printf '%s' "$(tc 'git push')" | HH_AWAY_BYPASS=0 "$HOOK" 2>&1; assert_status "marker 0 is no marker" $? 0
printf '%s' "$(tc 'git push')" | HH_AWAY_BYPASS= "$HOOK" 2>&1; assert_status "empty marker is no marker" $? 0

head -c 400000 /dev/zero | env -u HH_AWAY_BYPASS "$HOOK"; assert_eq "S5 the fast path drains its input (the writer is not hit by SIGPIPE)" "${PIPESTATUS[0]}" 0
echo "-- the hook ignores BASH_ENV and starts under bash -p, like the other executables"
printf 'HH_AWAY_BYPASS=0\n' > "$T_TMP/benv.sh"
r=$(printf '%s' "$(tc 'git push')" | BASH_ENV="$T_TMP/benv.sh" HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "a BASH_ENV that unsets the marker does not turn the hook off" $? 2
mkdir "$T_TMP/dn"; printf '#!/bin/sh\necho /nonexistent\n' > "$T_TMP/dn/dirname"; chmod +x "$T_TMP/dn/dirname"
r=$(printf '%s' "$(tc 'ls')" | PATH="$T_TMP/dn:$PATH" HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "a dirname first on PATH cannot move where the hook finds hh-lib.sh" $? 0
assert_eq "the hook's first line is #!/bin/bash -p" "$(head -1 "$HH_REPO_ROOT/bin/hh-away-hook")" "#!/bin/bash -p"
echo "-- fail closed (A9)"
hook 'not json'; assert_status "marker, input not json" $RC 2
hook '{"cwd":"/"}'; assert_status "marker, no tool name" $RC 2
hook '{"tool_name":"Bash","tool_input":{}}'; assert_status "Bash with no command" $RC 2
hook '{"tool_name":"Bash","tool_input":{"command":5}}'; assert_status "Bash with a non-string command" $RC 2
hook '{"tool_name":"Read","cwd":"/","tool_input":{}}'; assert_status "a tool outside its matcher" $RC 2
r=$(printf '%s' "$(tc ls)" | HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1); assert_status "no hub folder in the env" $? 2
r=$(printf '%s' "$(tc ls)" | HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$other" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1); assert_status "hub folder with no $T_HUB" $? 2
r=$(printf '%s' "$(tc ls)" | HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$T_TMP/none" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1); assert_status "hub folder that does not exist" $? 2
mkdir -p "$T_TMP/nojq"; for b in bash cat dirname basename ps sed tr grep sleep; do ln -sf "$(command -v $b)" "$T_TMP/nojq/$b"; done
# a PATH without jq changes nothing (the hook fixes its own); what denies is no root-owned jq at the three fixed paths (tests/test_jq_fixed.sh has the rest)
r=$(printf '%s' "$(tc ls)" | PATH="$T_TMP/nojq" HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$(command -v bash)" "$HOOK" 2>&1); assert_status "a PATH with no jq on it: the hook still finds the root-owned one" $? 0
NJ=$(t_jq_bin nojqbin "/nonexistent/jq")
r=$(printf '%s' "$(tc ls)" | HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$NJ/hh-away-hook" 2>&1); assert_status "jq missing" $? 2
assert_contains "jq missing says so" "$r" "jq"
r=$(printf '%s' "$(fileop Write "$proj/a.ts")" | env -u HOME HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); rc=$?
assert_status "an internal failure (no HOME) is a denial, not exit 1" $rc 2
mkdir -p "$T_TMP/nolib"; cp "$HOOK" "$T_TMP/nolib/hh-away-hook"
r=$(printf '%s' "$(tc ls)" | HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$T_TMP/nolib/hh-away-hook" 2>&1 >/dev/null); assert_status "a missing library is a denial" $? 2
allowed "plain ls is allowed" "ls -la"
for c in 'grep -rn vercel src' 'git commit -m "chore(vercel): bump"' 'grep -n ssh bin/hh-spawn' 'cat ssh_config' 'echo netlify scp' 'git log --grep=ssh'; do allowed "S1 a word that is not the command: $c" "$c"; done
for c in 'sh -c "ssh host"' 'xargs scp a' 'hh-slot run x -- ssh h' 'echo a | ssh h' 'FOO=1 vercel' 'nohup netlify deploy' 'true && scp a h:b' 'bash -c "vercel --prod"'; do denied "S1 the command position: $c" "$c"; done
allowed "S4 setup check: ls with the project set" "ls"

for pr in "" unset; do
  if [ "$pr" = unset ]; then r=$(printf '%s' "$(tc ls)" | env -u HH_PROJECT HH_AWAY_BYPASS=1 HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1)
  else r=$(printf '%s' "$(tc ls)" | HH_AWAY_BYPASS=1 HH_PROJECT= HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1); fi
  assert_status "S4 a marked session with HH_PROJECT '${pr:-empty}' is refused" $? 2
done
echo "-- git push (A22, A32, A38)"
for c in 'git push' 'git push origin main' 'git -C /tmp/x push' 'git push origin HEAD:main' 'git push +main' 'git push :main' 'git push --delete origin x' \
  'git push --all' 'git push --mirror' '/usr/bin/git push' 'command git push' 'exec git push' 'nohup git push' 'env GIT_X=1 git push' \
  'sh -c "git push"' "bash -c 'git push'" "zsh -c 'git push'" 'eval "git push"' 'echo x | xargs git push' 'echo $(git push)' 'echo `git push`' \
  'alias g=git; g push' 'true && git push' 'git status; git push' "g''it push" 'g"i"t push' 'gi\t push' "git 'push'" 'git commit -m "fix(push): x"' 'git log --grep=push'; do
  denied "git push form: $c" "$c"
done
printf '%s' "$ERR" | grep -q . && assert_contains "the refusal says why" "$ERR" "git push"
echo "-- git and push words that are not the pair"
allowed "git add bin/hh-push" 'git add bin/hh-push'
allowed "git diff -- tests/test_push.sh" 'git diff -- tests/test_push.sh'
allowed "git status" 'git status'
allowed "git commit without push" 'git commit -m "feat: add the thing"'
allowed "bash tests/run.sh test_push.sh" 'bash tests/run.sh test_push.sh'
allowed "cat bin/hh-push" 'cat bin/hh-push'

echo "-- hh-push and hh-remote-sync (A32, A38)"
for c in 'hh-push origin abc main' 'bin/hh-push origin abc main' './bin/hh-push x' "''hh-push x" 'hh-""push x' 'FOO=1 hh-push x' 'env hh-push x' 'nohup hh-push x' 'bash -c "hh-push x"' \
  'xargs hh-push' 'true; hh-push x' 'echo a && bin/hh-push x' 'xargs -n1 hh-push' 'timeout 5 hh-push x' 'sudo -n hh-push x' 'hh-slot run push -- hh-push origin a b' 'hh-remote-sync status' 'time hh-push x'; do
  denied "hh-push form: $c" "$c"
done
allowed "hh-push as an argument of git add" 'git add bin/hh-push'
allowed "hh-push inside a commit message" 'git commit -m "docs: about hh-push"'
allowed "the team's own hh-slot traffic" 'hh-slot run gate -- hh-gate'
allowed "hh-gate-verify" 'hh-gate-verify log /tmp/x.log --commit abc'

echo "-- gh (A21)"
for c in 'gh pr create' 'gh pr merge 3' 'gh api repos/x/y' 'gh issue create' 'gh release create v1' 'gh pr view 3 && gh pr merge 3' 'sh -c "gh pr merge"'; do denied "gh form: $c" "$c"; done
for c in 'gh pr view 3' 'gh pr list' 'gh pr status' 'gh pr diff 3' 'gh pr checks 3' 'gh run view 5' 'gh run list' 'gh issue view 2' 'gh issue list'; do allowed "gh read-only: $c" "$c"; done

echo "-- the rest of A21"
for c in 'ssh host ls' '/usr/bin/ssh host' 'scp a host:b' 'rsync -a a host:b' 'rsync -e ssh a b' 'rsync a rsync://h/m' 'curl -X POST http://x' 'curl -XPUT http://x' 'curl -d a=b http://x' \
  'curl --data a http://x' 'curl --data-binary @f http://x' 'curl -F f=@x http://x' 'curl -T f http://x' 'curl --upload-file f http://x' 'curl --request=DELETE http://x' 'curl -sd a http://x' 'curl --json {} http://x' \
  'wget --post-data=a http://x' 'wget --post-file=f http://x' 'wget --method=PUT http://x' 'npm publish' 'pnpm publish' 'yarn publish' 'npx npm publish' 'vercel deploy' 'vercel' 'netlify deploy' 'docker push img'; do
  denied "A21 form: $c" "$c"
done
for c in 'curl http://localhost:3000' 'curl -X GET http://x' 'curl -s -o /dev/null http://x' 'wget http://x' 'rsync -a a/ b/' 'npm test' 'npm install' 'yarn build' 'docker build .' 'docker ps' 'curl http://x | grep -F foo'; do allowed "A21 allowed: $c" "$c"; done

echo "-- the way out of the marker (A52)"
for c in 'claude' 'claude --permission-mode bypassPermissions' '/usr/local/bin/claude -p hi' 'env X=1 claude' 'nohup claude &' 'bash -c "claude"' \
  'tmux new-window claude' 'tmux split-window -h' 'tmux new-session -d' 'tmux respawn-pane -k' 'tmux respawn-window' 'tmux neww' 'tmux -S /x new-window'; do denied "way out: $c" "$c"; done
for c in 'tmux run-shell "claude x"' 'tmux run x' 'tmux if-shell true x' 'tmux if x' 'tmux display-popup' 'tmux popup' 'tmux pipe-pane x' 'tmux pipep x' 'tmux source-file x' 'tmux source x' 'tmux send-keys -t %0 "hh-push x" Enter' 'tmux send x'; do denied "S2 tmux way out: $c" "$c"; done
allowed "tmux list-panes" 'tmux list-panes -a'
allowed "which claude" 'which claude'
allowed "hh-spawn" 'hh-spawn --agent x --role implementer'

echo "-- protected files, by Bash (A52, A57, A61)"
CD="$CLAUDE_CONFIG_DIR"
for c in "echo {} > $CD/settings.json" "echo {} >> $CD/settings.local.json" 'echo {} > ~/.claude/settings.json' 'echo {} > $HOME/.claude.json' 'echo x > ~/.claude.json' 'echo x > ${HOME}/.claude.json' 'cp a ~/.claude.json' 'cp a $HOME/.claude.json' 'echo {} > .claude/settings.json' \
  'echo x > .claude/settings.local.json' 'echo x > .mcp.json' "tee $CD/settings.json" "sed -i s/a/b/ $CD/settings.json" "cp a $CD/plugins/x/hooks.json" "mv x $CD/plugins/y" 'echo x > hooks/hooks.json' \
  'echo x > .claude/hooks/pre.sh' "echo x > '$CD/settings.json'" "echo x >$CD/settings.json" 'cp a .mcp.json' "python3 -c x $CD/settings.json" "echo x > $CD/plugins/cache/p/hooks/hooks.json"; do
  denied "protected write: $c" "$c"
done
denied "S3 .claude.json in the config dir (redirect)" "echo x > $CD/.claude.json"
denied "S3 hooks/ in the config dir (cp)" "cp a $CD/hooks/x.sh"
ln -s "$CD/settings.json" "$T_TMP/lnk-settings"; ln -s "$T_TMP/loop2" "$T_TMP/loop1"; ln -s "$T_TMP/loop1" "$T_TMP/loop2"
ln -s "$T_TMP/lnk-settings" "$T_TMP/lnk-chain"; : > "$T_TMP/harmless"; ln -s "$T_TMP/harmless" "$T_TMP/lnk-harmless"
ln -s settings.json "$CD/lnk-rel"
denied "S3 a redirect through a relative symlink to settings.json" "echo x > $CD/lnk-rel"
denied "S3 a redirect through a symlink to settings.json" "echo x > $T_TMP/lnk-settings"
denied "S3 a redirect through a chain of symlinks" "echo x > $T_TMP/lnk-chain"
denied "S3 a link loop" "echo x > $T_TMP/loop1"
allowed "S3 a link to a harmless file" "echo x > $T_TMP/lnk-harmless"
allowed "reading settings" "cat $CD/settings.json"
allowed "jq on settings" "jq . $CD/settings.json"
allowed "memory stays writable" "echo x > $CD/projects/p/memory/note.md"
allowed "an ordinary redirect" 'echo x > /tmp/a.txt'
allowed "grep in the plugins folder" "grep -r x $CD/plugins"

echo "-- protected files, by Edit and Write (A52, A57, A61)"
for t in Edit Write MultiEdit NotebookEdit; do tool_denied "$t on settings.json in the config dir" "$(fileop $t "$CD/settings.json")"; done
tool_denied "Write to settings.local.json" "$(fileop Write "$CD/settings.local.json")"
tool_denied "Write to the project's .claude/settings.json" "$(fileop Write "$proj/.claude/settings.json")"
tool_denied "Write to a relative .claude/settings.local.json" "$(fileop Write ".claude/settings.local.json")"
tool_denied "Write to ~/.claude.json" "$(fileop Write "$HOME/.claude.json")"
tool_denied "Write to ~/.claude.json written with ~" "$(fileop Write "~/.claude.json")"
tool_denied "Write to the project's .mcp.json" "$(fileop Write "$proj/.mcp.json")"
tool_denied "Write to hooks.json" "$(fileop Write "$proj/hooks/hooks.json")"
tool_denied "Write to a hook script" "$(fileop Write "$proj/.claude/hooks/x.sh")"
tool_denied "Write into the plugins folder" "$(fileop Write "$CD/plugins/cache/x/bin/y")"
tool_denied "Write through .." "$(fileop Write "$CD/../$(basename "$CD")/settings.json")"
mkdir -p "$T_TMP/real-conf"; ln -s "$CD" "$T_TMP/linkdir"
tool_denied "S3 Write to .claude.json in the config dir" "$(fileop Write "$CD/.claude.json")"
tool_denied "S3 Write to hooks/ in the config dir" "$(fileop Write "$CD/hooks/x.sh")"
tool_denied "S3 Write through a symlink to settings.json" "$(fileop Write "$T_TMP/lnk-settings")"
tool_denied "S3 Write through a link loop" "$(fileop Write "$T_TMP/loop1")"
tool_allowed "S3 Write through a link to a harmless file" "$(fileop Write "$T_TMP/lnk-harmless")"
tool_denied "Write through a link to the config dir" "$(fileop Write "$T_TMP/linkdir/settings.json")"
mkdir -p "$proj/pl/bin"; PROOT="$proj/pl"
ERR=$(printf '%s' "$(fileop Write "$PROOT/bin/x")" | HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= CLAUDE_PLUGIN_ROOT="$PROOT" "$HOOK" 2>&1 >/dev/null); [ $? -eq 2 ] && ok "Write into the plugin's own folder" || bad "plugin root write allowed"
tool_allowed "Write to an ordinary project file" "$(fileop Write "$proj/src/a.ts")"
tool_allowed "Edit of an ordinary file" "$(fileop Edit "$proj/README")"
tool_allowed "Write to memory" "$(fileop Write "$CD/projects/p/memory/n.md")"
tool_allowed "Write to settings.json inside an unrelated folder" "$(fileop Write "$proj/docs/settings.json")"
tool_denied "Write with no path" '{"tool_name":"Write","cwd":"/","tool_input":{}}'

echo "-- the hub's records and a team's team.json are written by hivehouse's scripts, never by a session's tools (final review S1)"
# hub.json is the identity away_hub_caller checks and the "own hub" a SendMessage resolves by pid; projects.json lists what the hub may
# bypass; team.json names every agent's process. A marked agent that could write them could pass as the hub.
HR="$hub/$T_HUB"; echo '{}' > "$HR/tasks.jsonl"; mkdir -p "$HR/memory"
ln -s "$HR/hub.json" "$T_TMP/lnk-hubjson"; ln -s "$HR" "$T_TMP/lnk-hubdir"; ln -s "$proj/$T_STATE/team.json" "$T_TMP/lnk-teamjson"
ROLE=proj
for t in Edit Write MultiEdit NotebookEdit; do tool_denied "an agent's $t on hub.json" "$(fileop $t "$HR/hub.json")"; done
tool_denied "an agent's Write to projects.json" "$(fileop Write "$HR/projects.json")"
tool_denied "an agent's Write to the hub's tasks ledger" "$(fileop Write "$HR/tasks.jsonl")"
tool_denied "an agent's Write to the hub's memory folder" "$(fileop Write "$HR/memory/n.md")"
tool_denied "an agent's Write through a link to hub.json" "$(fileop Write "$T_TMP/lnk-hubjson")"
tool_denied "an agent's Write through a link to the hub's records folder" "$(fileop Write "$T_TMP/lnk-hubdir/hub.json")"
tool_denied "an agent's Write through .." "$(fileop Write "$hub/x/../$T_HUB/hub.json")"
denied "an agent's redirect into hub.json" "echo x > $HR/hub.json"
denied "an agent's tee into projects.json" "tee $HR/projects.json"
denied "an agent's cp onto hub.json" "cp a $HR/hub.json"
denied "an agent's sed -i on the ledger" "sed -i s/a/b/ $HR/tasks.jsonl"
denied "an agent's redirect through a link to hub.json" "echo x > $T_TMP/lnk-hubjson"
allowed "an agent reads hub.json" "cat $HR/hub.json"
tool_allowed "an agent's Write to its own handoff" "$(fileop Write "$proj/$T_STATE/handoffs/impl.md")"
tool_allowed "an agent's Write to a file named hub.json elsewhere" "$(fileop Write "$proj/src/hub.json")"
for R in proj hub; do
  ROLE=$R
  tool_denied "a $R session's Write to a project's team.json" "$(fileop Write "$proj/$T_STATE/team.json")"
  tool_denied "a $R session's Edit of another project's team.json" "$(fileop Edit "$other/$T_STATE/team.json")"
  tool_denied "a $R session's Write through a link to team.json" "$(fileop Write "$T_TMP/lnk-teamjson")"
  denied "a $R session's redirect into team.json" "echo x > $proj/$T_STATE/team.json"
  denied "a $R session's sed -i on team.json" "sed -i s/a/b/ $proj/$T_STATE/team.json"
  tool_allowed "a $R session's Write to a team.json outside any $T_STATE" "$(fileop Write "$proj/src/team.json")"
done
ROLE=proj
hook "$(fileop Write "$HR/hub.json")"; assert_contains "the refusal for the hub's records says so" "$ERR" "hub's records"
hook "$(fileop Write "$proj/$T_STATE/team.json")"; assert_contains "the refusal for a team.json says so" "$ERR" "team.json"
hook "$(fileop Write "$CD/settings.json")"; assert_contains "the refusal for settings still says so" "$ERR" "settings"
r=$(printf '%s' "$(fileop Write "$HR/hub.json")" | HH_AWAY_BYPASS=1 HH_PROJECT="$T_TMP/no-such-project" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "a session whose project folder cannot be read is not the hub: hub.json is refused" $? 2
ROLE=hub
tool_allowed "the hub's Write to its own memory" "$(fileop Write "$HR/memory/n.md")"
tool_allowed "the hub's Write to its own records, as before" "$(fileop Write "$HR/decisions/x.md")"
tool_allowed "the hub's Write through a link into its own records folder" "$(fileop Write "$T_TMP/lnk-hubdir/memory/n.md")"
ROLE=proj

echo "-- MCP tools (A21, A47-A49)"
tool_denied "an MCP tool, no allowlist" "$(mcp mcp__github__create_issue)"
tool_denied "a claude.ai connector, no allowlist" "$(mcp mcp__claude_ai_Gmail__send)"
tool_denied "the built-in computer-use server" "$(mcp mcp__computer-use__screenshot)"
ALLOW="github"; tool_allowed "a tool of an allowed server" "$(mcp mcp__github__create_issue)"
tool_denied "a tool of another server" "$(mcp mcp__slack__post)"
tool_denied "a server whose name starts the same" "$(mcp mcp__github2__x)"
ALLOW="mcp__github__get_issue"; tool_allowed "an allowed single tool" "$(mcp mcp__github__get_issue)"
tool_denied "another tool of that server" "$(mcp mcp__github__create_issue)"
ALLOW="slack, mcp__github__get_issue ,"; tool_allowed "spaces and a trailing comma" "$(mcp mcp__slack__post)"
tool_allowed "the single tool in a list" "$(mcp mcp__github__get_issue)"
tool_denied "a malformed tool name" "$(mcp mcp__)"
ALLOW="plugin_vercel_vercel"; tool_allowed "a plugin server by its full name" "$(mcp mcp__plugin_vercel_vercel__list_projects)"
ALLOW=""
for t in Artifact ArtifactData ArtifactComments RemoteTrigger; do tool_denied "S6 $t, no allowlist" "$(mcp $t)"; done
ALLOW="Artifact"; tool_allowed "S6 Artifact allowlisted by its name" "$(mcp Artifact)"
tool_denied "S6 ArtifactData is not Artifact" "$(mcp ArtifactData)"
ALLOW=""
tool_denied "S6 Agent with remote isolation" '{"tool_name":"Agent","cwd":"/","tool_input":{"prompt":"x","isolation":"remote"}}'
tool_allowed "S6 Agent without isolation" '{"tool_name":"Agent","cwd":"/","tool_input":{"prompt":"x"}}'
tool_allowed "S6 Agent in a worktree" '{"tool_name":"Agent","cwd":"/","tool_input":{"prompt":"x","isolation":"worktree"}}'
tool_denied "S6 Agent with an unreadable input" '{"tool_name":"Agent","cwd":"/","tool_input":{"isolation":5}}'
unset HH_AWAY_MCP_ALLOW
ERR=$(printf '%s' "$(mcp mcp__x__y)" | HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" "$HOOK" 2>&1 >/dev/null); assert_status "an unset allowlist allows nothing" $? 2

echo "-- SendMessage (A50, A55, A60)"
ROLE=proj
tool_allowed "agent to its orchestrator by live name" "$(msg proj-orchestrator)"
tool_allowed "a [ref] suffix is removed" "$(msg 'proj-orchestrator [3fa9c1]')"
tool_allowed "to its hub" "$(msg hub1)"
tool_allowed "to a team agent <project>-<agent>" "$(msg proj-implementer)"
tool_allowed "a reply by uds address (orchestrator)" "$(msg "uds:/tmp/cc-socks/$OP.sock")"
tool_allowed "a reply by uds address (hub)" "$(msg "uds:/tmp/cc-socks/$HP.sock")"
tool_allowed "a reply by uds address (agent)" "$(msg "uds:/tmp/cc-socks/$IP.sock")"
tool_allowed "main" "$(msg main)"
tool_denied "a name shaped like a raw agent id (a peer's name)" "$(msg alpha-orchestrator)"
tool_denied "another aX-Y name" "$(msg abc-def)"
tool_denied "a raw in-process agent id" "$(msg a1b2c3d4e5f6a7b8c-9f)"
tool_denied "a session outside the team" "$(msg stranger)"
tool_denied "another project's orchestrator" "$(msg other-orchestrator)"
tool_denied "a recorded pid whose start time differs (pid reuse), by uds" "$(msg "uds:/tmp/cc-socks/$SGP.sock")"
tool_denied "a recorded pid whose start time differs (pid reuse), by name" "$(msg proj-reused)"
tool_denied "a raw-id-looking target with a scheme in it" "$(msg 'a1:bridge-x')"
tool_denied "a stranger by uds address" "$(msg "uds:/tmp/cc-socks/$SGP.sock")"
tool_denied "another project's orchestrator by uds" "$(msg "uds:/tmp/cc-socks/$XP.sock")"
tool_denied "a bridge address" "$(msg bridge:abc123)"
tool_denied "a remote scheme" "$(msg ssh:host/x)"
tool_denied "a uds address with no pid" "$(msg uds:/tmp/cc-socks/none.sock)"
tool_denied "a uds address of a dead pid" "$(msg uds:/tmp/cc-socks/99999999.sock)"
tool_denied "a target that cannot be resolved" "$(msg nobody-at-all)"
tool_denied "a broadcast" "$(msg '*')"
tool_denied "no target" '{"tool_name":"SendMessage","cwd":"/","tool_input":{"message":"x"}}'
tool_denied "a non-string target" '{"tool_name":"SendMessage","cwd":"/","tool_input":{"to":5,"message":"x"}}'
# an impostor carrying an agent's name, and a stale session with the same name
spawn proj-implementer; IMP=$SP
tool_denied "an impostor with an agent's name" "$(msg proj-implementer)"
kill "$IMP" 2>/dev/null; sleep 0.2
tool_allowed "the name is the agent's again once the impostor is gone" "$(msg proj-implementer)"
spawn hub1; HIMP=$SP
tool_denied "an impostor with the hub's name" "$(msg hub1)"
kill "$HIMP" 2>/dev/null; sleep 0.2
spawn a1b2c3d4-9f; RIP=$SP
tool_denied "a raw-id-looking name that a live session carries" "$(msg a1b2c3d4-9f)"
kill "$RIP" 2>/dev/null; sleep 0.2
jq -nc --argjson p 99999999 '{pid:$p,name:"proj-orchestrator"}' > "$CLAUDE_CONFIG_DIR/sessions/99999999.json"
sleep 60 & NP=$!; t_track "$NP"
jq -nc --argjson p "$NP" '{pid:$p,name:"proj-orchestrator"}' > "$CLAUDE_CONFIG_DIR/sessions/$NP.json"
tool_allowed "a live non-Claude process on a stale record with the name is not an impostor" "$(msg proj-orchestrator)"
kill "$NP" 2>/dev/null
tool_allowed "a dead session record with the same name is not an impostor" "$(msg proj-orchestrator)"
echo "-- the hub's messages"
ROLE=hub
tool_allowed "hub to a project's orchestrator" "$(msg proj-orchestrator)"
tool_allowed "hub to another listed project's orchestrator" "$(msg other-orchestrator)"
tool_allowed "hub to an orchestrator by uds" "$(msg "uds:/tmp/cc-socks/$OP.sock")"
# the root-owned jq may sit at a path the hook's fixed PATH does not hold (/usr/local/bin, /opt/homebrew/bin): the library functions the hook
# calls then use that jq, not a bare one. Here the fixed PATH holds every program of /bin and /usr/bin except jq, and jq is reached by path alone.
REALJQ=""; for c in /usr/bin/jq /usr/local/bin/jq /opt/homebrew/bin/jq; do hh_path_trusted "$c" file 0 loose && REALJQ=$c && break; done
if [ -n "$REALJQ" ]; then
  NP="$T_TMP/nojq-path"; mkdir -p "$NP"; for f in /bin/* /usr/bin/*; do [ -x "$f" ] && [ "${f##*/}" != jq ] && ln -sf "$f" "$NP/${f##*/}" 2>/dev/null; done
  NJ=$(t_jq_bin nojq "$REALJQ")
  [ "$(grep -c '^PATH=/usr/bin:/bin:/usr/sbin:/sbin   # first of all' "$NJ/hh-away-hook")" = 1 ] && ok "the hook's PATH line is found once" || bad "the hook's PATH line did not match once"
  sed -i '' "s|^PATH=/usr/bin:/bin:/usr/sbin:/sbin   # first of all|PATH='$NP'   # first of all|" "$NJ/hh-away-hook"
  [ -z "$(env -i PATH="$NP" /bin/sh -c 'command -v jq')" ] && ok "...and the fixed PATH of this fixture holds no jq" || bad "the fixture PATH holds a jq"
  SAVE_HOOK="$HOOK"; HOOK="$NJ/hh-away-hook"
  tool_allowed "hub to a project's orchestrator with the root-owned jq off the fixed PATH" "$(msg proj-orchestrator)"
  tool_allowed "hub to an orchestrator by uds, the same" "$(msg "uds:/tmp/cc-socks/$OP.sock")"
  ROLE=proj; tool_allowed "an agent to its own orchestrator, the same" "$(msg proj-orchestrator)"; ROLE=hub
  tool_denied "...and a stranger is still refused" "$(msg stranger)"
  HOOK="$SAVE_HOOK"
else echo "  SKIP no root-owned jq on this machine"; fi
tool_denied "hub to a project's agent" "$(msg proj-implementer)"
tool_denied "hub to a stranger" "$(msg stranger)"
tool_denied "hub to a bridge address" "$(msg bridge:x)"
r=$(printf '%s' "$(msg proj-orchestrator)" | HH_AWAY_BYPASS=1 HH_PROJECT="$hub" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "HH_PROJECT equal to the hub's folder is the hub" $? 0
r=$(printf '%s' "$(msg proj-implementer)" | HH_AWAY_BYPASS=1 HH_PROJECT="$hub" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "...and has no agents to message" $? 2
# a team registered in a worktree of a listed home: the hub can message its orchestrator, and only that
wtp="$T_TMP/proj-wt"; git -C "$proj" worktree add -q "$wtp" -b wtteam; wtp=$(cd "$wtp" && pwd -P); mkdir -p "$wtp/$T_STATE"
spawn wt-orchestrator; WP=$SP; WS=$SS
jq -nc --arg op "$WP" --arg os "$WS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"wt-orchestrator",pane_pid:"1",pane_started:"x"}]}' > "$wtp/$T_STATE/team.json"
tool_allowed "hub to the orchestrator of a team in a worktree of a listed home, by name" "$(msg wt-orchestrator)"
tool_allowed "...and by uds" "$(msg "uds:/tmp/cc-socks/$WP.sock")"
tool_denied "...a stranger is still refused" "$(msg stranger)"
spawn wt2-orchestrator; XWP=$SP; XWS=$SS
unl="$T_TMP/unlisted"; git -C "$other" worktree add -q "$unl" -b unl >/dev/null 2>&1; rm -rf "$unl/$T_STATE"; mkdir -p "$unl/$T_STATE"
jq -nc --arg op "$XWP" --arg os "$XWS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"wt2-orchestrator",pane_pid:"1",pane_started:"x"}]}' > "$unl/$T_STATE/team.json"
tool_allowed "a worktree of the other listed project counts the same" "$(msg wt2-orchestrator)"
unl2="$T_TMP/not-a-root"; mkdir -p "$unl2/$T_STATE"; spawn nr-orchestrator; NRP=$SP; NRS=$SS
jq -nc --arg op "$NRP" --arg os "$NRS" '{agents:[{name:"orchestrator",claude_pid:$op,claude_started:$os,name_full:"nr-orchestrator",pane_pid:"1",pane_started:"x"}]}' > "$unl2/$T_STATE/team.json"
tool_denied "a folder that is no worktree of a listed home is not a team root" "$(msg nr-orchestrator)"
ROLE=proj
tool_denied "an agent of the project does not reach the worktree team's orchestrator" "$(msg wt-orchestrator)"
ROLE=hub
echo "-- a project that is not readable"
r=$(printf '%s' "$(msg hub1)" | HH_AWAY_BYPASS=1 HH_PROJECT="$hub/" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "the hub's own folder written with a trailing slash is still the hub" $? 0
r=$(printf '%s' "$(msg main)" | HH_AWAY_BYPASS=1 HH_PROJECT="$T_TMP/gone" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "main still passes, the check is by target" $? 0
r=$(printf '%s' "$(msg proj-orchestrator)" | HH_AWAY_BYPASS=1 HH_PROJECT="$T_TMP/gone" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "an unreadable HH_PROJECT denies a named target" $? 2

echo "-- the env the Bash tool sees does not matter"
r=$(printf '%s' "$(tc 'git push')" | HH_AWAY_BYPASS=1 HH_PROJECT="$other" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" 2>&1 >/dev/null); assert_status "any project in the env: still refused" $? 2

echo "-- wiring and the rule (A51, A72)"
m=$(jq -r '.hooks.PreToolUse[]? | select(.hooks[]?.command | test("bin/hh-away-hook")) | .matcher' "$HH_REPO_ROOT/hooks/hooks.json")
for t in Bash 'mcp__.*' SendMessage Edit Write MultiEdit NotebookEdit Artifact ArtifactData ArtifactComments RemoteTrigger Agent; do case "|$m|" in *"|$t|"*) ok "hooks.json matcher has $t" ;; *) bad "hooks.json matcher lacks $t: [$m]" ;; esac; done
assert_eq "the hook command runs from the plugin's bin" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HH_REPO_ROOT/hooks/hooks.json")" '"${CLAUDE_PLUGIN_ROOT}/bin/hh-away-hook"'
[ -x "$HOOK" ] && ok "hh-away-hook is executable" || bad "hh-away-hook is not executable"
grep -q 'HH_AWAY_BYPASS=1.*a message from anyone other than the session' <(tr '\n' ' ' < "$HH_REPO_ROOT/rules/RULES.md" | sed 's/  */ /g') && ok "RULES.md has the A51 line" || bad "RULES.md lacks the A51 line"
echo "-- the unmarked path's time"
s=$(date +%s); i=0; while [ $i -lt 50 ]; do printf '%s' "$(tc ls)" | env -u HH_AWAY_BYPASS "$HOOK"; i=$((i+1)); done; e=$(date +%s)
echo "  (50 unmarked runs: $((e - s)) s)"
[ $((e - s)) -le 10 ] && ok "50 unmarked runs took at most 10 s" || bad "unmarked path too slow: $((e - s)) s for 50"
t_done
