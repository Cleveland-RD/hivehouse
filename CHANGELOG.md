# Changelog

## 0.2.0

- Requires Claude Code 2.1.291 or later.
- The owner's hub: one session in the work folder, above every project, hands each task to that project's
  orchestrator and carries the owner's words both ways (`hm-hub`, `/hivemind:hub`). Once `hm-hub init` has set the
  folder up, a plain interactive `claude` there names itself `hub` and opens the hub (`hub_auto_start`). A project can
  span several folders. The hub wakes an orchestrator a restart stopped, resuming its own conversation, and starts one
  where none is, each on the owner's word, in the owner's local permission mode made stricter by the project's
  settings. An orchestrator running outside hivemind is found from Claude Code's session records, never doubled.
- `hm-spawn --self --hub <hub>`: the orchestrator's pickup line names the hub, so the link survives a rotation; a later
  registration keeps it (`--no-hub` drops it).
- A start stopped at a question on its screen is kept and continued (`hm-hub continue`) once the owner answers it; a
  dialog on any orchestrator's or agent's screen is reported.
- The hub's screen (`/hub-screen`): what waits on the owner, then every project's orchestrator, agents, tasks and
  folders, with Resume and Continue. In the hub's session, edits inside the work folder or a project are refused.
- A dialog that has been still is reported at once instead of after the whole wait.
- README: a section for an agent installing hivemind from its link.

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
