// What the hub's screen draws, read from `hm-hub status --json` and `hm-hub tasks --json` (bin/hm-hub owns every field).

// running, stopped, unknown (its process is alive but tmux cannot vouch for it), none (no team recorded), unregistered (a
// session running outside hivemind, found in Claude Code's own session records)
export type HubOrchestratorState = 'running' | 'stopped' | 'unknown' | 'none' | 'unregistered'
// as above, and unrecorded: on the team with no identity, so nothing proves either way
export type HubAgentState = 'running' | 'stopped' | 'unknown' | 'unrecorded'

// question: a dialog waits on its screen, which nobody watches
export type HubAgent = { name: string; state: HubAgentState; question?: boolean; context?: number; context_assumed?: boolean }

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
  // a session this hub started (wake, start) that has not registered yet. typed: its first line was sent; sending: an hm-hub
  // is still waiting to send it (coming up); neither: it stopped, waiting on the owner (hm-hub continue sends it);
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
}

// A dialog on a session's screen, as `hm-hub dialog` reads it. offered: the hub may answer with this option (one that needs
// the owner's own text is not); saves_rule: choosing it saves a permission rule; fingerprint: the screen the owner was
// shown, which `hm-hub answer` checks before it sends a key.
export type HubDialogOption = { n: number; label: string; detail: string; offered: boolean; saves_rule: boolean }
export type HubDialog = { kind: 'numbered' | 'menu' | 'none'; text: string; options: HubDialogOption[]; cursor: number | null; esc: boolean; fingerprint: string }

export type HubView = {
  root: string
  hubName: string
  projects: HubProject[]
  tasks: HubTask[]
  // by session: "<project>" for its orchestrator, "<project>/<agent>" for an agent
  dialogs: Record<string, HubDialog>
  updatedAt: number
  error: string
}

declare module 'claude-code' {
  interface PluginState {
    hivemind: { hubView: HubView; hubResuming: string }
  }
}
