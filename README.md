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
