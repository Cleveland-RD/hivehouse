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
      orchestrator: { state: 'stopped', name: 'app-orchestrator', session_id: 'sess-1', context: 51, context_assumed: false },
      agents: [
        { name: 'impl', state: 'stopped' },
        { name: 'rev', state: 'running' },
      ],
      open_tasks: 2,
    },
    { name: 'two', home: `${ROOT}/solo`, repos: [{ folder: 'solo', kind: 'repo', branch: 'main', changed: 3 }], orchestrator: { state: 'none' }, agents: [], open_tasks: 0 },
  ],
}
const TASKS = [
  { id: 'app-1', project: 'app', asked: '2026-10-05T11:00:00Z', state: 'plan', updated: '2026-10-05T11:58:00Z', last_note: null, needs_owner: true },
  { id: 'app-2', project: 'app', asked: '2026-10-05T11:10:00Z', state: 'handed', updated: '2026-10-05T11:20:00Z', last_note: null, needs_owner: false },
]
const PANE = {
  plugin: 'hivemind',
  component: 'Pane',
  requestId: 'hivemind-hub',
  props: { title: 'Hub', isFocused: true, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} },
} as const

// The hub's folder holds .hivemind-hub/; every other path is itself, except one record that is a link into a project.
function world(on: On, runs: string[][]) {
  on('session.cwd', async () => ({ value: ROOT }))
  on('fs.stat', async (_$, e) => {
    if (e.path === `${ROOT}/.hivemind-hub`) return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }
    if (e.path === `${ROOT}/.hivemind-hub/memory/link.md`) return { value: { kind: 'file', size: 0, mtimeMs: 0, isLink: true, realPath: `${ROOT}/back/src/a.ts` } }
    if (e.path.endsWith('/new.md')) return { deny: 'ENOENT: no such file or directory' }
    return { value: { kind: 'file', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }
  })
  on('process.run', async (_$, e) => {
    runs.push([...e.argv])
    const sub = e.argv[1]
    if (sub === 'status') return { value: { exitCode: 0, stdout: JSON.stringify(STATUS), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    if (sub === 'tasks') return { value: { exitCode: 0, stdout: JSON.stringify(TASKS), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    if (sub === 'wake') return { value: { exitCode: 0, stdout: '%7\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    return { value: { exitCode: 64, stdout: '', stderr: 'hivemind: usage', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('tool.call', async () => ({ result: 'ran' }) as never)
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('command.register', async (_$, e) => ({ value: { command: e.name } }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.toast', async () => ({ value: undefined }))
}

test('the hub keeps off the projects: edits outside its records and git writes are refused', async ($, on) => {
  const runs: string[][] = []
  world(on, runs)
  const edit = (file_path: string) => $.tool.call({ tool: 'Edit', tool_use_id: 't', file_path, old_string: 'a', new_string: 'b' } as never)
  expect((await edit(`${ROOT}/back/src/a.ts`)).deny).toContain('the hub never changes a project')
  expect((await edit(`${ROOT}/.hivemind-hub/memory/app.md`)).deny).toBeUndefined()
  expect((await edit(`${ROOT}/.hivemind-hub/memory/link.md`)).deny).toContain('the hub never changes a project')
  const write = (file_path: string) => $.tool.call({ tool: 'Write', tool_use_id: 't', file_path, content: 'x' } as never)
  expect((await write(`${ROOT}/.hivemind-hub/memory/new.md`)).deny).toBeUndefined()
  expect((await write(`${ROOT}/back/new.md`)).deny).toContain('the hub never changes a project')
  const nb = (notebook_path: string) => $.tool.call({ tool: 'NotebookEdit', tool_use_id: 't', notebook_path, new_source: 'x' } as never)
  expect((await nb(`${ROOT}/back/n.ipynb`)).deny).toContain('the hub never changes a project')
  const bash = (command: string) => $.tool.call({ tool: 'Bash', tool_use_id: 't', command } as never)
  expect((await bash('git -C back commit -m x')).deny).toContain('changes a repository')
  expect((await bash('cd back && git push origin main')).deny).toContain('changes a repository')
  expect((await bash('git -C back status --short')).deny).toBeUndefined()
  expect((await bash('hm-hub status')).deny).toBeUndefined()
})

test('the screen: what needs the owner first, then each project, and Resume wakes a stopped orchestrator', async ($, on) => {
  const runs: string[][] = []
  const clock = mock.clock(on, { now: NOW })
  mock.env(on, { HOME: '/home' })
  world(on, runs)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(runs.map(r => r[1])).toEqual(expect.arrayContaining(['status', 'tasks']))

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: 'NEEDS YOU' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /plan to approve/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'APP' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /stopped/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /51%/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /no team/ })).toBeDefined()
  // one stopped agent and the orchestrator: two sessions come back
  expect((await ui.find({ key: 'resume-app' }))?.text).toContain('Resume · 2 sessions')
  expect(await ui.find({ key: 'resume-two' })).toBeUndefined()

  await ui.press({ key: 'resume-app' })
  const wake = runs.find(r => r[1] === 'wake')
  expect(wake?.slice(1)).toEqual(['wake', 'app', '--model', 'opus'])
  expect(wake?.[0]).toMatch(/\/bin\/hm-hub$/)
  await ui.unmount()
})
