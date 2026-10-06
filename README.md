# hivemind

A Claude Code plugin that runs a software feature or task with a team of Claude sessions in tmux: one orchestrator,
the agents the task needs, reviews and gates before anything lands, context rotation, unattended overnight runs on this
machine or a remote host, and cleanup afterwards. Above every project sits the owner's **hub**: one session in the
work folder that hands each task to that project's orchestrator and carries the owner's words both ways.

It carries working methods proven on one long project and nothing specific to that project: every project fact lives in
the project's own CLAUDE.md (or CLAUDE.local.md) and memory. Skills are instructions; every mechanical action is a
tested bash executable in `bin/`.

## Requirements

- tmux ≥ 3.2 (`new-session` and `new-window` take `-e`; hm-spawn hands each pane its environment that way)
- git ≥ 2.31; ≥ 2.38 for `hm-gate-verify commits` to count a merge's own files exactly (`merge-tree --write-tree`;
  before it a merge is counted by `--cc`, which is near and not exact)
- bash (the macOS 3.2 is enough), jq, perl and shasum (both ship with macOS)
- ssh and rsync, for remote runs
- Claude Code ≥ 2.1.291 (the hub's screen is a function-hooks module, `hooks/hub.tsx`, named under `modules` in
  `hooks/hooks.json`; built and tested on 2.1.291)

The idle check reads the Claude Code terminal UI (the prompt box and the dialog wording), checked against 2.1.x. The text it
looks for is in one place, `HM_DIALOG_TEXT` and `hm_pane_idle_text` in `bin/hm-lib.sh`; update it there when a release
changes the screen.

`hm-*` executables are on the PATH only inside Claude sessions where the plugin is enabled. To run one by hand, call it
by its install path (`claude plugin list --json` shows it), for example `<installPath>/bin/hm-slot status`.

## Install

```
claude plugin marketplace add Cleveland-RD/hivemind
claude plugin install hivemind@hivemind
```

## For an agent installing this

A person may hand you this repository's link and say "install this". Do these steps in order; each says how to check it.
Where a step says **ask**, ask the person and wait: never decide it for them.

1. **Check what it needs.** Run each and compare with Requirements above:
   `tmux -V`, `git --version`, `jq --version`, `perl -v`, `shasum --version`, `claude --version`.
   If one is missing or too old, tell the person which, and how they would add it (on macOS: `brew install tmux jq`).
   **Ask** before installing anything yourself.
2. **Install the plugin** with the two commands under Install. Check it is there and enabled:
   `claude plugin list --json | jq '.[] | select(.id == "hivemind@hivemind") | {version, enabled}'`.
   It must print the version in `.claude-plugin/plugin.json` and `"enabled": true`.
3. **Settings.** The plugin's settings are its `userConfig` in `.claude-plugin/plugin.json` (models, efforts, permission
   mode, files per commit, rotation level, overnight ceiling, `hub_auto_start`); each has a default, so nothing must be
   set. **Ask** whether the person wants any changed; Claude Code's `/plugin` menu changes them.
4. **The hub (optional).** **Ask** whether they want one, and which folder is their work folder: the one that holds
   their projects, never a project itself. On their yes, set it up there:
   `cd <folder> && <installPath>/bin/hm-hub init`, with the `installPath` that `claude plugin list --json` shows for
   `hivemind@hivemind` (it refuses inside a repository). Then tell them to start `claude` in that folder: it names
   itself `hub`, opens the hub, and offers to group their folders into projects. You cannot start that session for
   them: it is theirs.
5. **Tell the person what they got:** `/hivemind:start <task>` runs a team on a task inside a project; `claude` in the
   work folder is the hub. Nothing runs until they ask.

