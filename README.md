# hivehouse

A Claude Code plugin that runs a software task with a team of Claude sessions in tmux: an orchestrator, the agents the task needs, reviews and gates before anything lands, context rotation, unattended overnight runs, and cleanup afterwards. A hub session in your work folder hands each task to its project's orchestrator and carries your words both ways.

Skills are instructions; every mechanical action is a tested bash executable in `bin/`.

Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you. See [Customise hivehouse](docs/customise.md#customise-hivehouse).

## Delegate mode

The default is relay mode: every start, wake and answer waits for you. Delegate mode is the mode the hub runs while you are away: it decides internal work inside your projects and keeps the teams running, and it keeps pushes, deploys and spending for you. It is on only while a file only you can write says so, for at most 7 days. Details, and what it guards and does not, are in [Delegate mode (away)](docs/away-mode.md#delegate-mode-away); what you can allow it to do is in [Customising what away mode allows](docs/away-mode.md#customising-what-away-mode-allows).

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
   `hivehouse@hivehouse` (it refuses inside a repository). Then tell them to run `hh-hub start` in that folder: it opens the hub in a
   tmux session named `hub`, which opens the hub and offers to group their folders into projects. You cannot start that session for
   them: it is theirs.
5. **Tell the person what they got:** `/hivehouse:start <task>` runs a team on a task inside a project; `claude` in the
   work folder is the hub. Nothing runs until they ask.

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
- [Development](docs/development.md): running the tests and the evals.
