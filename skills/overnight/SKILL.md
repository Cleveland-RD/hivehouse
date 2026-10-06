---
name: overnight
description: Run a queue of work unattended on this machine or a named remote host, with a team of Claude sessions, a heartbeat and a morning report. Use when the owner types /hivemind:overnight.
when_to_use: When the owner wants work to continue while they are away, or to move a team to another machine for the night.
argument-hint: <what to work through>
disable-model-invocation: true
allowed-tools: Bash(hm-spawn *) Bash(hm-rotate *) Bash(hm-self-rotate *) Bash(hm-slot status) Bash(hm-slot release *) Bash(hm-context *) Bash(hm-gate-verify *) Bash(hm-settings resolve *) Bash(hm-manifest *) Bash(hm-disk *) Bash(hm-adhd) Bash(git status *) Bash(git log *) Bash(git diff *) Bash(git rev-parse *) Bash(git show *) Read Edit(./.hivemind/**) Write(./.hivemind/**) AskUserQuestion SendMessage ListAgents CronCreate CronDelete CronList
---

# hivemind: overnight

You run a queue of work while the owner is away. The work: $ARGUMENTS

First read `${CLAUDE_PLUGIN_ROOT}/rules/RULES.md` and follow it. Briefs follow `${CLAUDE_PLUGIN_ROOT}/rules/brief-template.md`;
roles are in `${CLAUDE_PLUGIN_ROOT}/roles/`. Team setup is the same as the start skill's steps 1, 4, 5 and 6 (read the
project and resume the team, name yourself, plan with the owner's OK, spawn); this skill adds what an unattended night
needs.

Call every `hm-*` executable on its own, never inside a compound command. Executables that are not pre-approved
(`hm-push`, `hm-cleanup`, `hm-gate`, `hm-slot run`, `hm-slot acquire`, `hm-remote-sync`) ask for permission each time;
that is intended, and you do not work around it. Never write permission rules into the owner's settings.

A skill's pre-approval ends at the owner's next message, and every heartbeat beat is a new turn, so from the first beat
`hm-context`, `hm-disk`, `hm-settings`, `hm-rotate` and `hm-self-rotate` are no longer pre-approved and `hm-cleanup`
never was. Overnight therefore only runs unattended in auto mode, where the classifier decides each call (step 3).

If `hm-*` is not found, the plugin is not enabled in this session: say so and stop.

**Working through the owner's hub.** When the work reads `Task <id>: read <file>. It came from the owner through <hub>`,
read that file first and register with the hub's name as the start skill's "Working through the owner's hub" says
(`hm-spawn --self --agent orchestrator --hub <hub>`). The owner is then not at this screen: they read and answer only
through the hub, so everywhere this skill says to ask them or wait for their OK, send it to the hub with `SendMessage`
instead and wait for a reply that begins `OWNER on TASK <id>:` (the owner's own words) or `HUB on TASK <id>:` (the hub's
decision, made for the owner while they are away: act on it, but what the hub keeps for the owner, such as a push, a
deploy, a paid step or deleting data, still waits for the owner's own reply):

- step 1's questions, step 2's queue, step 3's question (where to run, and the mode check) and step 5's team: first line
  `TASK <id>: HM-CLARIFY` for a question and `TASK <id>: HM-PLAN` for the queue or the team, then the same text you would
  have shown on this screen;
- a blocker during the night goes in the report as before, and also to the hub as `TASK <id>: BLOCKED` with one line, so
  an owner looking at the hub from elsewhere sees it;
- in the morning (step 7), once the report is written: `TASK <id>: DONE`, the report's path and its three to five most
  important lines.

`hm-cleanup` and the other executables that ask permission still ask on this screen, each time. The hub reads such a
dialog and shows the owner its text and options, and sends the one key for the option they choose; the owner no longer has
to be at this pane.

Run `hm-adhd`. When it prints a path, the owner uses the i-have-adhd output style: Read that file and follow it
for every message to the owner, from now on (your pickup line after a rotation names it again). When it prints nothing,
carry on as usual; never install or enable it. The morning report follows it too.

## 1. Close every open question

List the open decisions: scope, done conditions, paid steps, what may be pushed, where to run. Ask each with
`AskUserQuestion`, multiple choice, until none remain. Write `HM-CLARIFY:` before the questions. Every option must satisfy
a rule the owner has already fixed. Nobody is there to answer after this step, so an assumption made here is a
decision made for the owner: ask instead.

## 2. Write the queue

Write `.hivemind/overnight-queue.md`: each item with its done condition; each paid step with its price; what may be
pushed, naming what CI runs on that push (deploys, migrations), since a push that deploys is an outward step; and the
morning-report template from `${CLAUDE_SKILL_DIR}/morning-report.md`. Show it to the owner and take their OK.

## 3. Ask where

This machine or a named remote host (offer the hosts in `${user_config.remote_hosts}` as the choices), and with it the
permission mode. Resolve the local mode on its own call:
`hm-settings resolve permission_mode ${user_config.permission_mode_local}`.

The heartbeat in step 5 needs this session to run in auto mode, or in bypass while the owner is away (the hub's delegate
mode starts it so and `hm-settings` then resolves to `bypassPermissions`). If the resolved mode is neither `auto` nor that,
or this session is not running in one of those modes (if you cannot tell, ask the owner), do not set the heartbeat and do not start the night: tell the owner that each beat would sit
on a permission prompt with nobody there, and what they must set (`permission_mode_local` to `auto`, and this session
started in auto mode). Ask whether they want to change that or stop.

Bypass permissions only on a host listed in `${user_config.dedicated_hosts}`, and only when the owner confirms it this
time; a previous night's yes does not carry. `hm-spawn` refuses bypass on its own (exit 4), except the delegate-mode case above, which it checks against the owner's file. A bypass session on a remote
host is started by `hm-remote-sync start-agent`, which asks permission each time.

## 4. Remote host (skip on this machine)

Over ssh, with `hm-remote-sync`, in this order, each on its own call:

- `check`: free disk first, the hivemind plugin installed at the same version (a private marketplace needs git
  credentials there), and the plugin's install path, which every later remote call uses by absolute path;
- `branches`: bundles of the branches the remote lacks;
- `files`: files git does not carry, by manifest, verified by sha256;
- `memory`: copied by content into the remote's own path-derived memory folder (a different absolute path is a
  different folder, so the mapping is explicit);
- `secret`: such as `.env`, copied at mode 0600, recorded in the remote's manifest and removed by its cleanup; settings
  are compared by key hash and never printed.

Start the dev servers there and health-check them before the team starts.

## 5. Start the team and the heartbeat

Spawn as the start skill's step 6, with the models and efforts from `${user_config.model_builder}` /
`${user_config.effort_builder}` and `${user_config.model_reviewer}` / `${user_config.effort_reviewer}`. Write `HM-PLAN:`
and show the team and the queue's order; wait for the owner's OK.

Then set the heartbeat with `CronCreate`, every `${user_config.heartbeat_minutes}` minutes. Each beat:

1. `hm-context --all`, yours included; rotate any session at or above `${user_config.rotate_at_percent}`% as the start
   skill's step 8 says, yourself last.
2. `hm-disk --min-gb ${user_config.min_free_gb}`; when it reports low, `hm-cleanup --disk` (it asks permission).
3. The queue: what is done, what is next, what is blocked.
4. Spend, read the project's way, against the ceiling from `hm-settings resolve overnight_ceiling_usd ${user_config.overnight_ceiling_usd}`.
   At the ceiling, stop starting paid work and say so in the report.

Record the `CronCreate` id in your handoff, so a rotated orchestrator can `CronDelete` it (`CronList` also finds it).
A heartbeat does not survive a restart. When you were woken (resumed) in the middle of a night, run `CronList`
first: if the heartbeat recorded in your handoff is gone, create it again and record the new id.
Add a dated line to your handoff for each beat that changed something.

If a call in a beat is refused (a classifier denial or a permission error): log it in the
handoff with the command and the reason, finish everything else the beat can do, and put it in the morning report. Never
route around a refusal, never retry it differently, and never stop the night silently.

## 6. Rules for the night

- Never idle on an empty queue. Sort what is carried over; build what can be ruled on from the owner's recorded rules.
- A run said to be free proves it after its first item, by reading spend.
- No deploy, no migration, no outward message (email, chat, post, push that triggers a deploy or migration), unless the
  queue names that exact item and the owner approved it in step 2.
- One heavy job at a time: `hm-slot run` for suites, builds and browser runs, while `hm-gate` takes the slot itself. A
  gate log is read, never assumed (`hm-gate-verify`).
- A blocker that needs the owner goes in the report, not in a guess.
- Every message to the owner, the morning report included, is short and plain. End every message to the owner with
  either "Nothing needed from you." or one short sentence saying what you need from them.
- Times in the handoff and the report come from `date`, never estimated.
- After a usage-limit pause, write a dated line in your handoff, re-read your top block, and re-send any relay that was in
  flight when you stopped.

## 7. Morning

Write the report from `${CLAUDE_SKILL_DIR}/morning-report.md` to `.hivemind/morning-report-<YYYY-MM-DD>.md`, the date from `date`: what landed, what is on a branch only, spend, and the
owner's questions. Delete the heartbeat (`CronDelete`). The return trip of branches and files from a remote host, and
the remote's cleanup (`hm-remote-sync`, then `hm-cleanup --finish --dry-run` and `hm-cleanup --finish`), happen only
on the owner's word.