Never: start agents or sessions the person did not ask for, start a session in `bypassPermissions` (hivemind does it only while the owner is away, through the owner's delegate file), install the
optional i-have-adhd plugin unasked, or push anything.

## Optional: i-have-adhd

[i-have-adhd](https://github.com/ayghri/i-have-adhd) shapes output for an ADHD reader. It is not a dependency: when it
is installed and enabled, the orchestrator reads its rules at the start and after every rotation and follows them in
every message to the owner; when it is not, nothing changes. hivemind never installs, enables or switches it on.

```
claude plugin marketplace add ayghri/i-have-adhd
claude plugin install i-have-adhd@i-have-adhd
```

In any other session, `/i-have-adhd` turns it on. Its INSTALL.md also describes an always-on mode; with that on, the
plugin applies itself everywhere and hivemind does not load it a second time.

## Skills

| Skill | Who runs it | What it does |
|---|---|---|
| `/hivemind:hub` | owner | the hub: hand tasks to each project's orchestrator, wake them, report back (starts by itself in the hub's folder) |
| `/hivemind:start` | owner | plan, approve and run a team on a task |
| `/hivemind:overnight` | owner | queue and run unattended, here or on a remote host |
| `/hivemind:gate` | orchestrator, builders | run the gate into a log and verify every step |
| `/hivemind:bubble-review` | reviewer | review a diff by depth, nine bubble categories |
| `/hivemind:handoff` | any agent | write the handoff and START HERE block |
| `/hivemind:cleanup` | owner | remove what the manifest recorded |
| `/hivemind:review-plan`, `/hivemind:doc-updater` | any | moved-in skills |
| `/hivemind:docs-health-check` | owner | documentation sweep of the current project, report mode by default (a workflow, not a skill) |

`docs-health-check` is a Claude Code workflow: `workflows/docs-health-check.workflow.js`, with no `SKILL.md`. Claude Code's plugin docs say a `workflows/` directory at the plugin root is loaded without a manifest entry and that a plugin workflow runs as `/<plugin>:<meta.name>`. **Unverified here:** it has not been run through a live Claude Code session, only through a stand-in for the workflow runtime (`tests/test_docs_health.sh`). The report is written to `.hivemind/reports/` (git-ignored), so report mode leaves the working tree as it was; when `.hivemind/` is tracked or cannot be written, it goes to `$TMPDIR` outside every repository and the returned path says so; `apply` mode edits the working tree and never commits.

## The hub

One Claude session in the owner's work folder, the folder above every project, is the owner's entry point:

- **Set up once.** Run `hm-hub init` in the work folder (it refuses inside a repository). An agent installing hivemind
  does this for you; `/hivemind:hub` in a session there offers it too, then asks you to start `claude` again, since a
  session started before the folder was the hub has no screen and no guard. From then on every session started in
  that folder, and only there, is the hub: a new, unnamed one names itself `hub` (`hub-2` beside another, since
  orchestrators reply to the hub by name) and opens the hub by itself, which takes one model turn. The `hub_auto_start`
  setting turns that off; then start it with `claude --name hub /hivemind:hub`.
- **Projects span folders.** A project is its home, the repository its team works from, and any other folders it
  covers (`hm-hub add <project> --home <folder> --repo <folder>...`). The hub proposes the groups from `hm-hub discover`
  and adds only what the owner confirms.
- **Handing work over.** The owner's words go to the ledger and a task file (`hm-hub task`), then to the project's
  orchestrator: a message when it runs; `hm-hub wake` when a restart stopped it, which resumes its own conversation (its
  own model) and tells it to register with the hub and bring its agents back; `hm-hub start` when there is none. An
  orchestrator already running outside hivemind is found in Claude Code's own session records and never doubled. Each
  start asks the owner first, and runs in the owner's local permission mode (`permission_mode_local`, the one hivemind's
  agents run in), made stricter where the project's own `.hivemind/settings.json` says so. Start the hub in that mode
  too: sessions in different modes hold each other's messages for an approval nobody sees.
- **Through the hub.** The orchestrator registers with `hm-spawn --self --hub <hub>`, so every pickup line, after each
  rotation too, says the owner talks through the hub. It sends its questions, plan, blockers and results there; the hub
  shows them word for word and carries the answer back. The ledger records each task's state; a plan, a question and a
  blocker wait on the owner.
