// The hub's screen and guard (hooks/hub.tsx) in the hub's own session. Run with `claude plugin test <plugin folder>`.
// hm-hub itself is stood in for beneath the plugin: its answers are the shapes tests/test_hub.sh pins.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const ROOT = '/work'
const NOW = Date.parse('2026-10-05T12:00:00Z')
const STATUS = {
  hub: { root: ROOT, name: 'hub' },
  projects: [
    {
      name: 'app',
      home: `${ROOT}/back`,
      repos: [
        { folder: 'back', kind: 'repo', branch: 'main', changed: 0 },
        { folder: 'site', kind: 'folder' },
      ],
      orchestrator: { state: 'stopped', question: false, name: 'app-orchestrator', session_id: 'sess-1', context: 51, context_assumed: false },
      agents: [
        { name: 'impl', state: 'stopped', question: false },
        { name: 'rev', state: 'running', question: true },
        // hm-spawn --respawn refuses an agent whose state cannot be told: it is no session Resume brings back
        { name: 'odd', state: 'unknown', question: false },
      ],
      open_tasks: 2,
    },
    { name: 'two', home: `${ROOT}/solo`, repos: [{ folder: 'solo', kind: 'repo', branch: 'main', changed: 3 }], orchestrator: { state: 'none', question: false }, agents: [], open_tasks: 0 },
    {
      name: 'tri',
      home: '/elsewhere/tri',
      repos: [{ folder: '/elsewhere/tri', kind: 'repo', branch: 'main', changed: 0 }],
      orchestrator: { state: 'unregistered', question: false, name: 'tri-orchestrator', pid: 4242, pane: '%9' },
      agents: [],
      open_tasks: 1,
    },
    {
      name: 'four',
      home: `${ROOT}/four`,
      repos: [{ folder: 'four', kind: 'repo', branch: 'main', changed: 0 }],
      orchestrator: { state: 'none', question: false, starting: { pane: '%12', kind: 'start', at: '2026-10-05T11:59:00Z', typed: false, sending: false, question: true, task: 'four-1' } },
      agents: [],
      open_tasks: 1,
    },
    {
      // a start whose line is still on the way: coming up, nothing for the owner to do
      name: 'five',
      home: `${ROOT}/five`,
      repos: [{ folder: 'five', kind: 'repo', branch: 'main', changed: 0 }],
      orchestrator: { state: 'none', question: false, starting: { pane: '%14', kind: 'start', at: '2026-10-05T11:59:50Z', typed: false, sending: true, question: false, task: 'five-1' } },
      agents: [],
      open_tasks: 1,
    },
  ],
}
const PROJECTS = {
  projects: [
    { name: 'app', home: 'back', repos: ['back', 'site'] },
    { name: 'tri', home: '/elsewhere/tri', repos: ['/elsewhere/tri'] },
  ],
}
const TASKS = [
  { id: 'app-1', project: 'app', asked: '2026-10-05T11:00:00Z', state: 'plan', updated: '2026-10-05T11:58:00Z', last_note: null, needs_owner: true },
  { id: 'app-2', project: 'app', asked: '2026-10-05T11:10:00Z', state: 'handed', updated: '2026-10-05T11:20:00Z', last_note: null, needs_owner: false },
  { id: 'app-3', project: 'app', asked: '2026-10-05T11:15:00Z', state: 'overnight', updated: '2026-10-05T11:30:00Z', last_note: null, needs_owner: false },
  { id: 'app-4', project: 'app', asked: '2026-10-05T11:16:00Z', state: 'cleanup', updated: '2026-10-05T11:31:00Z', last_note: null, needs_owner: false },
]
const PANE = {
  plugin: 'hivemind',
  component: 'Pane',
  requestId: 'hivemind-hub',
  props: { title: 'Hub', isFocused: true, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 80 }, view: {} },
} as const

// The plugin's skills, whose names Claude Code refuses to a command the plugin registers (it refused /hub for /hivemind:hub)
const SKILLS = ['bubble-review', 'cleanup', 'doc-updater', 'gate', 'handoff', 'hub', 'overnight', 'review-plan', 'start']
const ran = (exitCode: number, stdout: string, stderr = '') => ({ value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false } })

