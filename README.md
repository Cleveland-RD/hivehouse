# hivemind

A Claude Code plugin that runs a software feature or task with a team of Claude sessions in tmux: one orchestrator,
the agents the task needs, reviews and gates before anything lands, context rotation, unattended overnight runs on this
machine or a remote host, and cleanup afterwards.

It carries working methods proven on one long project and nothing specific to that project: every project fact lives in
the project's own CLAUDE.md (or CLAUDE.local.md) and memory. Skills are instructions; every mechanical action is a
tested bash executable in `bin/`.

## Requirements

- tmux ≥ 3.2 (`new-session` and `new-window` take `-e`; hm-spawn hands each pane its environment that way)
- git ≥ 2.31; ≥ 2.38 for `hm-gate-verify commits` to count a merge's own files exactly (`merge-tree --write-tree`;
  before it a merge is counted by `--cc`, which is near and not exact)
- bash (the macOS 3.2 is enough), jq, perl and shasum (both ship with macOS)
- ssh and rsync, for remote runs
- Claude Code ≥ 2.1.271

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

## Skills

| Skill | Who runs it | What it does |
|---|---|---|
| `/hivemind:start` | owner | plan, approve and run a team on a task |
| `/hivemind:overnight` | owner | queue and run unattended, here or on a remote host |
| `/hivemind:gate` | orchestrator, builders | run the gate into a log and verify every step |
| `/hivemind:bubble-review` | reviewer | review a diff by depth, nine bubble categories |
| `/hivemind:handoff` | any agent | write the handoff and START HERE block |
| `/hivemind:cleanup` | owner | remove what the manifest recorded |
| `/hivemind:review-plan`, `/hivemind:doc-updater` | any | moved-in skills |
| `/hivemind:docs-health-check` | owner | documentation sweep of the current project, report mode by default (a workflow, not a skill) |

`docs-health-check` is a Claude Code workflow: `workflows/docs-health-check.workflow.js`, with no `SKILL.md`. Claude Code's plugin docs say a `workflows/` directory at the plugin root is loaded without a manifest entry and that a plugin workflow runs as `/<plugin>:<meta.name>`. **Unverified here:** it has not been run through a live Claude Code session, only through a stand-in for the workflow runtime (`tests/test_docs_health.sh`). `apply` mode edits the working tree and never commits.

## State

- `<project>/.hivemind/` — handoffs, team, manifest, settings, trash; excluded through the repo's `info/exclude`, never tracked.
- `${HIVEMIND_HOME:-~/.hivemind}` — per machine: the heavy-job slot and the registry of running teams.

## Evals

Running the evals costs model usage.
