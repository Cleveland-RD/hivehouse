import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { HubAgent, HubProject, HubTask, HubView } from '../types'

// The owner's hub (bin/hm-hub, skills/hub): in the session started in the hub's own folder, and only there, a screen of
// what waits on the owner and of every project's orchestrator, and a guard that keeps the hub off the projects' files.
// Everything shown is read from hm-hub; the only things done here are the Resume and Continue presses, which run
// `hm-hub wake` and `hm-hub continue`.
const PANE = 'hivemind-hub'
// The command that opens the screen. Never a skill's name: Claude Code refuses a command named as one of the plugin's own
// skills (/hub is the skill, /hivemind:hub), and tests/test_hub_screen.sh holds it to that.
const COMMAND = 'hub-screen'
const EVERY_MS = 20_000
const WAKE_TIMEOUT_MS = 150_000 // hm-hub waits up to 90 s for a started session to be idle

const EMPTY: HubView = { root: '', hubName: '', projects: [], tasks: [], updatedAt: 0, error: '' }
const view = atom({ plugin: 'hivemind', key: 'hubView' } as const, EMPTY)
// the project a press is acting on, one at a time
const acting = atom({ plugin: 'hivemind', key: 'hubResuming' } as const, '')

// The session is the hub when its own folder holds .hivemind-hub/ (a folder, not a link): hm-session-hook's rule.
let hubRootOnce: Promise<string | null> | null = null
function hubRoot($: EngineInterface): Promise<string | null> {
  hubRootOnce ??= (async () => {
    try {
      const cwd = await $.session.cwd()
      const st = await $.fs.stat(`${cwd}/.hivemind-hub`)
      return st.kind === 'dir' && !st.isLink ? cwd : null
    } catch {
      return null
    }
  })()
  return hubRootOnce
}

const hmHub = ($: EngineInterface) => `${$.plugin.root}/bin/hm-hub`

async function refresh($: EngineInterface): Promise<void> {
  const root = await hubRoot($)
  if (!root) return
  try {
    const [status, tasks] = await Promise.all([
      $.process.run([hmHub($), 'status', '--json'], { cwd: root, timeoutMs: 30_000 }),
      $.process.run([hmHub($), 'tasks', '--json'], { cwd: root, timeoutMs: 30_000 }),
    ])
    if (status.exitCode !== 0) throw new Error(lastLine(status.stderr) || `hm-hub status exited ${status.exitCode}`)
    const s = JSON.parse(status.stdout) as { hub?: { root?: string; name?: string }; projects?: HubProject[] }
    const t = tasks.exitCode === 0 ? (JSON.parse(tasks.stdout) as HubTask[]) : []
    const next: HubView = {
      root: s.hub?.root ?? root,
      hubName: s.hub?.name ?? '',
      projects: s.projects ?? [],
      tasks: t,
      updatedAt: await $.clock.now(),
      // the projects still draw when only the ledger could not be read, and the screen says so
      error: tasks.exitCode === 0 ? '' : `tasks not read: ${lastLine(tasks.stderr) || `hm-hub tasks exited ${tasks.exitCode}`}`,
    }
    await update($, view, () => next)
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err)
    await update($, view, v => ({ ...(v ?? EMPTY), error, updatedAt: v?.updatedAt ?? 0 }))
  }
}

// One poller per module, which reads hm-hub only while the screen is open and shown (Claude Code's own record of this
// plugin's panes, so a pane the owner closed or tabbed away from costs nothing until it is back).
let poller: { cancel: () => void } | null = null
function startPolling($: EngineInterface): void {
  if (poller) return
  poller = $.clock.every(EVERY_MS, () => {
    void tick($)
  })
}
async function tick($: EngineInterface): Promise<void> {
  if ((await $.ui.panes()).some(pane => pane.id === PANE && pane.isShown)) await refresh($)
}

function lastLine(text: string): string {
  return (text.trim().split('\n').pop() ?? '').replace(/^hivemind: /, '')
}