// The hub's folder holds .hivemind-hub/; every other path is itself, except one record that is a link into a project.
// opened: the panes asked for; commands: the names registered, refused as Claude Code refuses them (all of them when
// refuseAll is set).
// shown: whether Claude Code lists the screen as open and shown (its own record of the plugin's panes). session: what
// Claude Code records of this session (hm-hub naming) and how many turns it has had; slash: the slash commands run.
type Session = { turns: number; naming?: { found: boolean; name: string; source: string; free: string } }
function world(on: On, runs: string[][], opened: string[] = [], commands: string[] = [], refuseAll = false, shown = { now: true },
  session: Session = { turns: 3 }, slash: string[][] = []) {
  on('session.turns', async () => ({ value: session.turns }))
  on('session.id', async () => ({ value: 'sess-hub' }))
  on('command.run', async (_$, e) => {
    slash.push([e.command, e.args ?? ''])
    return { text: '' } as never
  })
  on('session.cwd', async () => ({ value: ROOT }))
  on('fs.stat', async (_$, e) => {
    if (e.path === `${ROOT}/.hivemind-hub`) return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }
    if (e.path === `${ROOT}/.hivemind-hub/memory/link.md`) return { value: { kind: 'file', size: 0, mtimeMs: 0, isLink: true, realPath: `${ROOT}/back/src/a.ts` } }
    if (e.path.endsWith('/new.md')) return { deny: 'ENOENT: no such file or directory' }
    return { value: { kind: 'file', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }
  })
  on('fs.read', async (_$, e) => (e.path === `${ROOT}/.hivemind-hub/projects.json` ? { value: JSON.stringify(PROJECTS) } : { deny: 'ENOENT' }))
  on('process.run', async (_$, e) => {
    runs.push([...e.argv])
    const sub = e.argv[1]
    if (sub === 'status') return ran(0, JSON.stringify(STATUS))
    if (sub === 'tasks') return ran(0, JSON.stringify(TASKS))
    if (sub === 'wake' || sub === 'continue') return ran(0, '%7\n')
    if (sub === 'naming' && session.naming) return ran(0, JSON.stringify(session.naming))
    return ran(64, '', 'hivemind: usage')
  })
  on('tool.call', async () => ({ result: 'ran' }) as never)
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('command.register', async (_$, e) => {
    if (refuseAll || SKILLS.includes(e.name)) return { deny: `"/${e.name}" refused: it is the plugin's /hivemind:${e.name}` }
    commands.push(e.name)
    return { value: { command: e.name } }
  })
  on('ui.open', async (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.panes', async () => ({ value: shown.now ? [{ id: 'hivemind-hub', title: 'Hub', isShown: true, isFocused: false, isPlaced: true }] : [] }))
  on('ui.toast', async () => ({ value: undefined }))
}

test('the hub keeps off the projects, and off nothing else', async ($, on) => {
  const runs: string[][] = []
  world(on, runs)
  const edit = (file_path: string) => $.tool.call({ tool: 'Edit', tool_use_id: 't', file_path, old_string: 'a', new_string: 'b' } as never)
  expect((await edit(`${ROOT}/back/src/a.ts`)).deny).toContain('the hub never changes a project')
  expect((await edit(`${ROOT}/.hivemind-hub/memory/app.md`)).deny).toBeUndefined()
  expect((await edit(`${ROOT}/.hivemind-hub/memory/link.md`)).deny).toContain('the hub never changes a project')
  const write = (file_path: string) => $.tool.call({ tool: 'Write', tool_use_id: 't', file_path, content: 'x' } as never)
  expect((await write(`${ROOT}/.hivemind-hub/memory/new.md`)).deny).toBeUndefined()
  expect((await write(`${ROOT}/back/new.md`)).deny).toContain('the hub never changes a project')
  // anything else in the work folder, and a project's folder outside it
  expect((await write(`${ROOT}/notes.txt`)).deny).toContain('the hub never changes a project')
  expect((await write('/elsewhere/tri/a.ts')).deny).toContain('the hub never changes a project')
  // Claude Code's own memory and plans, and scratch files, are the session's, not a project's
  expect((await write('/home/u/.claude/projects/-work/memory/MEMORY.md')).deny).toBeUndefined()
  expect((await write('/tmp/scratch/notes.md')).deny).toBeUndefined()
  const nb = (notebook_path: string) => $.tool.call({ tool: 'NotebookEdit', tool_use_id: 't', notebook_path, new_source: 'x' } as never)
  expect((await nb(`${ROOT}/back/n.ipynb`)).deny).toContain('the hub never changes a project')
  const bash = (command: string) => $.tool.call({ tool: 'Bash', tool_use_id: 't', command } as never)
  expect((await bash('git -C back commit -m x')).deny).toContain('changes a repository')
  expect((await bash('cd back && git push origin main')).deny).toContain('changes a repository')
  expect((await bash('git -C back status --short')).deny).toBeUndefined()
  expect((await bash('hm-hub status')).deny).toBeUndefined()
  // the owner's own words, carried word for word, are never read as a command
  expect((await bash("hm-hub task app <<'EOF'\nafter git pull on main, fix the totals\ngit push when done\nEOF")).deny).toBeUndefined()
  expect((await bash('hm-hub log app-1 done --note "landed, git push done"')).deny).toBeUndefined()
  expect((await bash("hm-hub log app-1 note --note 'run git commit -m x first'")).deny).toBeUndefined()
  expect((await bash("hm-hub task app <<'EOF'\nx\nEOF\ngit push origin main")).deny).toContain('changes a repository')
})

test('the screen: what needs the owner first, then each project, and Resume wakes a stopped orchestrator', async ($, on) => {
  const runs: string[][] = []
  const opened: string[] = []
  const commands: string[] = []
  const clock = mock.clock(on, { now: NOW })
  mock.env(on, { HOME: '/home' })
  world(on, runs, opened, commands)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(runs.map(r => r[1])).toEqual(expect.arrayContaining(['status', 'tasks']))
  expect(commands).toEqual(['hub-screen'])
  expect(opened).toEqual(['hivemind-hub'])

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: 'NEEDS YOU' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /plan to approve/ })).toBeDefined()
  // a question nobody watches: an agent's, and a start stopped at one
  // (each line is the project or agent in bold, then what it waits for)
  expect(await ui.find({ type: 'Text', text: 'app · rev' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^ +a question on its screen$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /a question on the screen of pane %12/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'APP' })).toBeDefined()
  // an overnight run and a cleanup the hub started are shown on the project's task row, and wait on nobody
  expect(await ui.find({ type: 'Text', text: /1 overnight run · 1 cleanup/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /stopped/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /51%/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /no team/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /not registered/ })).toBeDefined()
  // the orchestrator and the one stopped agent come back; an agent that cannot be told about is not counted
  expect((await ui.find({ key: 'resume-app' }))?.text).toContain('Resume · 2 sessions')
  expect(await ui.find({ key: 'resume-two' })).toBeUndefined()
  expect(await ui.find({ key: 'resume-tri' })).toBeUndefined()
  // a start still sending its line is coming up: no Continue, nothing waiting on the owner
  expect(await ui.find({ key: 'continue-five' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /coming up/ })).toBeDefined()

  await ui.press({ key: 'resume-app' })
  const wake = runs.find(r => r[1] === 'wake')
  expect(wake?.slice(1)).toEqual(['wake', 'app', '--mode', 'auto'])
  expect(wake?.[0]).toMatch(/\/bin\/hm-hub$/)

  await ui.press({ key: 'continue-four' })
  expect(runs.find(r => r[1] === 'continue')?.slice(1)).toEqual(['continue', 'four'])
  await ui.unmount()
})

