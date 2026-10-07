---
name: cleanup
description: Full owner cleanup of a hivehouse run: preview what the manifest recorded, remove it on the owner's word, and report free disk before and after. Use when the owner types /hivehouse:cleanup after or during a run.
argument-hint: [--disk]
disable-model-invocation: true
allowed-tools: Bash(hh-resolve *) Bash(hh-disk *) Bash(hh-manifest list) Bash(hh-manifest list *) Bash(hh-slot status) Read SendMessage
---

# hivehouse: cleanup

Run `hh-resolve rules` and read the file it prints first (the project's or the user's own `custom/rules/RULES.md`, else the plugin's). `hh-cleanup` is the executable that does the work; this skill is the
owner's full, supervised pass. `hh-cleanup` is deliberately not pre-approved: it prompts every time, so the owner sees
the exact command. Call each `hh-*` executable and each `git` command on its own, never inside a compound command; no
git rule is pre-approved, so each `git` call asks.

`hh-cleanup` acts only on what the manifest recorded, by typed entry (worktree, tmux pane, process, dir, file, remote),
never on anything it merely finds. A process is stopped only if its start time and command line still match what was
recorded; a tmux pane is killed by server and pane id, never by name; a worktree is removed only if clean and merged;
anything uncertain moves to `.hivehouse/trash/<date>/` rather than being deleted. Claude sessions are never touched.

**Working through the owner's hub.** When you were started with `/hivehouse:cleanup` by the owner's hub (the hub's task
file, `TASK <id>`, says so), the owner is not at this screen. Send what this skill says to show or ask them to the hub
with `SendMessage` instead, and wait for a reply that begins `OWNER on TASK <id>:` (the owner's own words; a reply that
begins `HUB on TASK <id>:` is the hub deciding while they are away, and never lets `hh-cleanup --finish` run without the
owner): the table of what is recorded and
the questions about worktrees whose work has not landed (first line `TASK <id>: HH-CLARIFY`), then the preview and
"proceed?" (`TASK <id>: HH-PLAN`). The final report goes as `TASK <id>: DONE`. `hh-cleanup` still asks permission on
this screen each time, by design; that dialog reaches the owner through the hub.

## 1. Look first

- `hh-disk --min-gb ${user_config.min_free_gb}`: free space now.
- `hh-manifest list`: what is recorded. Show the owner a short table of kind and what.
- `git status` and `git log` in the project: whether each worktree's work has landed or is still needed.
- Ask the owner (AskUserQuestion) about anything whose work has not landed: a dirty or unmerged worktree is kept and
  reported, and the owner decides what to do with it.

## 2. Preview

Run `hh-cleanup --finish --dry-run` (with `--disk` instead when `$ARGUMENTS` is `--disk`, which removes only temporary
files and directories and keeps everything else). Show the owner every line: `removed`, `kept`, `trashed` or `skipped`,
each with its reason. Change nothing yet.

## 3. Run it, on the owner's word

Only after the owner says to proceed, run `hh-cleanup --finish` (or `--disk`). Do not run it because the preview
looked fine.

`hh-cleanup` exits 2 when there is no project, 3 when `.hivehouse` is tracked by git (say so and stop: that is the
owner's to fix), 64 on a usage error and 75 when another cleanup is already running here (wait; never start a second).

## 4. Report

Free disk before and after, the count of each outcome, everything kept and why, and the trash size (`du -sh` is
printed by `hh-cleanup`). Trash does not free disk. Ask before emptying it, and empty it only on the owner's word for
that time. Never delete anything that is not on the manifest, and never delete outside the trash yourself.

End every message to the owner with either "Nothing needed from you." or one short sentence saying what you need from
them.
