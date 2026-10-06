// What the hub's screen draws, read from `hm-hub status --json` and `hm-hub tasks --json` (bin/hm-hub owns every field).

// running, stopped, unknown (its process is alive but tmux cannot vouch for it), none (no team recorded)
export type HubOrchestratorState = 'running' | 'stopped' | 'unknown' | 'none'
// as above, and unrecorded: on the team with no identity, so nothing proves either way
export type HubAgentState = 'running' | 'stopped' | 'unknown' | 'unrecorded'

export type HubAgent = { name: string; state: HubAgentState; context?: number; context_assumed?: boolean }

export type HubOrchestrator = {
  state: HubOrchestratorState
  name?: string
  session_id?: string
  context?: number
  context_assumed?: boolean
  // a session this hub started (wake, start) that has not registered yet
  starting?: { pane: string; kind: string; at: string }
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

export type HubView = {
  root: string
  hubName: string
  projects: HubProject[]
  tasks: HubTask[]
  updatedAt: number
  error: string
}

declare module 'claude-code' {
  interface PluginState {
    hivemind: { hubView: HubView; hubResuming: string }
  }
}
