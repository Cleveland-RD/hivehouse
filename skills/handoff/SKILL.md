---
name: handoff
description: Write a handoff so a fresh session with no memory can resume the work: constraints first, then state and next steps. Use when ending a session, when an agent reaches the rotation threshold, or when transferring work to another agent.
when_to_use: Also when an orchestrator asks an agent to update its START HERE block before a clear, or when told "hand off", "rotate" or "write the handoff".
---

# Session handoff

Read `${CLAUDE_PLUGIN_ROOT}/rules/RULES.md` first if you are inside a hivemind team.

Produce a handoff that lets a fresh agent with zero prior context resume work immediately.

**Core principle:** the next agent repeats every mistake you made unless you tell it not to. Transfer constraints and
lessons, not just progress.

**Announce at start:** "I'm using the handoff skill to write the handoff."

## What makes a good handoff

Most handoffs say what was done but not why decisions were made or what went wrong. The next agent needs an operating
manual, not a changelog. Priority order:

1. **Constraints and hard-won rules**: things that caused rework when violated.
2. **Current state**: where things stand right now.
3. **Next steps**: what to do next, detailed enough to start immediately.
4. **What was done**: a summary, for context only.

## Inside a hivemind team

Each agent, the orchestrator included, keeps one file: `.hivemind/handoffs/<agent>.md`. Its newest **START HERE**
block is at the top and is the agent's whole prompt after a `/clear`; older blocks and dated log lines sit beneath.

### The START HERE block

```markdown
## START HERE — <machine/context>, written <weekday date time> (from `date`) by <project>-<agent> (supersedes every block below)

I am <project>-<agent>. Report ONLY to <orchestrator>.
Rules: <the 4-6 rules that matter most now, one line each; the rest are in .hivemind/team/<agent>/RULES.md>.

STATE: <idle | mid-task: which>. Branch <b>, worktree <path>, tip <hash>. Pushed / not pushed. Gated / not gated.
DONE: <what is finished, one line each, with hashes>.
NOW: <the task in flight, and exactly where it stands>.
NEXT: <numbered, specific steps a cold reader can start on; name the files to read first>.
OPEN: <decisions waiting on the owner or the orchestrator; questions unanswered>.
LIVE STATE: <worktrees, processes, servers, temp files, drafts, anything that must be cleaned or left alone>.
```

Write it for a cold reader: no "as discussed above", no reliance on the conversation. Take the date from `date`, never
from memory. Verify every hash, path and count against the source before writing it.

### The pickup line

After a clear, the orchestrator sends this (`hm-spawn` and `hm-rotate` send it for you):

`You are <project>-<agent>. Read <root>/.hivemind/handoffs/<agent>.md from the top: its START HERE block is your prompt, and <root>/.hivemind/team/<agent>/ holds your role and the rules. Report to <orchestrator>. Wait for its first message before any work.`

<orchestrator> is the orchestrator session's own name, read when the line is sent (so a rename is followed), or
<project>-orchestrator when it cannot be read.

The orchestrator's own line, after `hm-self-rotate`, is shorter: it reports to nobody and waits for nobody.

`You are <orchestrator>. Read <root>/.hivemind/handoffs/<agent>.md from the top: its START HERE block is your prompt.`

When the owner uses the i-have-adhd output style (`hm-adhd` finds it), the line adds `Read <its SKILL.md> and follow it
for every message to the owner.`

### At the rotation threshold

When the orchestrator (or your own check) says the context is at `${user_config.rotate_at_percent}`% or above:

1. Finish or safely park the task in hand. Do not start new work.
2. Update the START HERE block, and add a dated log line for anything that happened since the last one.
3. Say "done" to the orchestrator and stop. Do nothing further: the orchestrator clears you next.

### How the orchestrator rotates

- For an agent: read every session's level with `hm-context --all`; at the threshold ask for the update; on "done" run
  `hm-rotate <agent>`. It waits until the pane is idle, sends `/clear`, checks it landed, sends the pickup line, and
  logs the levels before and after in `.hivemind/rotate.log`.
- For itself: update its own block, then `hm-self-rotate <orchestrator agent name>` as the last act of the turn. It
  detaches, waits until the orchestrator is idle, and does the same.
- After a rotation, the agent re-reads any file before editing it; a remembered file may be stale.

## Outside a hivemind team

Use this structure for a standalone handoff. Every section is mandatory; write "None" for an empty one.

```markdown
# Session Handoff

> **Date:** YYYY-MM-DD
> **Branch:** <current git branch>
> **Next task:** <one-line summary of what comes next>

---

## 1. Project Context
<2-3 sentences: what the project is, its stack, the goal.>

## 2. Spec / Source of Truth
<Path to the spec or planning document. If none exists, say so. If the spec holds the rules, say "Read this file fully
before doing anything" and give the path.>

## 3. Constraints and Rules
**These caused rework when violated. Follow them strictly.**
<One clear sentence per rule, with the why if it is not obvious. Group by category if there are more than five.>

### Hard-Won Lessons
<What went wrong and the fix: "Problem → Fix", or "Don't do X because Y happened".>

## 4. Current State
<Completed, in progress, untouched. A table if the project tracks sections or tasks.>

### Uncommitted Work
<Any uncommitted changes. "None" if clean.>

### Known Issues
<Existing bugs, broken tests, things to watch.>

## 5. File Structure
<Only the paths the next agent needs, one line each. Not a full tree.>

## 6. Next Steps
<Specific and actionable, not "continue working on X": which file to read, which step first, what to wait for.>

## 7. Workflow Reminders
<Any workflow the next agent must follow, for example "never implement before the owner approves".>
```

Location: `docs/HANDOFF.md` if `docs/` exists, else `HANDOFF.md` at the project root. A handoff is a snapshot; overwrite
an earlier one. Then tell the owner what to say to the next agent:

```
In your next session, start with:

  Read <path-to-handoff> and <path-to-spec-if-exists> before starting any work.
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Listing what was done without constraints | Constraints are the most valuable part; they prevent rework |
| Vague next steps ("continue the work") | Numbered, specific instructions the agent can follow |
| Omitting lessons learned | If something caused rework, the next agent will repeat it |
| Conversation-specific details | Write for a cold reader |
| Dumping raw file trees | Only paths the next agent needs |
| Forgetting uncommitted work | Always check `git status` and mention it |
| Not naming the spec | The spec is the first thing the next agent should read |
| A date or hash from memory | Read the date with `date`; read hashes from `git` |

## Red flags

Your handoff is bad if it reads like a git log, mentions no constraints, ends with "continue working on...", assumes the
reader saw this session, or does not say which file to read first.