// A press is the owner's own word for that one action: Resume wakes a stopped orchestrator (hm-hub wake), Continue sends
// a started one its first line once the owner has answered the question on its screen (hm-hub continue).
async function act($: EngineInterface, project: string, args: string[], done: string): Promise<void> {
  const root = await hubRoot($)
  if (!root || (await read($, acting))) return
  await update($, acting, () => project)
  try {
    const r = await $.process.run([hmHub($), ...args], { cwd: root, timeoutMs: WAKE_TIMEOUT_MS })
    $.ui.toast(r.exitCode === 0 ? `${project}: ${done} (pane ${r.stdout.trim()})` : `${project}: ${lastLine(r.stderr)}`)
  } finally {
    await update($, acting, () => '')
    await refresh($)
  }
}

// ---- the guard ------------------------------------------------------------------------------------------------------
// The hub changes no project: in the hub's session an edit inside its work folder (apart from its own records) or inside
// any project's folder is refused. A path is judged by where it really is (links and `..` resolved); a file that does
// not exist yet, by its folder. Everything else (Claude Code's own memory and plans, scratch files) is the session's.
async function realPath($: EngineInterface, path: string): Promise<string | null> {
  try {
    return (await $.fs.stat(path, { resolve: true })).realPath ?? null
  } catch {
    const cut = path.lastIndexOf('/')
    if (cut <= 0) return null
    const dir = await realPath($, path.slice(0, cut))
    return dir === null ? null : `${dir}/${path.slice(cut + 1)}`
  }
}

async function projectFolders($: EngineInterface, root: string): Promise<string[]> {
  try {
    const text = await $.fs.read(`${root}/.hivemind-hub/projects.json`)
    const list = (JSON.parse(typeof text === 'string' ? text : '{}') as { projects?: { home?: string; repos?: string[] }[] }).projects ?? []
    return list.flatMap(p => [p.home ?? '', ...(p.repos ?? [])]).filter(f => f !== '').map(f => (f.startsWith('/') ? f : `${root}/${f}`))
  } catch {
    return []
  }
}

const inside = (path: string, dir: string | null) => dir !== null && (path === dir || path.startsWith(`${dir}/`))

const KEEP_OFF = 'the hub never changes a project: hand this to the project\'s orchestrator'

// Why an edit of this path is refused in the hub, or null when it may go on.
async function editRefusal($: EngineInterface, path: string): Promise<string | null> {
  const root = await hubRoot($)
  if (!root) return null
  const abs = path.startsWith('/') ? path : `${root}/${path}`
  const real = (await realPath($, abs)) ?? abs
  if (inside(real, await realPath($, `${root}/.hivemind-hub`))) return null
  const folders = await Promise.all([root, ...(await projectFolders($, root))].map(f => realPath($, f)))
  return folders.some(f => inside(real, f)) ? `${KEEP_OFF} (${path})` : null
}

