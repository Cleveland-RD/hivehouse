# hivehouse

A Claude Code plugin that runs a software feature or task with a team of Claude sessions in tmux: one orchestrator,
the agents the task needs, reviews and gates before anything lands, context rotation, unattended overnight runs on this
machine or a remote host, and cleanup afterwards. Above every project sits the owner's **hub**: one session in the
work folder that hands each task to that project's orchestrator and carries the owner's words both ways.

It carries working methods proven on one long project and nothing specific to that project: every project fact lives in
the project's own CLAUDE.md (or CLAUDE.local.md) and memory. Skills are instructions; every mechanical action is a
tested bash executable in `bin/`.

Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you. See [Customise hivehouse](#customise-hivehouse).

## Delegate mode

The default is relay mode: every start, wake and answer waits for you. Delegate mode is the mode the hub runs while you are away: it decides internal work inside your projects and keeps the teams running, and it keeps pushes, deploys and spending for you. It is on only while a file only you can write says so, for at most 7 days. Details, and what it guards and does not, are in [Delegate mode (away)](#delegate-mode-away); what you can allow it to do is in [Customising what away mode allows](#customising-what-away-mode-allows).

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
   set. **Ask** whether the person wants any changed; Claude Code's `/plugin` menu changes them.
4. **The hub (optional).** **Ask** whether they want one, and which folder is their work folder: the one that holds
   their projects, never a project itself. On their yes, set it up there:
   `cd <folder> && <installPath>/bin/hh-hub init`, with the `installPath` that `claude plugin list --json` shows for
   `hivehouse@hivehouse` (it refuses inside a repository). Then tell them to start `claude` in that folder: it names
   itself `hub`, opens the hub, and offers to group their folders into projects. You cannot start that session for
   them: it is theirs.
5. **Tell the person what they got:** `/hivehouse:start <task>` runs a team on a task inside a project; `claude` in the
   work folder is the hub. Nothing runs until they ask.

Never: start agents or sessions the person did not ask for, start a session in `bypassPermissions` (hivehouse does it only while the owner is away, through the owner's delegate file), install the
optional i-have-adhd plugin unasked, or push anything.

## Optional: i-have-adhd

[i-have-adhd](https://github.com/ayghri/i-have-adhd) shapes output for an ADHD reader. It is not a dependency: when it
is installed and enabled, the orchestrator reads its rules at the start and after every rotation and follows them in
every message to the owner; when it is not, nothing changes. hivehouse never installs, enables or switches it on.

```
claude plugin marketplace add ayghri/i-have-adhd
claude plugin install i-have-adhd@i-have-adhd
```

In any other session, `/i-have-adhd` turns it on. Its INSTALL.md also describes an always-on mode; with that on, the
plugin applies itself everywhere and hivehouse does not load it a second time.

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

## The hub

One Claude session in the owner's work folder, the folder above every project, is the owner's entry point:

- **Set up once.** Run `hh-hub init` in the work folder (it refuses inside a repository). An agent installing hivehouse
  does this for you; `/hivehouse:hub` in a session there offers it too, then asks you to start `claude` again, since a
  session started before the folder was the hub has no screen and no guard. From then on every session started in
  that folder, and only there, is the hub: a new, unnamed one names itself `hub` (`hub-2` beside another, since
  orchestrators reply to the hub by name) and opens the hub by itself, which takes one model turn. The `hub_auto_start`
  setting turns that off; then start it with `claude --name hub /hivehouse:hub`.
  The name belongs to the hub's folder: `hh-hub name <name>` keeps it in `.hivehouse-hub/name`, and the hub starts from it
  (`<name>-2` beside another). `ListAgents` shows sessions on other machines only while Remote Control is connected, and without it
  the check finds nothing; a hub that finds its name taken there says so once and never renames itself.
- **Projects span folders.** A project is its home, the repository its team works from, and any other folders it
  covers (`hh-hub add <project> --home <folder> --repo <folder>...`). The hub proposes the groups from `hh-hub discover`
  and adds only what the owner confirms. `hh-hub add <project> --repo <folder>...` adds folders to a project that exists,
  and `hh-hub drop <project> <folder>` takes one out (never the home); tasks and memory stay.
- **Teams in worktrees.** A project's team roots are its home, then each worktree of the home's repository that has a
  `.hivehouse/team.json`. `hh-hub status`, `wake`, `dialog`, `run` and `recover` look in every one (an orchestrator
  registered in two counts once; each agent is listed with its worktree), the away hook lets the marked hub message a
  worktree's orchestrator, and bypass is granted in a worktree team root exactly as in the home: the root and the home
  must both be the caller's, not links, and not writable by group or others. Every team root takes its settings from the
  home (a worktree's own `.hivehouse/settings.json` is not read). The worktrees are found without running git: from
  `<home>/.git/worktrees/<name>/gitdir` and the worktree's own `.git` file, which must point at each other (relative
  paths, as git 2.48 can write them, are resolved against the file they are in). git comes from `PATH`, which an away
  session's own Bash command sets, so it is never run on the grant path.
- **An orchestrator that ended unregistered** is found too. A live session named exactly like the project, running in its
  home, counts as its orchestrator. When nothing is recorded of its conversation, `hh-hub wake` looks in Claude Code's
  transcripts under the folder key of each team root (`<config dir>/projects/<key>/*.jsonl`, the 20 newest per root) for
  the newest one whose last `custom-title` is `<project>-orchestrator` and whose records' `cwd` is that root exactly (the
  key alone is not trusted: `/ . _ & space` all become `-`). It resumes that session by id, never by name, and
  `hh-hub status` shows it as `stopped, not registered (resumable)`. The transcript format is Claude Code's and
  undocumented: reading it is one function, `hh_resume_candidate` in `bin/hh-lib.sh`.
- **Handing work over.** The owner's words go to the ledger and a task file (`hh-hub task`), then to the project's
  orchestrator: a message when it runs; `hh-hub wake` when a restart stopped it, which resumes its own conversation (its
  own model) and tells it to register with the hub and bring its agents back; `hh-hub start` when there is none. An
  orchestrator already running outside hivehouse is found in Claude Code's own session records and never doubled. Each
  start asks the owner first, and runs in the owner's local permission mode (`permission_mode_local`, the one hivehouse's
  agents run in), made stricter where the project's own `.hivehouse/settings.json` says so. Start the hub in that mode
  too: sessions in different modes hold each other's messages for an approval nobody sees.
- **Through the hub.** The orchestrator registers with `hh-spawn --self --hub <hub>`, so every pickup line, after each
  rotation too, says the owner talks through the hub. It sends its questions, plan, blockers and results there; the hub
  shows them word for word and carries the answer back. The ledger records each task's state; a plan, a question and a
  blocker wait on the owner.
- **Nothing stuck, nothing unseen.** A start that stops at a question on its screen is kept: once the owner answers it,
  `hh-hub continue` (or the screen's Continue) sends the line, and never while the start's own line is still on its way.
  A dialog waiting on any orchestrator's or agent's screen is shown to the owner.
- **Claude Code's session records.** Naming itself and finding orchestrators outside hivehouse read
  `~/.claude/sessions/<pid>.json`, which Claude Code keeps and does not document. Without them the hub names nothing
  (the person types `/rename hub`) and finds only orchestrators hivehouse registered; nothing else changes.
- **The screen.** `/hub-screen` (or a wide terminal, at start) opens a pane: what waits on the owner, then each
  project's orchestrator, agents, tasks and folders, with Resume and Continue buttons, and a button for each option of a dialog waiting on a session (a click carries the dialog's `Seen` fingerprint, so an answer to a screen that has changed is refused). It reads `hh-hub` only while shown.
- **Hands off the code.** The hub never reviews, builds, tests, commits or pushes. In the hub's session the module
  refuses an edit inside the work folder (apart from `.hivehouse-hub/`) or inside a project's folder, and a git command
  that changes a repository; quoted text and heredocs are the owner's words, never a command (best effort for shell).

### Overnight and cleanup through the hub

`/hivehouse:overnight` and `/hivehouse:cleanup` can only be started by a person typing them. The hub types them for the owner: `hh-hub run <project> overnight <task id>` and `hh-hub run <project> cleanup <task id> [--disk]`. Only these two skills, only a line `hh-hub` builds, only into the project's running, registered orchestrator, and only after the owner's yes for that one run. It refuses a task that waits on the owner, a task already in an overnight run, and a second run while one is being typed. The task then shows as `overnight` or `cleanup`, open and not waiting on the owner.

### Dialogs through the hub

A permission prompt or another dialog on an orchestrator's or agent's screen is shown to the owner with its options (`hh-hub dialog <project> [<agent>]`). The owner can answer it from the hub: `hh-hub answer <project> [<agent>] --choice <1-9|esc> --seen <fingerprint>`, which presses the one key (or, for a menu with no numbers, moves the cursor and presses Enter as the last key of that choice) after checking that the dialog is still the one the owner saw. The hub never offers the options that need the owner's own words, "Type something" and "Chat about this": those are answered in the pane. An option that saves a permission rule ("always allow…") is marked as such when it is shown. Every answer is logged to `.hivehouse-hub/answers.jsonl`, not to the task ledger, because a dialog belongs to no task. Limits: two identical dialogs in a row share a fingerprint, and the screen's one-press-at-a-time lock is what stops a repeat; multi-select and multi-question dialogs are untested.

### Delegate mode (away)

Relay mode, where every start, wake and answer waits for the owner, is the default and is unchanged. Before leaving, the owner can switch delegate mode on. The hub then decides internal work itself, keeps the teams running, and keeps for the owner only what must be theirs.

**Switching it on and off.** `hh-hub away --until <time> [--mcp-allow <list>] [--remote-allow <hosts>] [--allow <words>]` prints lines for the owner to paste; `hh-hub back` prints the line that ends it. hivehouse never runs `sudo` and never asks for a password: the lines create one file as root, so a changed script cannot capture the password and the owner sees exactly what runs as root.

- **The file.** One file for each user: `/Library/Application Support/hivehouse/delegate.d/<uid>` on macOS, `/etc/hivehouse/delegate.d/<uid>` on Linux, where `<uid>` is the user's real user id as `/usr/bin/id -u` prints it (never `$UID`, `$USER`, an argument or a setting). Several people can share a machine, each with their own hub, and each can be away on their own: one user's file says nothing about another's. Line 1 is `hivehouse-delegate 2`, then `hub=<the hub's folder>`, `until=<epoch seconds>`, `mcp=<list>` (the MCP servers the owner allowed: letters, digits and `_ , . : -`), `hosts=<list>` (the ssh hosts the away sessions may read from) and `allow=<list>` (the command words `scp`, `rsync` or `sftp` the owner exempted); `hosts=` and `allow=` may be empty. The `sudo` lines that `hh-hub away` prints with `--mcp-allow`, `--remote-allow` and `--allow` write them. A file written by 0.5.0 (`hivehouse-delegate 1`, exactly the first four lines) is still read, with no hosts and no allowed words. The hub's allowed servers come from this file, never from `away.json` or the environment. Delegate mode is on exactly while this file is valid. Valid means: the file, its folder and every folder above it are not links and not writable by group or others; the file and its folder are owned by root; the content is exactly the lines of its version (four for version 1, six for version 2) and every value is one this release accepts (an unknown or forbidden `allow=` word, or a bad host name, makes the file invalid and away mode stays off); and `until` is in the future. No environment variable or setting changes the path, the owner or the content, and every executable that asks starts with `#!/bin/bash -p` and calls outside commands by absolute path, so a fake `date`, a function or a `BASH_ENV` cannot revive an expired file.
- **The file must belong to the user who reads it.** The hub it names, its `.hivehouse-hub/`, `projects.json` (which homes get bypass) and `hub.json` (which Claude is the hub) must be owned by that user, not links, and not writable by group or others. So must each project's home that is granted bypass: a session working in a folder another user controls would load that user's `CLAUDE.md`, hooks and `.mcp.json`. The files inside a home are not checked one by one, and neither are `tasks.jsonl`, `holds/`, `decisions/` and `away.json` in the hub's folder; `hh-hub` runs with `umask 022` and takes group and others' write off `.hivehouse-hub/` (at `init`, `add`, `remove`, `self` and `away`), which puts those right. A hub or a project home cloned or made under `umask 002` (775) is refused while away until its owner runs `chmod go-w` on it; `hh-hub away` checks all of it first, prints no `sudo` line for an away that would be refused, and prints the reason and the `chmod go-w` line instead. `hh-hub status` shows `away_refused` and its reason when a file exists at the user's path but is refused.
- **Away mode needs a root-owned `jq`.** The away hook and every check that grants away powers read their JSON with the first of `/usr/bin/jq`, `/usr/local/bin/jq` and `/opt/homebrew/bin/jq` whose file and every folder above it are root's, not links and not writable by group or others (`hh_jq_fixed` in `bin/hh-lib.sh`; the hook also fixes its own `PATH` to `/usr/bin:/bin:/usr/sbin:/sbin` first of all). A Homebrew `jq` belongs to the user, so it never passes: the user's own account is exactly the away session being guarded, and a `jq` it could replace could name any hub or project. macOS 15 and later have `/usr/bin/jq`; elsewhere, install one root-owned. With none, the hook denies every call and bypass is refused (fail closed); scripts that decide nothing work as before.
- **Who can read it.** The file is mode 0644, so other users on the machine can read whether you are away and where your hub is. On macOS every user shares the group `staff`, so a group-only mode would protect nothing.
- **At most 7 days.** `until` may be at most 7 days ahead. The hub's heartbeat is a `CronCreate` job: it lives only as long as the hub's session, fires only while the hub is idle, and a recurring one expires after 7 days. After a reboot nothing runs until the owner starts the hub again.
- **Before leaving, two things only the owner can do**: Claude Code shows a one-time warning the first time it runs in bypass mode (`Yes, I accept`; it then writes `skipDangerousModePermissionPrompt` to the user's settings), and a folder-trust dialog for every folder it has not trusted. `hh-hub away` checks both, for the hub's folder and for every folder of every project it lists, and prints what is missing. Claude Code decides trust per folder: a git repository does not inherit it from the folder above, and a worktree is judged by its main repository's entry, so one line covers a repository and its worktrees. `hh-spawn` warns when a worktree it is about to use would stop at that dialog. Nobody can answer these dialogs while the owner is away.
- **The hub starts marked.** The start line `hh-hub away` prints runs the hub in bypass with `HH_AWAY_BYPASS=1`, `HH_PROJECT`, `HH_AWAY_HUB` and `HH_AWAY_MCP_ALLOW` in its launch environment, and with only the MCP servers named in the file's `mcp=` line. The owner exits the running hub first, so two do not share the folder. The hub acts in delegate mode only when `printenv HH_AWAY_BYPASS` prints `1`.
- **Bypass is granted only under three conditions together**: the owner's delegate file is valid and lists the project's home, the caller's own Claude carries the away marker, and the owner's `permission_mode_local` is `auto` (a stricter value, or a project's own tighter setting, keeps a session out of bypass). Bypass is never a value the owner or a project can name. An orchestrator the hub starts or wakes and an agent `hh-spawn` starts get it on those terms. `hh-remote-sync start-agent` never starts bypass; a dedicated host is where the owner may start a bypass session by hand.
- **When it ends** (`hh-hub back`, or the file expires), the hub tells the owner to restart it out of bypass, and until they have, it asks before every start, wake, run or answer, as in relay mode.

**What the hub decides, and what it keeps for the owner.** It decides plans and questions about work inside the project's own repositories and branches, its tests, its agents and their number, worktrees, overnight runs of tasks the owner gave, and wake, start, continue and run for those tasks. It keeps for the owner: a push, a merge, a deploy or migration, anything that sends or publishes outside the machine, a paid step, deleting data that is not the team's own scratch, a change to settings or permissions, a new task, and every screen dialog. A kept item is logged as a question, its task waits, and other tasks go on. `hh-hub hold <project>` keeps the hub away from a project altogether.

While the owner is away the hub never answers a screen dialog (`hh-hub answer` refuses; `hh-hub dialog` still reads it). Its answers go out as `HUB on TASK <id>: <decision>`, never `OWNER on TASK`, so an orchestrator always knows whose words it has. Each decision is recorded, with the question and the answer word for word, in `.hivehouse-hub/decisions/<task id>.md` and a `decided` event (`hh-hub decide`). When the owner is back, the hub opens with what it decided since they left, and the screen keeps "decided while you were away" until the owner presses Seen (`hh-hub status --json` shows `hub.last_away` after away ends).

**Keeping the teams running.** On each beat the hub runs `hh-hub recover --json --max-starts <hub_max_starts_per_day>` and carries out what it prints: wake a stopped orchestrator, or one that ended unregistered but left a transcript (resumable), that has an open task, send an orchestrator `RESPAWN:` for agents that stopped, restart a hung session (below), and list a dialog for the owner. The same action on the same item is tried at most 3 times in 24 hours, then the task is blocked for the owner; and at most `hub_max_starts_per_day` sessions are started or woken in 24 hours, each wake counted as it is decided, so two stopped orchestrators and room for one wake one. That daily cap is a guideline the hub passes, not a guard: the hub runs in bypass and could ignore it. Spend is not tracked here: overnight runs stop at their own ceiling.
**Hung sessions.** A hung session is restarted, never typed into. It counts as hung only on positive evidence: Claude Code's working line (`✳ Effecting… (3s · thinking)`) is recognised, and its elapsed time is the same on every beat for 15 minutes, for the same process. A screen hivehouse does not recognise is "unknown" and is never restarted; a session that is slow but still counting is not hung. The hub then stops that Claude process by its recorded process id and start time, never by name or pattern: it checks again that the process is the recorded one, is Claude, is not the hub's own, runs under the pane whose screen it read, and that the screen still shows the same line; it sends TERM, waits up to 10 seconds, and sends KILL only if it is still the same process. This is the one place hivehouse stops a process it did not start; `rules/RULES.md` names it, and it applies to the hub's recover only, in delegate mode, not to agents. The session is then resumed in its own conversation: an orchestrator by `hh-hub wake`, an agent by `hh-spawn --respawn <agent> --resume`, typed one short line ("You were restarted by hivehouse after your session stopped responding…") instead of the full pickup line. A session is restarted at most 3 times in 24 hours, then its task is blocked for the owner; a hung orchestrator is stopped only while the daily cap leaves room to wake it; a stop that does not take is reported once and not tried again for 24 hours.

**One limit.** A team counts only when it sits in the project's home or in a worktree of the home's own repository that has a `.hivehouse/team.json`. A team in a separate clone of the repository is not seen.

### What away mode guards, and what it does not

**Away mode is not a sandbox.** In bypass, any session can run any command as the owner's user, with the owner's files and credentials. The refusals below stop the actions delegate keeps for the owner; they are not a security boundary, and switching away on means trusting the teams the hub runs.

**Who is guarded: the marker.** A session hivehouse launches in bypass while away carries `HH_AWAY_BYPASS=1` in its launch environment. Every guard keys on it. On macOS, `ps -E` shows no environment for Apple's own programs (bash, sleep) and shows it for others, such as Claude: the marker is read from the Claude process, and a session whose environment cannot be read is refused, never trusted. `ps -E` joins the variables with spaces, so on macOS a marker spelled inside another variable's value (`FOO="x HH_AWAY_BYPASS=1 y"`) counts as set; Linux reads `/proc/<pid>/environ` exactly. A Bash command can unset it for itself, so the hook, not the scripts, is the guard. When a session carries no marker (the owner's own bypass sessions, `dedicated_hosts` runs) nothing here applies. If delegate mode ever has to run in `auto` instead of bypass, there is no marker and no refusals: outward steps are left to the auto classifier and to prompts nobody answers, as in overnight today.

**The hook.** `bin/hh-away-hook` is a `PreToolUse` command hook, wired in `hooks/hooks.json` for Bash, MCP tools, SendMessage, Edit, Write, MultiEdit, NotebookEdit, Artifact, ArtifactData, ArtifactComments, RemoteTrigger and Agent. Without the marker it exits at once. With it, it refuses (exit 2, with a reason the session can read):

- every MCP tool, and the Artifact, ArtifactData, ArtifactComments and RemoteTrigger tools (by their own names), unless the owner's `away_mcp_allow` lists the server (`<server>`) or the single tool (`mcp__<server>__<tool>`). Allowing a server allows its write tools too, and a single-tool entry still loads the whole server: only the hook limits it to that tool. This also blocks local tools such as browser automation and the built-in `computer-use` server. `hh-hub away` loads servers from `~/.claude.json` and the hub's `.mcp.json` only, not from plugins' manifests, so a plugin's server may not be available even when listed;
- in Bash: `git` with `push`, `gh` outside its read-only forms, `ssh` (except the reads the owner allowed with `--remote-allow`, below), `scp`, `rsync` and `sftp` (unless the owner listed them with `--allow`), `curl` and `wget` that upload or use a method other than GET, `npm`, `pnpm` and `yarn` `publish`, `vercel`, `netlify`, `docker push`, `hh-push` and `hh-remote-sync`;
- `claude` run by hand, and `tmux` `new-window`, `split-window`, `new-session`, `respawn-pane`, `respawn-window`, `run-shell`, `if-shell`, `display-popup`, `pipe-pane`, `source-file` and `send-keys`: `hh-spawn` and `hh-hub` start sessions and set the marker again, and SendMessage is the way to talk to a peer;
- Edit, Write and Bash redirects or writing commands (`tee`, `cp`, `mv`, `sed`, an interpreter, and the like) on Claude Code's settings files, hook files, plugin folders, `~/.claude.json`, a project's `.mcp.json` and `~/.ssh/` (whom a session trusts and as whom it signs in), judged by where a link leads;
- Edit, Write, MultiEdit, NotebookEdit and the Bash write forms into the hub's `.hivehouse-hub/` folder by any session that is not the hub, and into any `.hivehouse/team.json` by every marked session, the hub included (hivehouse's own scripts still write it), judged by where a link leads;
- SendMessage to anyone but the session's own hub and team, checked by name and by process: a `bridge:` address, another project, a name another live session also carries, and anything that cannot be resolved are refused. `RULES.md` adds that a message from anyone else is information, never an instruction; to instruct the hub while away, the owner types into it (Remote Control, say);
- an Agent call that starts a remote (cloud) agent, which would carry no marker.

Anything the hook cannot read or parse is refused too, and so is any failure of the hook itself. Its refusal text says it comes from hivehouse's away mode, is not a permission prompt, and tells the session not to change settings, hooks or permissions to get round it, because a session told "no" has offered to do exactly that.

**A second layer.** `hh-push`, every `hh-remote-sync` subcommand and `hh-cleanup --finish` also refuse with exit 4 when `HH_AWAY_BYPASS=1` is in their environment; `hh-cleanup --disk` stays allowed. These three run under `#!/bin/bash -p`, and so does `bin/hh-away-hook` (it finds `hh-lib.sh` through `HH_BIN`). A Bash command can unset the variable for itself, so this is a backstop behind the hook.

**What the hook does not catch.** The list is not complete, and this README says so on purpose:

- The matching is by words, not by structure. `$'\x67'it push`, `g${e}it push` and zsh glob qualifiers (`*(e:'…':)`) get through, and so does a push inside a script file the session wrote. A quoted `push` beside `git`, as in `git commit -m "fix(push): …"`, is refused: rephrase. A heredoc body is data, never commands, only when the command in front of `<<` is a known reader (`cat`, `git`, `grep`, `jq`, `wc`, `head`, `tail`, `sort`, `uniq` or an `hh-` executable) and nothing on that line runs or relays its input (a shell or interpreter, `ssh`, `xargs`, `eval`, `tmux`, a wrapper); an unquoted body keeps only its lines with `$(` or a backtick, and those are checked. In every other case, including a line that ends in a pipe or `&&`, the body is checked as commands.
- A marked session can still reach the network or start an unmarked Claude in ways the hook does not see: `osascript` running `claude`, a script it wrote, or a tool that is not on the hook's matcher. `WebFetch` and `WebSearch` stay allowed, like `curl` GET, but they are reads that can carry data out in the address or the query.
- The list of protected files is not complete.
- The hook guards sessions of this plugin. It assumes the owner's `disableAllHooks` is not set.
- Nothing runs while the machine is off. Remote hosts are reached while away only by the reads the owner allowed with `--remote-allow` (`hh-remote-sync` is refused).

### Customising what away mode allows

Away mode allows nothing beyond its fixed rules, and only the owner widens them, in the root-owned delegate file. `hh-hub away` writes it from the options below, as lines for you to paste; hivehouse never runs `sudo`, and no agent, hook, setting or option can add to the file or loosen away mode any other way. An agent that is asked to allow something prints the lines for you to paste, and never edits anything to get round the refusal.

- `--remote-allow <hosts>` (comma-separated real ssh host names, letters, digits, `.`, `_` and `-`, not starting with `-`, or `user@host`) lets the away sessions read from those hosts, and only read. ssh passes as one command of plain words, `ssh -F none [-T] [-o ConnectTimeout=<digits>] [-o BatchMode=yes] <host> <command>`, with the host exactly as listed and `-F none` always there: ssh would otherwise read `~/.ssh/config` and the files it includes, which a session could write to point a listed name somewhere else, so with `-F none` no config is read and names from your `~/.ssh/config` are not usable while away (list the real host name). Any other ssh option, a host that is not listed, a command with no remote command, a variable or substitution for the host, and any quote, backslash, `;`, `&`, `|`, `(`, `)`, `` ` ``, `$`, `<`, `>`, newline, glob character or `~` in the remote part refuse the whole command.
- What the remote command may be: its first word must be one of a read-only list (no `env`, `nohup`, `name=value` prefix or other wrapper in front): `tmux` with `list-panes`, `list-sessions`, `list-windows`, `capture-pane -p` or `display-message -p`; `ls`, `cat`, `head`, `tail` (not following), `grep`, `sed -n` with a `<digits>[,<digits>]p` script only, `wc`, `df`, `ps`; `git log`, `show` and `rev-parse` (`log` and `show` must carry `--no-ext-diff --no-textconv --no-show-signature`, which stop a program named in the remote repository's config from running; `git status` and `git diff` are not allowed, because they can run one too); `hh-context`, `hh-slot status` and `hh-hub tasks`. `hh-hub status` is not on the list: it runs `git status`. Nothing that writes, starts a session or runs another program is on the list, and `--allow` never applies to it. `~/.ssh/` is protected in away sessions, so a session cannot change `known_hosts` or the keys.
- `--allow <words>` exempts `scp`, `rsync` or `sftp` from the refusal of their command word on the local machine, and nothing else: an allowed word lets only that command past its command-position refusal, every other rule still runs on the command, and it never applies to the remote part of an ssh command. No other word can be listed: not `ssh` (that is `--remote-allow`'s job), not `hh-push`, `hh-remote-sync`, `vercel` or `netlify` (a standing grant of up to 7 days would break "a word given for one run does not carry to the next"), and never `claude` or anything that starts a session or a tmux server. `hh-hub away` refuses to print (exit 4, naming the word or host) a forbidden word or a bad host name, and a file that holds one is invalid, so away mode stays off. `hh-hub status --json` shows the hosts and words in force.
- What can never be lifted, by any option: starting sessions by hand (`claude`, `tmux new-session` and the like), which would carry no marker and escape every guard; writing Claude Code's settings, hooks and plugin files and `~/.ssh/`; `git push` and the other publishing commands.
- Messages to sessions on other machines stay cut off while away: a Remote Control row does not say which host it is on. The ssh reads above cover status checks. In this release SendMessage to sessions on other machines stays cut off while away.
- Roles, rules and the brief template are yours to change in `custom/` (see [Customise hivehouse](#customise-hivehouse)), and nothing in `custom/` can loosen away mode. Note that an away agent can rewrite its own team's, and another project's, future roles and rules in custom/: no grant is loosened (away grants come only from the root-owned delegate file), but you should know.

**Which records are trusted, and why.** Only the root-owned delegate file gates bypass and delegate mode. Everything else is writable by the owner's user, so by any of their sessions in bypass, and is trusted only that far: `away.json`, the hub's `tasks.jsonl`, `recovery.jsonl` and `decisions/`, a project's `.hivehouse/settings.json` and `team.json`, and Claude Code's own settings. `hub.json` (which Claude is the hub) and `projects.json` (which folders a project covers, and so which get bypass) are writable by the owner's user, but a marked agent cannot write them through its tools: the hook refuses any write into `.hivehouse-hub/` by a session that is not the hub, and any write to a `team.json` by every marked session, the hub included. Both halves have limits: the hub's own session can still write its folder, and a write the hook's word matching does not recognise gets through, so this is not a security boundary.

## Customise hivehouse

The principle, stated once: setup-specific behaviour is configuration, never a code change. Anything specific to one machine, project or person is met by an option, a file in `custom/` or an allowance in the delegate file, not by editing the plugin. Anything that loosens away mode is root-owned: it lives in the delegate file only you can write.

Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you. This part is what Claude reads when you ask.

**Where each change goes**

- **A role, the rules or the brief template: `custom/`.** The plugin cache holds the installed plugin as a copy that is replaced by the next plugin update, so an edit inside it is lost; Claude never edits it (and an away session is refused if it tries). A file under `<project>/.hivehouse/custom/` (this project) or `${HIVEHOUSE_HOME:-~/.hivehouse}/custom/` (you, every project) takes the place of the plugin's file of the same path, the project's before yours before the plugin's:
  - `custom/roles/<role>.md` replaces `roles/<role>.md` (`implementer`, `fixer`, `reviewer`, `architect`, `product`), and `custom/roles/<new name>.md` adds a role of your own;
  - `custom/rules/RULES.md` replaces `rules/RULES.md`, which every skill and every agent reads first;
  - `custom/rules/brief-template.md` replaces `rules/brief-template.md`.
  - One resolver decides this for every skill: `hh-resolve role <name>`, `hh-resolve rules` and `hh-resolve brief` print the file to read, and a note on stderr says when a custom file is used or ignored. A custom file that is a link, that you do not own or that group or others can write is ignored with that note. `custom/` sits inside `.hivehouse/`, which git never tracks, so the project's files stay on this machine. A role file is copied into the team's folder when an agent is spawned, so a change reaches agents spawned afterwards. The hub has no project of its own, so for the hub only your own `custom/` and the plugin's apply.
- **A skill's behaviour.** A skill's own text is the plugin's, and an update replaces it. Everything a skill does is bound by the rules it reads first, so a change in how skills behave goes into `custom/rules/RULES.md` (or a role); a fact about one project goes in that project's `CLAUDE.md`.
- **Roles and rules for a team you spawn by hand.** `hh-spawn --role <file> --rules <file>` takes any two files: point them at your own copies.
- **Options.** The plugin options below, set in Claude Code's plugin settings.
- **Project safety settings.** `<project>/.hivehouse/settings.json` may tighten `permission_mode`, `overnight_ceiling_usd`, `allow_attribution` and `files_per_commit`, never loosen them.
- **What away mode allows.** `hh-hub away --until <time> [--mcp-allow <list>] [--remote-allow <hosts>] [--allow <words>]` prints the lines that write the delegate file (see [Customising what away mode allows](#customising-what-away-mode-allows)). When you ask Claude to loosen away mode, it prints those lines for you to paste and never edit anything to get round it.

**Every plugin option** (`.claude-plugin/plugin.json`, `userConfig`)

| Option | What it does | Default |
|---|---|---|
| `commit_style` | Commit subject style: conventional (type(scope): summary) or free | `conventional` |
| `allow_attribution` | Allow AI attribution trailers in commits: When off, gates refuse commits carrying Co-Authored-By or similar trailers | `false` |
| `files_per_commit` | Most files per commit: Gates warn or refuse commits touching more files than this | `5` |
| `model_orchestrator` | Orchestrator model: Model alias for the orchestrator session | `opus` |
| `model_builder` | Implementer/fixer model: Model alias for builder agents | `sonnet` |
| `model_reviewer` | Reviewer/architect/product model: Model alias for reviewing agents | `opus` |
| `effort_builder` | Builder effort: Reasoning effort for builder agents | `medium` |
| `effort_reviewer` | Reviewer effort: Reasoning effort for reviewing agents | `high` |
| `window_orchestrator` | Orchestrator context window (tokens): Used only when Claude Code's own reading of the window is missing (always for the orchestrator); never inferred from a model name | `200000` |
| `window_builder` | Builder context window (tokens): Used only when Claude Code's own reading of the window is missing; never inferred from a model name | `200000` |
| `window_reviewer` | Reviewer context window (tokens): Used only when Claude Code's own reading of the window is missing; never inferred from a model name | `200000` |
| `permission_mode_local` | Agents' permission mode on this machine: Bypass permissions is never used locally, except while the hub is in delegate mode (the owner is away): that needs this set to auto | `auto` |
| `remote_hosts` | Known remote hosts (comma-separated ssh names): ssh host names hivehouse may run overnight work on | `empty` |
| `dedicated_hosts` | Remote hosts dedicated to agents (bypass allowed): Comma-separated ssh names where bypass permissions may be used, asked again each time | `empty` |
| `rotate_at_percent` | Context level that triggers a handoff: Percent of the context window at which an agent hands off and is cleared | `50` |
| `overnight_ceiling_usd` | Spending ceiling per overnight run (USD): A project may only lower this | `50` |
| `heartbeat_minutes` | Overnight heartbeat interval (minutes): How often the orchestrator checks context, disk, queue and spend | `30` |
| `hub_auto_start` | Hub names itself and greets: A plain claude started in the hub's folder names itself hub (or hub-2...) and opens the hub, which takes one model turn; when off, start it with claude --name hub /hivehouse:hub | `true` |
| `hub_max_starts_per_day` | Hub: sessions started or woken per day while away: Delegate mode: the most sessions the hub starts or wakes in 24 hours before it keeps the rest for you. A guideline the hub passes to hh-hub recover, not a guard | `10` |
| `away_mcp_allow` | Away: MCP servers an away hub may use: Comma-separated MCP server names, or mcp__<server>__<tool>, loaded for the hub started by hh-hub away (none by default). Allowing a server allows its write tools too | `empty` |
| `min_free_gb` | Free disk (GB) below which cleanup runs: Below this, sessions get a low-disk warning and cleanup runs | `20` |

## State

- `<project>/.hivehouse/` — handoffs, team, manifest, settings, trash; excluded through the repo's `info/exclude`, never tracked.
- `${HIVEHOUSE_HOME:-~/.hivehouse}` — per user: the registry of running teams, and the heavy-job slot unless the machine has one (below).
- `<project>/.hivehouse/custom/` and `${HIVEHOUSE_HOME:-~/.hivehouse}/custom/` — your own roles, rules and brief template, which an update of the plugin never replaces ([Customise hivehouse](#customise-hivehouse)).
- The machine's heavy-job slot — one for every user, so two people's jobs queue instead of starving each other. An
  administrator makes it once, from lines `hh-slot setup` prints (`hh-slot setup <group>` on Linux): `slot/` and
  `slot/queue/` under `/Library/Application Support/hivehouse` on macOS or `/var/lib/hivehouse` on Linux, owned by root,
  mode exactly 2775, under folders only root can write. hivehouse never runs sudo. Until that folder passes every check,
  each user has a slot of their own, and `hh-slot status` says why. `hh-slot run --wait [<seconds>] <label> -- <command>`
  and `hh-slot acquire <label> --pid <pid> --wait [<seconds>]` queue in the order they asked; without `--wait` the
  answer is 75 at once, also while others wait. `HH_SLOT_LOCAL=1` opts out of the machine slot for one process and
  can never name another folder. The slot is coordination, not a security boundary: a user can file fake tickets and
  delay the others.
- `<work folder>/.hivehouse-hub/` — the hub's projects, task ledger and task files, its notes per project; outside every
  repository. Delegate mode adds `hub.json` (which Claude is the hub), `away.json`, `decisions/<task id>.md`,
  `answers.jsonl` (dialogs answered through the hub), `recovery.jsonl` and `recovery-state.json`, `hung-state.json` and
  `holds/<project>`.
- `/Library/Application Support/hivehouse/delegate.d/<uid>` (macOS) or `/etc/hivehouse/delegate.d/<uid>` (Linux) — the
  user's own root-owned delegate file, one for each user and the only record that gates bypass; hivehouse never writes it.
- Files that may hold MCP server secrets, each mode 0600 and removed or replaced by the next start:
  `.hivehouse/team/<agent>/away-mcp.json` (an agent started in bypass), `.hivehouse-hub/away-mcp.json` (the hub's) and
  `.hivehouse-hub/panes/<project>-mcp.json` (an orchestrator the hub started, until it registers).

## After a restart

A restart of the machine or of tmux takes the team's panes with it. `hh-context --all` then marks each session
"(not running)", keeping its last level. The orchestrator registers itself again with `hh-spawn --self --agent
orchestrator`, then runs `hh-spawn --respawn <agent>` for each agent so marked: the agent starts again from its own
record (model, effort, permission mode, worktree and branch from `team.json`, role and rules from
`.hivehouse/team/<agent>/`) and is sent back to its handoff. A running agent, one whose state cannot be told, and the
orchestrator itself are never respawned. An agent recorded in bypass is refused (exit 4) once away has ended: add
`--mode <a stricter mode>` (the owner's `permission_mode_local`). `--resume` brings the agent back in its own recorded
conversation instead of from its handoff, when no live Claude already holds that conversation.

With a hub, `hh-hub status` shows which orchestrators a restart stopped; `hh-hub wake <project>` (or the screen's Resume)
resumes each one's own conversation in tmux and tells it to do the above.

## Tests

`bash tests/run.sh` runs every `tests/test_*.sh`, or the files it is given. `test_cleanup.sh` stops real processes, so
it is skipped, named or not, unless `HH_CLEANUP_TEST=1` is set: the owner runs it, watching. `test_hub_screen.sh` runs
the hub screen's own tests (`tests/*.test.ts`) through `claude plugin test`, with no model call, and says SKIP where
that is not available.

## Evals

Running the evals costs model usage.
