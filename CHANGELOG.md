# Changelog

## 0.1.2

- After a restart: `hm-context` marks a session that is no longer running, keeping its last level, and
  `hm-spawn --respawn <agent>` starts a stopped agent again from its own record and sends it back to its handoff.
- One check decides whether a team member still runs as recorded, read from its process first: `hm-rotate`,
  `hm-context` and `hm-spawn --respawn` all use it.

## 0.1.1

- Context levels use Claude Code's own window for spawned agents; a guessed window is marked as assumed.
- Agents report to the orchestrator's real session name; the orchestrator's own pickup line waits for nobody.
- `hm-spawn --self` records the orchestrator's session, so its context level reads from the start.
- An agent spawned without `--session` goes beside the calling pane.
- Commit before the gate: `hm-gate` warns on a dirty tree, and an unchecked GREEN says so; `hm-gate` is never wrapped
  in `hm-slot run`.
- Every message to the owner ends with "Nothing needed from you." or what is needed.
- The optional i-have-adhd plugin's rules are used when it is installed and enabled; hivemind never installs it.

## 0.1.0

- First version.
