// What the hub's screen draws, read from `hh-hub status --json` and `hh-hub tasks --json` (bin/hh-hub owns every field).

// running, stopped, unknown (its process is alive but tmux cannot vouch for it), none (no team recorded), unregistered (a
// session running outside hivehouse, found in Claude Code's own session records), resumable (nothing recorded, but a transcript of
// its conversation under a team root: hh-hub wake resumes it by id)
export type HubOrchestratorState = 'running' | 'stopped' | 'unknown' | 'none' | 'unregistered' | 'resumable'
// as above, and unrecorded: on the team with no identity, so nothing proves either way
export type HubAgentState = 'running' | 'stopped' | 'unknown' | 'unrecorded'

// question: a dialog waits on its screen, which nobody watches
// context_unknown: its tokens (context_tokens) exceed a window that was only assumed, so there is no percent
export type HubAgent = { name: string; state: HubAgentState; question?: boolean; context?: number; context_assumed?: boolean; context_unknown?: boolean; context_tokens?: number; worktree?: string; ref?: string }

export type HubOrchestrator = {
  state: HubOrchestratorState
  question?: boolean
  name?: string
  // an unregistered session's process and tmux pane
  pid?: number
  pane?: string
  session_id?: string
  context?: number
  context_assumed?: boolean
  context_unknown?: boolean
  context_tokens?: number
  // a session this hub started (wake, start) that has not registered yet. typed: its first line was sent; sending: an hh-hub
  // is still waiting to send it (coming up); neither: it stopped, waiting on the owner (hh-hub continue sends it);
  // question: a dialog waits on its screen
  starting?: { pane: string; kind: string; at: string; typed?: boolean; sending?: boolean; question?: boolean; task?: string }
}

export type HubFolder = { folder: string; kind: string; branch?: string; changed?: number }

export type HubProject = {
  name: string
  home: string
  repos: HubFolder[]
  orchestrator: HubOrchestrator
  agents: HubAgent[]
  open_tasks: number
}

export type HubTask = {
  id: string
  project: string
  asked: string
  state: string
  updated: string
  last_note: string | null
  needs_owner: boolean
  // what the hub decided for the owner on this task while they were away, each with its one-line reason
  decisions?: { at: string; reason: string }[]
}

// A dialog on a session's screen, as `hh-hub dialog` reads it. offered: the hub may answer with this option (one that needs
// the owner's own text is not); saves_rule: choosing it saves a permission rule; fingerprint: the screen the owner was
// shown, which `hh-hub answer` checks before it sends a key.
export type HubDialogOption = { n: number; label: string; detail: string; offered: boolean; saves_rule: boolean }
export type HubDialog = { kind: 'numbered' | 'menu' | 'none'; text: string; options: HubDialogOption[]; cursor: number | null; esc: boolean; fingerprint: string }

export type HubView = {
  root: string
  hubName: string
  projects: HubProject[]
  tasks: HubTask[]
  // by session: "<project>" for its orchestrator, "<project>/<agent>" for an agent
  dialogs: Record<string, HubDialog>
  // delegate mode: the owner is away until this epoch (seconds), since this time; null in relay mode
  away: { until: number; since?: string } | null
  // a delegate file exists at this user's path but is refused: the first reason (hh-hub status --json: hub.away_refused); null when none
  awayRefused: string | null
  // the last away period, which stays in status after it ends: what the hub decided in it is shown until the owner has seen it
  lastAway: { since: string; until: number } | null
  updatedAt: number
  error: string
}

declare module 'claude-code' {
  interface PluginState {
    hivehouse: { hubView: HubView; hubResuming: string; hubSeenAway: string }
  }
}
