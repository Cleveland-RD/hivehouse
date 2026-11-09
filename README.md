# hivehouse

A Claude Code plugin that runs a software task with a team of Claude sessions in tmux: an orchestrator, the agents the task needs, reviews and gates before anything lands, context rotation, unattended overnight runs, and cleanup afterwards. A hub session in your work folder hands each task to its project's orchestrator and carries your words both ways.

https://github.com/user-attachments/assets/4d7cd596-8090-4e91-b258-3f470838e277

Skills are instructions; every mechanical action is a tested bash executable in `bin/`.

Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you. See [Customise hivehouse](docs/customise.md#customise-hivehouse).

## Delegate mode

The default is relay mode: every start, wake and answer waits for you. Delegate mode is the mode the hub runs while you are away: it decides internal work inside your projects and keeps the teams running, and it keeps pushes, deploys and spending for you. It is on only while a file only you can write says so, for at most 7 days. Details, and what it guards and does not, are in [Delegate mode (away)](docs/away-mode.md#delegate-mode-away); what you can allow it to do is in [Customising what away mode allows](docs/away-mode.md#customising-what-away-mode-allows).

## What hivehouse runs and sends

hivehouse is bash scripts and a few hooks. One of them, `hooks/hub.tsx`, draws the hub's screen. Its `hub_auto_start` option is on by default: a plain `claude` started in the hub's folder then renames its session to hub and opens the hub, which takes one model turn. Apart from the push and the ssh below, it makes no network calls of its own, and it sends nothing to us. (The Claude sessions it starts talk to Anthropic like any Claude Code session.)

**The hooks.** `hooks/hooks.json` wires four command hooks, each a bash script in `bin/` that reads the event on its standard input. None of them makes a network call itself; the away hook decides which network reads and which ssh a session may make.

- **`hh-session-hook`, on SessionStart (startup, clear and resume).** In a session started in the hub's folder it prints one line that tells Claude it is the hub and should open the hub skill (or, if another hub session is already alive there, that this one is not the hub). In a pane hivehouse registered (an agent it started, or an orchestrator registered with `hh-spawn --self`) it records the session id and transcript path in that agent's `.hivehouse/team/<agent>/session.json`, so the Stop hook and the context reading know which session is whose, and it prints a low-disk warning if the free space is below `min_free_gb`. Anywhere else it does nothing and exits 0.
- **`hh-guard-env`, on SessionStart (every start, clear and resume).** Appends one line to Claude Code's `CLAUDE_ENV_FILE` that puts the plugin's `bin/guard` first in PATH, so `rm`, `find` and `rsync` called by name in a Bash command refuse to delete protected folders. It adds the line once, and touches nothing else. See [docs/rm-guard.md](docs/rm-guard.md).
- **`hh-stop-hook`, on Stop.** In a session hivehouse registered, inside tmux, it reads how full the context is (from the session's own transcript, through `bin/hh-context`). At or above the `rotate_at_percent` option it blocks the stop once for each crossing, with a reason that tells the agent to update its handoff file and rotate. When the window size is only guessed, it blocks once instead, to say so and how to set it. Anywhere else it does nothing.
- **`hh-away-hook`, on PreToolUse** for Bash, MCP tools, SendMessage, Edit, Write, MultiEdit, NotebookEdit, Artifact tools, RemoteTrigger, Agent, Workflow, WebFetch, DesignSync and PushNotification. It does nothing unless the session was launched by the hub in delegate mode with the away marker in its launch environment. With the marker, it denies pushes, publishing and uploads, MCP servers you did not allow, messages to sessions outside the team other than peers you listed with `--peers`, and changes to Claude Code's settings and hooks. It lets through network reads (`curl` and `wget` GET, read-only `gh`), read-only ssh to the hosts you listed with `--remote-allow`, messages to listed peers (sent by the hub or a project's orchestrator, each logged in `.hivehouse-hub/peers.jsonl`), and the extra tools you chose with `--tools` or `--chrome`. It reads the tool call, the session's launch environment, the root-owned delegate file, the hub's and teams' records, Claude Code's session records, the process table, and the text of any script a Bash command runs. It answers within 20 seconds and treats anything it cannot read as a denial.

Then everything else it does outside its own files:

- **It starts Claude sessions in tmux and types into their panes.** Only into panes it started or recorded as part of a team. It waits until the pane is idle and never types over a dialog. It types the first line of a started or woken session, `/clear` and the pickup line after a context rotation, and the keys for the option you chose in a Claude Code dialog (a digit, Escape, or arrows and Enter). It answers a dialog only after you chose, and never in delegate mode.
- **Git worktrees and cleanup.** A team agent can get its own git worktree and branch in your repository. Cleanup removes only what its manifest recorded: temporary folders, files it moves to `.hivehouse/trash`, and the processes and panes it started.
- **Bypass, only in delegate mode.** While you're away, only while a file that only you can write allows it (7 days at most), and only if hivehouse's `permission_mode_local` option is auto, the hub starts and wakes team sessions with `--permission-mode bypassPermissions`. A hook in those sessions refuses pushes, publishing, uploads and changes to Claude Code's settings and hooks, unless you started away with `--no-hook` (for a machine whose own guard does this), which turns that hook off for your away sessions. Chrome is off in them unless you start away with `--chrome` and the hub or a session that holds the grant passes it down. In the default relay mode, and on remote hosts, hivehouse starts nothing in bypass.
- **No MCP server config for those sessions.** They start with every MCP server Claude Code is configured with, and hivehouse copies no MCP config and writes no `away-mcp.json` (an earlier version did, and removes a stale one). While that hook is on, it refuses calls to servers you did not allow.
- **Pushes only on your word.** `hh-push` pushes one commit by its full hash to a remote you name, fast-forward only, never forced; it reads the remote first (`git ls-remote`, `git fetch`). Agents are not pre-approved to run it, the team's rules say only the orchestrator runs it and only when you say so, and it refuses in delegate mode.
- **ssh, scp and rsync to your own machines.** For an overnight run on a host you listed in the `remote_hosts` option, `hh-remote-sync` copies four things to it: the git branches you name (as a git bundle), the project files you list, your Claude memory files (every `*.md` in the memory folder), and one secret file you name (into the project's `.hivehouse/tmp`, mode 600). The listed files replace what is there. A memory file or the secret file that differs there is never overwritten. Its `start-agent` step starts a Claude session on the host. Every call asks for your permission, and it refuses in delegate mode.
- **What `hooks/hub.tsx` runs.** It is the hub's screen, a Claude Code module named under `modules` in `hooks/hooks.json`. It runs only in a session started in the hub's folder (the one holding `.hivehouse-hub/`), and always from that folder. It reads the hub's own file (`.hivehouse-hub/projects.json`), the output of `hh-hub`, and the paths of the files an edit would touch. The only programs it starts are `bin/hh-hub` with these subcommands: `status` and `tasks` every 20 seconds, while the screen is open, to draw the projects and what waits on you; `dialog` for a question waiting on a session's screen, to show it; `wake` and `continue` when you press Resume or Continue; `answer` when you press an option of a dialog; and `name` and `naming` to pick the hub's name. With `hub_auto_start` on, at the start of an interactive session that has had no turn yet, it types the slash commands `/rename` (to the free hub name) and then `/hivehouse:hub`, so that the hub names itself and opens; with the option off it types neither. It sends nothing off the machine: it makes no network call and starts no other program. Its `tool.call` hooks refuse Edit, Write and NotebookEdit on project files, and common git commands that change a repository, in the hub session. Its command hook (`command.run` for `/hub-screen`) only opens the hub screen.
- **Local files.** It reads Claude Code's own records: the session records (`~/.claude/sessions`), the session transcripts, `~/.claude.json` (folder trust, MCP servers) and `~/.claude/settings.json`. To find a status line command to run, it also reads the managed settings file (`/Library/Application Support/ClaudeCode/managed-settings.json` on macOS, `/etc/claude-code/managed-settings.json` elsewhere) and the project's `.claude/settings.json` and `.claude/settings.local.json`. It reads the root-owned file you write to switch delegate mode on. It reads the launch environment of other Claude processes, to check the away marker. It keeps its state as files in your project's `.hivehouse/`, the hub's `.hivehouse-hub/` and `~/.hivehouse`.
- **The programs it starts.** `tmux` (sessions, panes, and typing into them, as above), `claude` (the sessions it starts, `claude --version` and `claude plugin list --json` to read which plugins are installed, locally and on a remote host you listed), `git` (worktrees, status, and the push above), `jq` (reading and writing its own JSON files), `ssh`, `scp` and `rsync` (only to the `remote_hosts` you set, as above, and, in away sessions, read-only ssh to the `--remote-allow` hosts), and standard system tools such as `ps`, `df`, `du`, `perl`, `shasum`, `awk` and `sed`. `hh-statusline` is the status line of the agents it spawns: it runs your own status line command, if you have one, and keeps Claude Code's reading of the context window in the agent's folder. Nothing else is downloaded, installed or run from the network. What leaves the machine: the Claude sessions' own traffic to Anthropic, a push you ask for to the remote you name, the `remote_hosts` copy above, in away sessions what the away hook lets through (above), and, only when you ask for a second opinion, the diff the Codex CLI sends to OpenAI. Agents it starts are pre-approved for six of its own commands (`hh-slot status` and `release`, `hh-context`, `hh-gate-verify`, `hh-settings resolve`, `hh-disk`) and nothing else. A reviewer runs a second opinion (the Codex CLI, if you have it, or a Claude subagent) only when you ask for one.

## Requirements

- tmux ≥ 3.2 (`new-session` and `new-window` take `-e`; hh-spawn hands each pane its environment that way)
- git ≥ 2.31; ≥ 2.38 for `hh-gate-verify commits` to count a merge's own files exactly (`merge-tree --write-tree`;
  before it a merge is counted by `--cc`, which is near and not exact)
- bash (the macOS 3.2 is enough), jq, perl and shasum (both ship with macOS)
- ssh and rsync, for remote runs
- Claude Code ≥ 2.1.291 (the hub's screen is a function-hooks module, `hooks/hub.tsx`, named under `modules` in
  `hooks/hooks.json`; built and tested on 2.1.291)

The idle check reads the Claude Code terminal UI (the prompt box and the dialog wording), checked against 2.1.x. The text it
looks for is in one place, `HH_DIALOG_TEXT` and `hh_pane_idle_text` in `bin/hh-lib.sh`; update it there when a release
changes the screen.

`hh-*` executables are on the PATH only inside Claude sessions where the plugin is enabled. To run one by hand, call it
by its install path (`claude plugin list --json` shows it), for example `<installPath>/bin/hh-slot status`.

## Install

```
claude plugin marketplace add Cleveland-RD/hivehouse
claude plugin install hivehouse@hivehouse
```

## For an agent installing this

A person may hand you this repository's link and say "install this". Do these steps in order; each says how to check it.
Where a step says **ask**, ask the person and wait: never decide it for them.

1. **Check what it needs.** Run each and compare with Requirements above:
   `tmux -V`, `git --version`, `jq --version`, `perl -v`, `shasum --version`, `claude --version`.
   If one is missing or too old, tell the person which, and how they would add it (on macOS: `brew install tmux jq`).
   **Ask** before installing anything yourself.
2. **Install the plugin** with the two commands under Install. Check it is there and enabled:
   `claude plugin list --json | jq '.[] | select(.id == "hivehouse@hivehouse") | {version, enabled}'`.
   It must print the version in `.claude-plugin/plugin.json` and `"enabled": true`.
3. **Settings.** The plugin's settings are its `userConfig` in `.claude-plugin/plugin.json` (models, efforts, permission
   mode, rotation level, overnight ceiling, `hub_auto_start`); each has a default, so nothing must be
   set. **Ask** whether the person wants any changed; Claude Code's `/plugin` menu changes them. Claude Code may say
   "N userConfig options not yet set" after the install: that needs no action, the defaults are in use.
4. **The hub (optional).** **Ask** whether they want one, and which folder is their work folder: the one that holds
   their projects, never a project itself. On their yes, set it up there:
   `cd <folder> && <installPath>/bin/hh-hub init`, with the `installPath` that `claude plugin list --json` shows for
   `hivehouse@hivehouse` (it refuses inside a repository). Then tell them to run `<installPath>/bin/hh-hub start` in that folder: it opens the hub in a
   tmux session named `hub`, which opens the hub and offers to group their folders into projects. You cannot start that session for
   them: it is theirs.
5. **Tell the person what they got:** `/hivehouse:start <task>` runs a team on a task inside a project; `<installPath>/bin/hh-hub start`
   in the work folder opens the hub. Nothing runs until they ask.

Never: start agents or sessions the person did not ask for, start a session in `bypassPermissions` (hivehouse does it only while the owner is away, through the owner's delegate file), install the
optional i-have-adhd plugin unasked, or push anything.

## Skills

| Skill | Who runs it | What it does |
|---|---|---|
| `/hivehouse:hub` | owner | the hub: hand tasks to each project's orchestrator, wake them, report back (starts by itself in the hub's folder) |
| `/hivehouse:start` | owner | plan, approve and run a team on a task |
| `/hivehouse:overnight` | owner | queue and run unattended, here or on a remote host |
| `/hivehouse:gate` | orchestrator, builders | run the gate into a log and verify every step |
| `/hivehouse:bubble-review` | reviewer | review a diff by depth, nine bubble categories |
| `/hivehouse:handoff` | any agent | write the handoff and START HERE block |
| `/hivehouse:cleanup` | owner | remove what the manifest recorded |
| `/hivehouse:review-plan`, `/hivehouse:doc-updater` | any | moved-in skills |
| `/hivehouse:docs-health-check` | owner | documentation sweep of the current project, report mode by default (a workflow, not a skill) |

`docs-health-check` is a Claude Code workflow: `workflows/docs-health-check.workflow.js`, with no `SKILL.md`. Claude Code's plugin docs say a `workflows/` directory at the plugin root is loaded without a manifest entry and that a plugin workflow runs as `/<plugin>:<meta.name>`. **Unverified here:** it has not been run through a live Claude Code session, only through a stand-in for the workflow runtime (`tests/test_docs_health.sh`). The report is written to `.hivehouse/reports/` (git-ignored), so report mode leaves the working tree as it was; when `.hivehouse/` is tracked or cannot be written, it goes to `$TMPDIR` outside every repository and the returned path says so; `apply` mode edits the working tree and never commits.

## Docs

- [The hub](docs/hub.md): the work folder's session, projects, handing tasks over, overnight runs and dialogs.
- [Delegate mode (away)](docs/away-mode.md): what the hub does while you are away, what it guards and what you can allow.
- [Customise hivehouse](docs/customise.md): roles, rules, options, and the optional i-have-adhd plugin.
- [State and restarts](docs/state-and-restarts.md): where hivehouse keeps its files and what to do after a restart.
- [The delete guard](docs/rm-guard.md): the `rm`, `find` and `rsync` guards that refuse to delete a root folder, and what they do not stop.
- [Development](docs/development.md): running the tests and the evals.
- [Security](SECURITY.md): the supported version and how to report a vulnerability privately.
