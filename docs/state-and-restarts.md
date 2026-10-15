# State and restarts

## State

- `<project>/.hivehouse/`: handoffs, team, manifest, settings, trash; excluded through the repo's `info/exclude`, never tracked.
- `${HIVEHOUSE_HOME:-~/.hivehouse}` (per user): the registry of running teams, and the heavy-job slot unless the machine has one (below).
- `<project>/.hivehouse/custom/` and `${HIVEHOUSE_HOME:-~/.hivehouse}/custom/`: your own roles, rules and brief template, which an update of the plugin never replaces ([Customise hivehouse](customise.md#customise-hivehouse)).
- The machine's heavy-job slot: one for every user, so two people's jobs queue instead of starving each other. An
  administrator makes it once, from lines `hh-slot setup` prints (`hh-slot setup <group>` on Linux): `slot/` and
  `slot/queue/` under `/Library/Application Support/hivehouse` on macOS or `/var/lib/hivehouse` on Linux, owned by root,
  mode exactly 2775, under folders only root can write. hivehouse never runs sudo. Until that folder passes every check,
  each user has a slot of their own, and `hh-slot status` says why. `hh-slot run --wait [<seconds>] <label> -- <command>`
  and `hh-slot acquire <label> --pid <pid> --wait [<seconds>]` queue in the order they asked; without `--wait` the
  answer is 75 at once, also while others wait. `HH_SLOT_LOCAL=1` opts out of the machine slot for one process and
  can never name another folder. The slot is coordination, not a security boundary: a user can file fake tickets and
  delay the others.
- `<work folder>/.hivehouse-hub/`: the hub's projects, task ledger and task files, its notes per project; outside every
  repository. Delegate mode adds `hub.json` (which Claude is the hub), `away.json`, `decisions/<task id>.md`,
  `answers.jsonl` (dialogs answered through the hub), `recovery.jsonl` and `recovery-state.json`, `hung-state.json` and
  `holds/<project>`.
- `/Library/Application Support/hivehouse/delegate.d/<uid>` (macOS) or `/etc/hivehouse/delegate.d/<uid>` (Linux): the
  user's own root-owned delegate file, one for each user and the only record that gates bypass; hivehouse never writes it.
- No MCP config is written for away sessions. Earlier versions wrote `.hivehouse/team/<agent>/away-mcp.json`,
  `.hivehouse-hub/away-mcp.json` and `.hivehouse-hub/panes/<project>-mcp.json` (they may hold server secrets); the next
  start, registration or `hh-hub away` removes a stale one.

## After a restart

A restart of the machine or of tmux takes the team's panes with it. `hh-context --all` then marks each session
"(not running)", keeping its last level. The orchestrator registers itself again with `hh-spawn --self --agent
orchestrator`, then runs `hh-spawn --respawn <agent>` for each agent so marked: the agent starts again from its own
record (model, effort, permission mode, worktree and branch from `team.json`, role and rules from
`.hivehouse/team/<agent>/`) and is sent back to its handoff. A running agent, one whose state cannot be told, and the
orchestrator itself are never respawned. An agent recorded in bypass is refused (exit 4) once away has ended: add
`--mode <a stricter mode>` (the owner's `permission_mode_local`). `--resume` brings the agent back in its own recorded
conversation instead of from its handoff, when no live Claude already holds that conversation.
A respawn uses the tmux server the agent was recorded on (`socket` in `team.json`), whatever server the caller's own `HH_TMUX_SOCKET` names. When the record holds no socket, the caller's server is used. When it holds a socket that is not an absolute path to an existing socket, it says so and uses the caller's server.

An agent the orchestrator has ended for good is taken off the team with `hh-spawn --close <agent>`: its record leaves `team.json`, the pane
registry and the manifest, so nothing lists it as "(not running)" again; its worktree, branch and handoff stay. It is refused while the
agent's pane is live (end the agent first), for a record that proves nothing, for the orchestrator and for a name that is not on the team.

With a hub, `hh-hub status` shows which orchestrators a restart stopped; `hh-hub wake <project>` (or the screen's Resume)
resumes each one's own conversation in tmux and tells it to do the above.
