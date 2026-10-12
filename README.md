# hivehouse

A Claude Code plugin that runs a software task with a team of Claude sessions in tmux: an orchestrator, the agents the task needs, reviews and gates before anything lands, context rotation, unattended overnight runs, and cleanup afterwards. A hub session in your work folder hands each task to its project's orchestrator and carries your words both ways.

https://github.com/user-attachments/assets/4d7cd596-8090-4e91-b258-3f470838e277

Skills are instructions; every mechanical action is a tested bash executable in `bin/`.

Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you. See [Customise hivehouse](docs/customise.md#customise-hivehouse).

## Delegate mode

The default is relay mode: every start, wake and answer waits for you. Delegate mode is the mode the hub runs while you are away: it decides internal work inside your projects and keeps the teams running, and it keeps pushes, deploys and spending for you. It is on only while a file only you can write says so, for at most 7 days. Details, and what it guards and does not, are in [Delegate mode (away)](docs/away-mode.md#delegate-mode-away); what you can allow it to do is in [Customising what away mode allows](docs/away-mode.md#customising-what-away-mode-allows).

## What hivehouse runs and sends

hivehouse is bash scripts and a few hooks. One of them, `hooks/hub.tsx`, draws the hub's screen. Its `hub_auto_start` option is on by default: a plain `claude` started in the hub's folder then renames its session to hub and opens the hub, which takes one model turn. Apart from the push and the ssh below, it makes no network calls of its own, and it sends nothing to us. (The Claude sessions it starts talk to Anthropic like any Claude Code session.) This is everything it does outside its own files:

- **It starts Claude sessions in tmux and types into their panes.** Only into panes it started or recorded as part of a team. It waits until the pane is idle and never types over a dialog. It types the first line of a started or woken session, `/clear` and the pickup line after a context rotation, and the keys for the option you chose in a Claude Code dialog (a digit, Escape, or arrows and Enter). It answers a dialog only after you chose, and never in delegate mode.
- **Git worktrees and cleanup.** A team agent can get its own git worktree and branch in your repository. Cleanup removes only what its manifest recorded: temporary folders, files it moves to `.hivehouse/trash`, and the processes and panes it started.
- **Bypass, only in delegate mode.** While you're away, only while a file that only you can write allows it (7 days at most), and only if hivehouse's `permission_mode_local` option is auto, the hub starts and wakes team sessions with `--permission-mode bypassPermissions`. A hook in those sessions refuses pushes, publishing, uploads and changes to Claude Code's settings and hooks. In the default relay mode, and on remote hosts, hivehouse starts nothing in bypass.
- **MCP server config for those sessions.** `hh-hub away` copies the config of the MCP servers you allowed (none by default) from `~/.claude.json` and the project's `.mcp.json` into `.hivehouse-hub/away-mcp.json`, and each session it starts gets a copy in its own folder. That config can hold the servers' secrets. The files are mode 0600.
- **A delete guard first in PATH.** A SessionStart hook adds one line to Claude Code's `CLAUDE_ENV_FILE` that puts the plugin's `bin/guard` first in PATH, so `rm`, `find` and `rsync` called by name in every Bash command refuse to delete protected folders. See [docs/rm-guard.md](docs/rm-guard.md).
- **Pushes only on your word.** `hh-push` pushes one commit by its full hash to a remote you name, fast-forward only, never forced; it reads the remote first (`git ls-remote`, `git fetch`). Agents are not pre-approved to run it, the team's rules say only the orchestrator runs it and only when you say so, and it refuses in delegate mode.
- **ssh, scp and rsync to your own machines.** For an overnight run on a host you listed in the `remote_hosts` option, `hh-remote-sync` copies four things to it: the git branches you name (as a git bundle), the project files you list, your Claude memory files (every `*.md` in the memory folder), and one secret file you name (into the project's `.hivehouse/tmp`, mode 600). The listed files replace what is there. A memory file or the secret file that differs there is never overwritten. Its `start-agent` step starts a Claude session on the host. Every call asks for your permission, and it refuses in delegate mode.
- **What `hooks/hub.tsx` runs.** Only in a session started in the hub's folder (the one holding `.hivehouse-hub/`), and always from that folder. It runs `bin/hh-hub` with `status` and `tasks` every 20 seconds, `dialog` for a question waiting on a screen, `wake` and `continue` when you press Resume or Continue, `answer` when you press an option of a dialog, and `name` and `naming` to pick the hub's name. With `hub_auto_start` on, at the start of a session that has had no turn yet, it types the slash commands `/rename` (to the free hub name) and then `/hivehouse:hub`. It reads the hub's own files (`.hivehouse-hub/projects.json`) and the paths of the files an edit would touch, and it sends nothing off the machine. Its `tool.call` hooks refuse Edit, Write and NotebookEdit on project files, and common git commands that change a repository, in the hub session. Its command hook (`command.run` for `/hub-screen`) only opens the hub screen.
- **Local files.** It reads Claude Code's own records: the session records (`~/.claude/sessions`), the session transcripts, `~/.claude.json` (folder trust, MCP servers) and `~/.claude/settings.json`. It reads the root-owned file you write to switch delegate mode on. It reads the launch environment of other Claude processes, to check the away marker. It keeps its state as files in your project's `.hivehouse/`, the hub's `.hivehouse-hub/` and `~/.hivehouse`.

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
   mode, files per commit, rotation level, overnight ceiling, `hub_auto_start`); each has a default, so nothing must be
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
