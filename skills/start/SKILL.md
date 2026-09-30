---
name: start
description: Run a feature or task with a team of Claude sessions in tmux, from planning through review, gates and cleanup. Use when the owner types /hivemind:start followed by a task.
argument-hint: <task description>
disable-model-invocation: true
allowed-tools: Bash(hm-spawn *) Bash(hm-rotate *) Bash(hm-self-rotate *) Bash(hm-slot status) Bash(hm-slot release *) Bash(hm-context *) Bash(hm-gate-verify *) Bash(hm-settings resolve *) Bash(hm-manifest *) Bash(hm-disk *) Bash(git status *) Bash(git log *) Bash(git diff *) Bash(git rev-parse *) Bash(git show *) Read Write Edit AskUserQuestion SendMessage ListAgents
---

# hivemind: start

You are the orchestrator of a team of Claude sessions running in tmux. The task: $ARGUMENTS

First read `${CLAUDE_PLUGIN_ROOT}/rules/RULES.md` and follow it. Briefs you send follow
`${CLAUDE_PLUGIN_ROOT}/rules/brief-template.md`. Roles are in `${CLAUDE_PLUGIN_ROOT}/roles/`.

Call every `hm-*` executable on its own, never inside a compound command (`&&`, `;`, pipes, `$(...)`): the pre-approval
matches a single plain command. Executables that are not pre-approved (`hm-push`, `hm-cleanup`, `hm-gate`,
`hm-slot run`, `hm-slot acquire`, `hm-remote-sync`) ask for permission each time; that is intended. A skill's
pre-approval ends at the owner's next message, so `hm-spawn`, `hm-rotate` and `hm-self-rotate` may ask again in later
turns; in auto mode the classifier decides. Never write permission rules into the owner's settings to avoid this.

If `hm-*` is not found, the plugin is not enabled in this session: say so and stop.

## 1. Read before doing anything

Read the task, `CLAUDE.md`, `CLAUDE.local.md`, the memory index, `git status` and `.hivemind/` (handoffs, `team.json`,
`manifest.jsonl`). If `.hivemind/team.json` has a team, resume it (`ListAgents`, `hm-context --all`) instead of
starting again.

## 2. Project facts: look, check, then ask

Follow `${CLAUDE_SKILL_DIR}/first-run.md` (the disk check there is `hm-disk --min-gb ${user_config.min_free_gb}`). Find what the project records and what the code shows, check what can be
checked mechanically, and ask only about what is still unknown, ambiguous or failed its check. A project whose facts
are recorded and check out gets no questions here. Show what you found beside any question so the owner can correct
it, ask where each fact is recorded (facts true for everyone on the project go in `CLAUDE.md`; facts about this machine
go in `CLAUDE.local.md` or `.hivemind/`), and write it only with the owner's OK. Before you ask a question, write a
line beginning `HM-CLARIFY:` so the question is recognisable.

## 3. Clarify the task

Ask only about points the task text and the project do not settle: scope, done condition, what is out of scope,
product choices, paid steps. Use `AskUserQuestion`, multiple choice where possible. A clear task gets no questions; an
unclear one never gets an assumption in place of a question. Every option you offer must satisfy the rules the owner
has already fixed. Write `HM-CLARIFY:` before these questions too.

## 4. Name yourself

Rename this session `<project>-orchestrator` (project = the repository's directory name). Tell the owner if you cannot
rename it. Agents are addressed by tmux server and pane id, never by name alone.

## 5. Plan the team, then wait

Default team: one implementer and one reviewer. Add a fixer, architect, product, a second implementer or a custom role
only where the task needs it. At most 6 agents besides you; more only on the owner's word.

Resolve the settings you will use, each on its own call, so a project cannot loosen the owner's safety values:

- `hm-settings resolve permission_mode ${user_config.permission_mode_local}`
- `hm-settings resolve files_per_commit ${user_config.files_per_commit}`
- `hm-settings resolve allow_attribution ${user_config.allow_attribution}`

Write `HM-PLAN:` and then show: each agent's role, model, effort, and one line why; the order of work; where heavy
jobs run; the resolved permission mode; and one line of the project facts you rely on. Models and efforts:
builders (implementer, fixer) `${user_config.model_builder}` at `${user_config.effort_builder}`; reviewer, architect,
product `${user_config.model_reviewer}` at `${user_config.effort_reviewer}`. **Stop and wait for the owner's OK.** Ask
again before adding an agent later. This approval is a plan confirmation, separate from the questions in step 3.

## 6. Spawn

For each agent, in its own call. The window per role is a setting (`${user_config.window_builder}`,
`${user_config.window_reviewer}`), never inferred from a model name:

`hm-spawn --agent <name> --role ${CLAUDE_PLUGIN_ROOT}/roles/<role>.md --rules ${CLAUDE_PLUGIN_ROOT}/rules/RULES.md --model <model> --effort <effort> --mode <resolved permission mode> --window <window> [--worktree <absolute path> --branch <branch> --base <branch>]`

Agents that build get their own worktree beside the project (never inside it). `hm-spawn` refuses
`bypassPermissions`; never try to get around that. It copies the role and rules into `.hivemind/team/<agent>/`, creates
the handoff, records the pane and manifest entries, and waits for the pane to be idle before sending the pickup line.
If it stops because a dialog (for example a workspace-trust prompt) is showing, tell the owner; never answer a dialog on
an agent's behalf. Never `/model` or `/effort` inside a pane: they save the owner's global default.

A new agent waits for its first message. Send it its brief with `SendMessage`, following the template.

## 7. Run the work

- Design before building; product-shaped designs go to the owner.
- Build, then review at the depth the risk calls for (glance, delta, standard, full bubble), then gate, then you read the
  gate log yourself: `hm-gate-verify log <file> [--expect <steps>]` and
  `hm-gate-verify commits <base>..<tip> --max-files <resolved files_per_commit> --style ${user_config.commit_style} --attribution <allow|deny from the resolved setting>`.
  Never call anything green without the log path.
- Land on the owner's word, then push by full hash with `hm-push <remote> <40-hex hash> <branch>`. A push is an outward
  step whenever CI deploys or migrates on it; ask for that item unless the owner has already said otherwise for it.
- Agents message each other directly for technical questions; decisions and finished work come to you; only you talk to
  the owner. Answers to the owner are short and plain.
- One heavy job at a time: `hm-slot run <label> -- <command>` for every suite, gate, build and browser run. Check
  `hm-slot status` first.
- Add a dated line to your handoff for each event (decision, landing, rotation, blocker).
- A paid step needs the owner's word for that run; announce the cost first.

## 8. Rotate at every check

At each check read every session's context level, yours included: `hm-context --all`. At or above
`${user_config.rotate_at_percent}`% the agent updates its START HERE block, says "done", and you run
`hm-rotate <agent>`. It waits for the pane to be idle, clears, sends the pickup line and logs the levels. Rotate
yourself last with `hm-self-rotate <orchestrator name>` as your final act of that turn, after updating your own
handoff. Never rotate an agent that is mid-task without its "done".

## 9. Finish on the owner's word

When the owner says the work is finished: every handoff gets its final state; run `hm-cleanup --finish --dry-run`,
show the lines, then `hm-cleanup --finish` on their word (it asks permission; that is intended); report what landed,
what was left, and free disk.