// git commands that change a repository; read-only ones (status, log, diff, show) pass. Best effort: a shell can always
// spell a command another way, which is why the skill says so too.
const GIT_WRITES =
  /(^|[;&|(`]|\s)git(\s+-C\s+\S+)?\s+(commit|push|merge|rebase|reset|checkout|switch|restore|stash|cherry-pick|revert|tag|am|apply|clean|rm|mv|add|worktree|pull|branch\s+-[dDmMf])\b/

// A command with the words it only carries taken out: a heredoc's body and quoted strings are the owner's text, passed
// word for word (a task, a note), never a command the shell runs.
function commandsOnly(command: string): string {
  const kept: string[] = []
  let until = ''
  for (const line of command.split('\n')) {
    if (until) {
      if (line.trim() === until) until = ''
      continue
    }
    const opens = /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/.exec(line)
    if (opens) until = opens[2] ?? ''
    kept.push(line)
  }
  return kept.join('\n').replace(/'[^']*'/g, "''").replace(/"(?:[^"\\]|\\.)*"/g, '""')
}

export const register: Register = (on, options) => {
  // the mode orchestrators run in, as the hub's own sessions do: cross-session messages wait for approval across modes
  const mode = typeof options.permission_mode_local === 'string' ? options.permission_mode_local : ''
  // the level at which hivemind rotates a session: a level at or above it is drawn as a warning
  const rotateAt = typeof options.rotate_at_percent === 'number' ? options.rotate_at_percent : 50

  // A guard that fails lets the call go on (its .catch): it is best effort, and a broken guard must not stop the work.
  on('tool.call', { tool: 'Edit' }, async ($, e, next) => {
    const deny = await editRefusal($, e.file_path)
    return deny ? { deny } : next(e)
  }).catch(($, e, next) => next(e))
  on('tool.call', { tool: 'Write' }, async ($, e, next) => {
    const deny = await editRefusal($, e.file_path)
    return deny ? { deny } : next(e)
  }).catch(($, e, next) => next(e))
  on('tool.call', { tool: 'NotebookEdit' }, async ($, e, next) => {
    const deny = await editRefusal($, e.notebook_path)
    return deny ? { deny } : next(e)
  }).catch(($, e, next) => next(e))
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const root = await hubRoot($)
    if (!root || !GIT_WRITES.test(commandsOnly(e.command))) return next(e)
    return { deny: `${KEEP_OFF} (a git command that changes a repository)` }
  }).catch(($, e, next) => next(e))

  // ---- the screen ---------------------------------------------------------------------------------------------------
  on('session.start', async ($, e, next) => {
    if (await hubRoot($)) {
      // a refused command must not keep the screen shut: it opens anyway, and says why the command is missing
      try {
        await $.command.register({ name: COMMAND, description: 'Show the hub: what waits on you, and every project' })
      } catch (err) {
        $.ui.toast(`hub screen: /${COMMAND} is not available (${err instanceof Error ? err.message : String(err)})`)
      }
      void refresh($)
      startPolling($)
      void $.ui.open({ id: PANE, title: 'Hub' })
    }
    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    void refresh($)
    startPolling($)
    await $.ui.open({ id: PANE, title: 'Hub' })
    return { text: 'Hub screen opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const v = { ...EMPTY, ...((await read($, view)) ?? {}) } // a hot reload can hand back an older shape
    const busy = (await read($, acting)) ?? ''
    const now = await $.clock.now()
    const body = Math.max(36, e.props.bodyColumns ?? 60)
    const inner = body - 2
    const home = (await $.env.get('HOME')) ?? ''
    const where = home && v.root.startsWith(home) ? `~${v.root.slice(home.length)}` : v.root
    const rule = <Text color="gray">{'─'.repeat(inner)}</Text>
    const resumeArgs = (p: string) => ['wake', p, ...(mode ? ['--mode', mode] : [])]

    // What waits on the owner: tasks hm-hub marks so, and questions on screens nobody watches.
    type Need = { key: string; glyph: string; color: string; who: string; words: string; when: string; action?: JSX.Element }
    const needs: Need[] = []
    if (v.updatedAt && !v.hubName) {
      needs.push({ key: 'hub', glyph: '!', color: 'red', who: 'hub', words: 'has not recorded its session, so nobody can reply to it', when: '' })
    }
    for (const t of v.tasks.filter(t => t.needs_owner)) {
      const w = waitLook(t.state)
      needs.push({ key: t.id, glyph: w.glyph, color: w.color, who: t.id, words: w.words, when: ago(t.updated, now) })
    }
    for (const p of v.projects) {
      const o = p.orchestrator ?? { state: 'none' }
      if (o.question) needs.push({ key: `q-${p.name}`, glyph: '?', color: 'yellow', who: p.name, words: 'its orchestrator has a question on its screen', when: '' })
      for (const a of (p.agents ?? []).filter(a => a.question)) {
        needs.push({ key: `q-${p.name}-${a.name}`, glyph: '?', color: 'yellow', who: `${p.name} · ${a.name}`, words: 'a question on its screen', when: '' })
      }
      const s = o.starting
      if (s && !s.typed) {
        needs.push({
          key: `s-${p.name}`,
          glyph: '?',
          color: 'yellow',
          who: p.name,
          words: s.question ? `a question on the screen of pane ${s.pane}: answer it, then Continue` : `waiting in pane ${s.pane} for its first line`,
          when: ago(s.at, now),
          action:
            busy === p.name ? (
              <Text color="cyan">continuing…</Text>
            ) : (
              <Button key={`continue-${p.name}`} onPress={() => void act($, p.name, ['continue', p.name], 'its first line was sent')}>
                Continue
              </Button>
            ),
        })
      }
    }

    const row = (label: string, ...lines: JSX.Element[]) => (
      <Box flexDirection="row" paddingLeft={1}>
        <Box width={14} flexShrink={0}>
          <Text color="gray">{label}</Text>
        </Box>
        <Box flexDirection="column" flexShrink={1}>
          {lines}
        </Box>
      </Box>
    )

    const card = (p: HubProject) => {
      const look = orchestratorLook(p)
      const o = p.orchestrator ?? { state: 'none' }
      const agents = p.agents ?? []
      const up = agents.filter(a => a.state === 'running').length
      const away = agents.filter(a => a.state !== 'running')
      // what Resume brings back: the orchestrator, and each agent hm-spawn --respawn takes (one proven stopped)
      const back = 1 + agents.filter(a => a.state === 'stopped').length
      const doneToday = v.tasks.filter(t => t.project === p.name && t.state === 'done' && sameDay(t.updated, now)).length
      const canResume = o.state === 'stopped' && Boolean(o.session_id) && !o.starting
      return (
        <Box key={`p-${p.name}`} flexDirection="column" marginTop={1}>
          <Box flexDirection="row" justifyContent="space-between">
            <Text bold color="white">
              {p.name.toUpperCase()}
            </Text>
            <Text color={look.color}>{`${look.dot} ${look.word}`}</Text>
          </Box>
          {row(
            'orchestrator',
            <Box flexDirection="row">
              <Text color="white">{o.name ?? (o.state === 'none' ? 'none yet' : '?')}</Text>
              {o.state === 'unregistered' && o.pane ? <Text color="gray">{`  pane ${o.pane}`}</Text> : null}
              {typeof o.context === 'number' ? (
                <Text color={o.context_assumed ? 'gray' : o.context >= rotateAt ? 'yellow' : 'green'}>{`  ${o.context}%`}</Text>
              ) : null}
            </Box>,
          )}
          {row(
            'agents',
            agents.length === 0 ? (
              <Text color="gray">none</Text>
            ) : (
              <Box flexDirection="row">
                {agents.map(a => (
                  // a space after each: two hollow dots side by side read as one wide sign
                  <Text key={`a-${p.name}-${a.name}`} color={agentColor(a)}>
                    {`${a.state === 'running' ? '●' : a.state === 'stopped' ? '○' : '?'} `}
                  </Text>
                ))}
                <Text color="white">{` ${up} of ${agents.length}`}</Text>
              </Box>
            ),
            ...(away.length > 0
              ? [<Text key={`away-${p.name}`} color="yellow">{away.map(a => `${a.name} ${a.state}`).join(', ')}</Text>]
              : []),
          )}
          {row(
            'tasks',
            <Text color="white">{`${p.open_tasks ?? 0} open${doneToday > 0 ? ` · ${doneToday} done today` : ''}`}</Text>,
          )}
          {row(
            'folders',
            ...(p.repos ?? []).map(f => (
              <Text key={`f-${p.name}-${f.folder}`} color="white" wrap="truncate-end">
                {f.folder}
                {f.changed ? `  ${f.changed} changed` : ''}
              </Text>
            )),
          )}
          {busy === p.name && canResume ? (
            <Box paddingLeft={15}>
              <Text color="cyan">resuming…</Text>
            </Box>
          ) : canResume ? (
            <Box paddingLeft={15}>
              <Button
                key={`resume-${p.name}`}
                variant="primary"
                onPress={() => void act($, p.name, resumeArgs(p.name), 'its orchestrator is coming up; it reports back when its team is up')}
              >
                {`Resume · ${back} session${back === 1 ? '' : 's'}`}
              </Button>
            </Box>
          ) : null}
        </Box>
      )
    }

    // the engine's pane background is grey in an ANSI theme: paint the whole body in the terminal's own black
    return (
      <Box flexDirection="column" backgroundColor="black" width={body} minHeight={e.viewport?.rows ?? 0} paddingX={1}>
        {/* the folder gives way from its left, so the time always shows */}
        <Box flexDirection="row" justifyContent="space-between">
          <Box flexDirection="row" flexShrink={1}>
            <Text bold color="white">
              HUB
            </Text>
            <Text color="gray" wrap="truncate-start">
              {where ? `  ·  ${where}` : ''}
            </Text>
          </Box>
          <Box flexShrink={0} paddingLeft={2}>
            <Text color="gray">{v.updatedAt ? clock(v.updatedAt) : 'reading…'}</Text>
          </Box>
        </Box>
        {rule}
        {v.error ? <Text color="red">{v.error}</Text> : null}
        {needs.length > 0 ? (
          <Box flexDirection="column" marginTop={1}>
            <Text bold color="magenta">
              NEEDS YOU
            </Text>
            {needs.map(n => (
              <Box key={`n-${n.key}`} flexDirection="column" paddingLeft={1}>
                <Box flexDirection="row" justifyContent="space-between">
                  <Box flexDirection="row" flexShrink={1}>
                    <Text color={n.color}>{`${n.glyph} `}</Text>
                    <Text bold color="white">
                      {n.who}
                    </Text>
                    <Text color="white" wrap="wrap">{`  ${n.words}`}</Text>
                  </Box>
                  <Text color="gray">{n.when}</Text>
                </Box>
                {n.action ? <Box paddingLeft={2}>{n.action}</Box> : null}
              </Box>
            ))}
          </Box>
        ) : null}
        {v.updatedAt && v.projects.length === 0 && !v.error ? (
          <Box marginTop={1}>
            <Text color="gray">No projects yet: tell the hub which folders make up a project.</Text>
          </Box>
        ) : null}
        {v.projects.map(card)}
        <Box marginTop={1}>{rule}</Box>
        <Box flexDirection="row" justifyContent="space-between">
          <Text color="gray">● running  ○ stopped  ◌ no team</Text>
          <Button key="refresh" plain hotkey="r" onPress={() => void refresh($)}>
            refresh
          </Button>
        </Box>
      </Box>
    )
  })
}

// ---- looks ------------------------------------------------------------------------------------------------------------
function orchestratorLook(p: HubProject): { dot: string; word: string; color: string } {
  const o = p.orchestrator ?? { state: 'none' }
  if (o.starting && o.state !== 'running') {
    return o.starting.typed ? { dot: '◐', word: 'coming up', color: 'cyan' } : { dot: '◐', word: 'waiting on you', color: 'magenta' }
  }
  const looks: Record<HubProject['orchestrator']['state'], { dot: string; word: string; color: string }> = {
    running: { dot: '●', word: 'running', color: 'green' },
    stopped: { dot: '○', word: 'stopped', color: 'yellow' },
    unknown: { dot: '?', word: 'cannot tell', color: 'red' },
    none: { dot: '◌', word: 'no team', color: 'gray' },
    unregistered: { dot: '◑', word: 'not registered', color: 'magenta' },
  }
  return looks[o.state] ?? looks.unknown
}

function agentColor(a: HubAgent): string {
  return a.state === 'running' ? 'green' : a.state === 'stopped' ? 'yellow' : 'red'
}

// What a waiting task asks of the owner. hm-hub decides which states wait (needs_owner); this only words them, and a
// state it does not know is shown by its own name.
function waitLook(state: string): { glyph: string; words: string; color: string } {
  const looks: Record<string, { glyph: string; words: string; color: string }> = {
    plan: { glyph: '▲', words: 'plan to approve', color: 'magenta' },
    question: { glyph: '?', words: 'question', color: 'yellow' },
    blocked: { glyph: '✖', words: 'blocked', color: 'red' },
  }
  return looks[state] ?? { glyph: '•', words: state, color: 'white' }
}

function clock(ms: number): string {
  return new Date(ms).toTimeString().slice(0, 5)
}

function sameDay(iso: string, now: number): boolean {
  return new Date(iso).toDateString() === new Date(now).toDateString()
}

function ago(iso: string, now: number): string {
  const s = Math.max(0, Math.round((now - Date.parse(iso)) / 1000))
  if (!Number.isFinite(s)) return ''
  if (s < 60) return 'now'
  if (s < 3600) return `${Math.floor(s / 60)}m`
  if (s < 86_400) return `${Math.floor(s / 3600)}h`
  return `${Math.floor(s / 86_400)}d`
}