test('the screen reads hm-hub only while it is open, and once per tick', async ($, on) => {
  const runs: string[][] = []
  const shown = { now: true }
  const clock = mock.clock(on, { now: NOW })
  world(on, runs, [], [], false, shown)
  const reads = () => runs.filter(r => r[1] === 'status').length
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true }) // a second start keeps one poller
  await clock.settle()
  const first = reads()
  await clock.advance(20_000)
  expect(reads()).toBe(first + 1)
  shown.now = false // the owner closed it
  await clock.advance(60_000)
  expect(reads()).toBe(first + 1)
  await $.command.run({ command: 'hub-screen', args: '', origin: 'person' } as never)
  shown.now = true
  await clock.settle()
  const reopened = reads()
  expect(reopened).toBe(first + 2)
  await clock.advance(20_000)
  expect(reads()).toBe(reopened + 1)
})

test('a command Claude Code refuses does not keep the screen shut', async ($, on) => {
  const runs: string[][] = []
  const opened: string[] = []
  const clock = mock.clock(on, { now: NOW })
  world(on, runs, opened, [], true)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(runs.map(r => r[1])).toEqual(expect.arrayContaining(['status', 'tasks']))
  expect(opened).toEqual(['hivemind-hub'])
})

const UNNAMED = { found: true, name: 'Read the docs', source: 'auto', free: 'hub' }

test('a plain claude in the hub folder names itself and opens the hub', async ($, on) => {
  const ran: string[][] = []
  const clock = mock.clock(on, { now: NOW })
  world(on, [], [], [], false, { now: true }, { turns: 0, naming: UNNAMED }, ran)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(ran).toEqual([['rename', 'hub'], ['hivemind:hub', '']])
})

// each test's world is its own: hooks a test registers stay for the rest of that test
const leftAlone = (why: string, session: Session, isInteractive = true) =>
  test(`a session ${why} is left as it is`, async ($, on) => {
    const ran: string[][] = []
    const clock = mock.clock(on, { now: NOW })
    world(on, [], [], [], false, { now: true }, session, ran)
    await $.session.start({ cwd: ROOT, surface: isInteractive ? 'terminal' : null, isInteractive })
    await clock.settle()
    expect(ran).toEqual([])
  })
leftAlone('the owner named', { turns: 0, naming: { ...UNNAMED, name: 'hub', source: 'user' } })
leftAlone('resumed or reloaded (it has had turns)', { turns: 4, naming: UNNAMED })
leftAlone('Claude Code keeps no record of', { turns: 0, naming: { ...UNNAMED, found: false } })
leftAlone('nobody is at the prompt of (claude -p, the SDK)', { turns: 0, naming: UNNAMED }, false)

test('the setting turns the naming off', { options: { hub_auto_start: false } }, async ($, on) => {
  const ran: string[][] = []
  const clock = mock.clock(on, { now: NOW })
  world(on, [], [], [], false, { now: true }, { turns: 0, naming: UNNAMED }, ran)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(ran).toEqual([])
})