- **Nothing stuck, nothing unseen.** A start that stops at a question on its screen is kept: once the owner answers it,
  `hm-hub continue` (or the screen's Continue) sends the line, and never while the start's own line is still on its way.
  A dialog waiting on any orchestrator's or agent's screen is shown to the owner.
- **Claude Code's session records.** Naming itself and finding orchestrators outside hivemind read
  `~/.claude/sessions/<pid>.json`, which Claude Code keeps and does not document. Without them the hub names nothing
  (the person types `/rename hub`) and finds only orchestrators hivemind registered; nothing else changes.
- **The screen.** `/hub-screen` (or a wide terminal, at start) opens a pane: what waits on the owner, then each
  project's orchestrator, agents, tasks and folders, with Resume and Continue buttons. It reads `hm-hub` only while shown.
- **Hands off the code.** The hub never reviews, builds, tests, commits or pushes. In the hub's session the module
  refuses an edit inside the work folder (apart from `.hivemind-hub/`) or inside a project's folder, and a git command
  that changes a repository; quoted text and heredocs are the owner's words, never a command (best effort for shell).

### Overnight and cleanup through the hub

`/hivemind:overnight` and `/hivemind:cleanup` can only be started by a person typing them. The hub types them for the owner: `hm-hub run <project> overnight <task id>` and `hm-hub run <project> cleanup <task id> [--disk]`. Only these two skills, only a line `hm-hub` builds, only into the project's running, registered orchestrator, and only after the owner's yes for that one run. It refuses a task that waits on the owner, a task already in an overnight run, and a second run while one is being typed. The task then shows as `overnight` or `cleanup`, open and not waiting on the owner.

### Dialogs through the hub

A permission prompt or another dialog on an orchestrator's or agent's screen is shown to the owner with its options (`hm-hub dialog <project> [<agent>]`). The owner can answer it from the hub: `hm-hub answer <project> [<agent>] --choice <1-9|esc> --seen <fingerprint>`, which presses the one key (or, for a menu with no numbers, moves the cursor and presses Enter as the last key of that choice) after checking that the dialog is still the one the owner saw. The hub never offers the options that need the owner's own words, "Type something" and "Chat about this": those are answered in the pane. An option that saves a permission rule ("always allow…") is marked as such when it is shown. Every answer is logged to `.hivemind-hub/answers.jsonl`, not to the task ledger, because a dialog belongs to no task. Limits: two identical dialogs in a row share a fingerprint, and the screen's one-press-at-a-time lock is what stops a repeat; multi-select and multi-question dialogs are untested.

### Delegate mode (away)

Relay mode, where every start, wake and answer waits for the owner, is the default and is unchanged. Before leaving, the owner can switch delegate mode on. The hub then decides internal work itself, keeps the teams running, and keeps for the owner only what must be theirs.

**Switching it on and off.** `hm-hub away --until <time> [--mcp-allow <list>]` prints lines for the owner to paste; `hm-hub back` prints the line that ends it. hivemind never runs `sudo` and never asks for a password: the lines create one file as root, so a changed script cannot capture the password and the owner sees exactly what runs as root.

- **The file.** `/Library/Application Support/hivemind/delegate` on macOS, `/etc/hivemind/delegate` on Linux. Line 1 is `hivemind-delegate 1`, then `hub=<the hub's folder>`, `until=<epoch seconds>` and `mcp=<list>`, the MCP servers the owner allowed (letters, digits and `_ , . : -`), which the `sudo` lines `hm-hub away --mcp-allow` prints write. The hub's allowed servers come from this file, never from `away.json` or the environment. Delegate mode is on exactly while this file is valid. Valid means: the file, its folder and every folder above it are not links and not writable by group or others; the file and its folder are owned by root; the content is exactly those four lines; and `until` is in the future. No environment variable or setting changes the path, the owner or the content, and every executable that asks starts with `#!/bin/bash -p` and calls outside commands by absolute path, so a fake `date`, a function or a `BASH_ENV` cannot revive an expired file.
- **At most 7 days.** `until` may be at most 7 days ahead. The hub's heartbeat is a `CronCreate` job: it lives only as long as the hub's session, fires only while the hub is idle, and a recurring one expires after 7 days. After a reboot nothing runs until the owner starts the hub again.
- **Before leaving, two things only the owner can do**: Claude Code shows a one-time warning the first time it runs in bypass mode (`Yes, I accept`; it then writes `skipDangerousModePermissionPrompt` to the user's settings), and a folder-trust dialog for every folder it has not trusted. `hm-hub away` checks both, for the hub's folder and for every folder of every project it lists, and prints what is missing. Claude Code decides trust per folder: a git repository does not inherit it from the folder above, and a worktree is judged by its main repository's entry, so one line covers a repository and its worktrees. `hm-spawn` warns when a worktree it is about to use would stop at that dialog. Nobody can answer these dialogs while the owner is away.
- **The hub starts marked.** The start line `hm-hub away` prints runs the hub in bypass with `HM_AWAY_BYPASS=1`, `HM_PROJECT`, `HM_AWAY_HUB` and `HM_AWAY_MCP_ALLOW` in its launch environment, and with only the MCP servers named in the file's `mcp=` line. The owner exits the running hub first, so two do not share the folder. The hub acts in delegate mode only when `printenv HM_AWAY_BYPASS` prints `1`.
- **Bypass is granted only under three conditions together**: the owner's delegate file is valid and lists the project's home, the caller's own Claude carries the away marker, and the owner's `permission_mode_local` is `auto` (a stricter value, or a project's own tighter setting, keeps a session out of bypass). Bypass is never a value the owner or a project can name. An orchestrator the hub starts or wakes and an agent `hm-spawn` starts get it on those terms. `hm-remote-sync start-agent` never starts bypass; a dedicated host is where the owner may start a bypass session by hand.
- **When it ends** (`hm-hub back`, or the file expires), the hub tells the owner to restart it out of bypass, and until they have, it asks before every start, wake, run or answer, as in relay mode.

**What the hub decides, and what it keeps for the owner.** It decides plans and questions about work inside the project's own repositories and branches, its tests, its agents and their number, worktrees, overnight runs of tasks the owner gave, and wake, start, continue and run for those tasks. It keeps for the owner: a push, a merge, a deploy or migration, anything that sends or publishes outside the machine, a paid step, deleting data that is not the team's own scratch, a change to settings or permissions, a new task, and every screen dialog. A kept item is logged as a question, its task waits, and other tasks go on. `hm-hub hold <project>` keeps the hub away from a project altogether.

While the owner is away the hub never answers a screen dialog (`hm-hub answer` refuses; `hm-hub dialog` still reads it). Its answers go out as `HUB on TASK <id>: <decision>`, never `OWNER on TASK`, so an orchestrator always knows whose words it has. Each decision is recorded, with the question and the answer word for word, in `.hivemind-hub/decisions/<task id>.md` and a `decided` event (`hm-hub decide`). When the owner is back, the hub opens with what it decided since they left, and the screen keeps "decided while you were away" until the owner presses Seen (`hm-hub status --json` shows `hub.last_away` after away ends).

**Keeping the teams running.** On each beat the hub runs `hm-hub recover --json --max-starts <hub_max_starts_per_day>` and carries out what it prints: wake a stopped orchestrator that has an open task, send an orchestrator `RESPAWN:` for agents that stopped, restart a hung session (below), and list a dialog for the owner. The same action on the same item is tried at most 3 times in 24 hours, then the task is blocked for the owner; and at most `hub_max_starts_per_day` sessions are started or woken in 24 hours, each wake counted as it is decided, so two stopped orchestrators and room for one wake one. That daily cap is a guideline the hub passes, not a guard: the hub runs in bypass and could ignore it. Spend is not tracked here: overnight runs stop at their own ceiling.
**Hung sessions.** A hung session is restarted, never typed into. It counts as hung only on positive evidence: Claude Code's working line (`✳ Effecting… (3s · thinking)`) is recognised, and its elapsed time is the same on every beat for 15 minutes, for the same process. A screen hivemind does not recognise is "unknown" and is never restarted; a session that is slow but still counting is not hung. The hub then stops that Claude process by its recorded process id and start time, never by name or pattern: it checks again that the process is the recorded one, is Claude, is not the hub's own, runs under the pane whose screen it read, and that the screen still shows the same line; it sends TERM, waits up to 10 seconds, and sends KILL only if it is still the same process. This is the one place hivemind stops a process it did not start; `rules/RULES.md` names it, and it applies to the hub's recover only, in delegate mode, not to agents. The session is then resumed in its own conversation: an orchestrator by `hm-hub wake`, an agent by `hm-spawn --respawn <agent> --resume`, typed one short line ("You were restarted by hivemind after your session stopped responding…") instead of the full pickup line. A session is restarted at most 3 times in 24 hours, then its task is blocked for the owner; a hung orchestrator is stopped only while the daily cap leaves room to wake it; a stop that does not take is reported once and not tried again for 24 hours.

**One limit.** The hub reads only a project's home. A team whose orchestrator works from another worktree is not seen unless that orchestrator also registers in the home (`hm-spawn --self --hub <hub>`), and then the hub shows it running with no agents.

### What away mode guards, and what it does not

**Away mode is not a sandbox.** In bypass, any session can run any command as the owner's user, with the owner's files and credentials. The refusals below stop the actions delegate keeps for the owner; they are not a security boundary, and switching away on means trusting the teams the hub runs.

**Who is guarded: the marker.** A session hivemind launches in bypass while away carries `HM_AWAY_BYPASS=1` in its launch environment. Every guard keys on it. On macOS, `ps -E` shows no environment for Apple's own programs (bash, sleep) and shows it for others, such as Claude: the marker is read from the Claude process, and a session whose environment cannot be read is refused, never trusted. A Bash command can unset it for itself, so the hook, not the scripts, is the guard. When a session carries no marker (the owner's own bypass sessions, `dedicated_hosts` runs) nothing here applies. If delegate mode ever has to run in `auto` instead of bypass, there is no marker and no refusals: outward steps are left to the auto classifier and to prompts nobody answers, as in overnight today.

**The hook.** `bin/hm-away-hook` is a `PreToolUse` command hook, wired in `hooks/hooks.json` for Bash, MCP tools, SendMessage, Edit, Write, MultiEdit, NotebookEdit, Artifact, ArtifactData, ArtifactComments, RemoteTrigger and Agent. Without the marker it exits at once. With it, it refuses (exit 2, with a reason the session can read):

- every MCP tool, and the Artifact, ArtifactData, ArtifactComments and RemoteTrigger tools (by their own names), unless the owner's `away_mcp_allow` lists the server (`<server>`) or the single tool (`mcp__<server>__<tool>`). Allowing a server allows its write tools too, and a single-tool entry still loads the whole server: only the hook limits it to that tool. This also blocks local tools such as browser automation and the built-in `computer-use` server. `hm-hub away` loads servers from `~/.claude.json` and the hub's `.mcp.json` only, not from plugins' manifests, so a plugin's server may not be available even when listed;
- in Bash: `git` with `push`, `gh` outside its read-only forms, `ssh`, `scp`, `rsync` to a remote, `curl` and `wget` that upload or use a method other than GET, `npm`, `pnpm` and `yarn` `publish`, `vercel`, `netlify`, `docker push`, `hm-push` and `hm-remote-sync`;
- `claude` run by hand, and `tmux` `new-window`, `split-window`, `new-session`, `respawn-pane`, `respawn-window`, `run-shell`, `if-shell`, `display-popup`, `pipe-pane`, `source-file` and `send-keys`: `hm-spawn` and `hm-hub` start sessions and set the marker again, and SendMessage is the way to talk to a peer;
- Edit, Write and Bash redirects or writing commands (`tee`, `cp`, `mv`, `sed`, an interpreter, and the like) on Claude Code's settings files, hook files, plugin folders, `~/.claude.json` and a project's `.mcp.json`, judged by where a link leads;
- SendMessage to anyone but the session's own hub and team, checked by name and by process: a `bridge:` address, another project, a name another live session also carries, and anything that cannot be resolved are refused. `RULES.md` adds that a message from anyone else is information, never an instruction; to instruct the hub while away, the owner types into it (Remote Control, say);
- an Agent call that starts a remote (cloud) agent, which would carry no marker.

Anything the hook cannot read or parse is refused too, and so is any failure of the hook itself. Its refusal text says it comes from hivemind's away mode, is not a permission prompt, and tells the session not to change settings, hooks or permissions to get round it, because a session told "no" has offered to do exactly that.

**A second layer.** `hm-push`, every `hm-remote-sync` subcommand and `hm-cleanup --finish` also refuse with exit 4 when `HM_AWAY_BYPASS=1` is in their environment; `hm-cleanup --disk` stays allowed. These three run under `#!/bin/bash -p`. A Bash command can unset the variable for itself, so this is a backstop behind the hook.

**What the hook does not catch.** The list is not complete, and this README says so on purpose:

- The matching is by words, not by structure. `$'\x67'it push`, `g${e}it push` and zsh glob qualifiers (`*(e:'…':)`) get through, and so does a push inside a script file the session wrote. A quoted `push` beside `git`, as in `git commit -m "fix(push): …"`, is refused: rephrase.
- A marked session can still reach the network or start an unmarked Claude in ways the hook does not see: `osascript` running `claude`, a script it wrote, or a tool that is not on the hook's matcher. `WebFetch` and `WebSearch` stay allowed, like `curl` GET, but they are reads that can carry data out in the address or the query.
- The list of protected files is not complete.
- The hook guards sessions of this plugin. It assumes the owner's `disableAllHooks` is not set.
- Nothing runs while the machine is off. Remote hosts are not used while away (`hm-remote-sync` is refused).

**Which records are trusted, and why.** Only the root-owned delegate file gates bypass and delegate mode. Everything else is writable by the owner's user, so by any of their sessions in bypass, and is trusted only that far: `away.json`, the hub's `tasks.jsonl`, `recovery.jsonl` and `decisions/`, a project's `.hivemind/settings.json` and `team.json`, and Claude Code's own settings. `projects.json` is user-writable too: a session could list another folder during an away period the owner opened.

## State

- `<project>/.hivemind/` — handoffs, team, manifest, settings, trash; excluded through the repo's `info/exclude`, never tracked.
- `${HIVEMIND_HOME:-~/.hivemind}` — per machine: the heavy-job slot and the registry of running teams.
- `<work folder>/.hivemind-hub/` — the hub's projects, task ledger and task files, its notes per project; outside every
  repository.

## After a restart

A restart of the machine or of tmux takes the team's panes with it. `hm-context --all` then marks each session
"(not running)", keeping its last level. The orchestrator registers itself again with `hm-spawn --self --agent
orchestrator`, then runs `hm-spawn --respawn <agent>` for each agent so marked: the agent starts again from its own
record (model, effort, permission mode, worktree and branch from `team.json`, role and rules from
`.hivemind/team/<agent>/`) and is sent back to its handoff. A running agent, one whose state cannot be told, and the
orchestrator itself are never respawned.

With a hub, `hm-hub status` shows which orchestrators a restart stopped; `hm-hub wake <project>` (or the screen's Resume)
resumes each one's own conversation in tmux and tells it to do the above.

## Tests

`bash tests/run.sh` runs every `tests/test_*.sh`, or the files it is given. `test_cleanup.sh` stops real processes, so
it is skipped, named or not, unless `HM_CLEANUP_TEST=1` is set: the owner runs it, watching. `test_hub_screen.sh` runs
the hub screen's own tests (`tests/*.test.ts`) through `claude plugin test`, with no model call, and says SKIP where
that is not available.

## Evals

Running the evals costs model usage.
