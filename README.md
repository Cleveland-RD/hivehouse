# hivemind

A Claude Code plugin that runs a software feature or task with a team of Claude sessions in tmux: one orchestrator,
the agents the task needs, reviews and gates before anything lands, context rotation, unattended overnight runs on this
machine or a remote host, and cleanup afterwards.

It carries working methods proven on one long project and nothing specific to that project: every project fact lives in
the project's own CLAUDE.md (or CLAUDE.local.md) and memory. Skills are instructions; every mechanical action is a
tested bash executable in `bin/`.

## Requirements

tmux ≥ 3.0, jq, git ≥ 2.31, bash (3.2 is enough), ssh/rsync/shasum for remote runs, Claude Code ≥ 2.1.271.

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
| `/hivemind:docs-health-check` | owner | documentation sweep, report mode by default |

## State

- `<project>/.hivemind/` — handoffs, team, manifest, settings, trash; excluded through the repo's `info/exclude`, never tracked.
- `${HIVEMIND_HOME:-~/.hivemind}` — per machine: the heavy-job slot and the registry of running teams.

## Evals

Running the evals costs model usage.
