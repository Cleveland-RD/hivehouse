// Outside the hub's folder the hub module does nothing: no screen, no hm-hub call, and every edit and command passes.
// Run with `claude plugin test <plugin folder>` (each file runs in its own process, so the module starts fresh here).
import { expect, test } from 'claude-code/testing'

test('a session outside the hub is left alone', async ($, on) => {
  const runs: string[][] = []
  on('session.cwd', async () => ({ value: '/work/back' }))
  on('fs.stat', async (_$, e) => {
    if (e.path.endsWith('/.hivemind-hub')) return { deny: 'ENOENT: no such file or directory' }
    return { value: { kind: 'file', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }
  })
  on('process.run', async (_$, e) => {
    runs.push([...e.argv])
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('tool.call', async () => ({ result: 'ran' }) as never)
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/work/back', surface: 'terminal', isInteractive: true })
  expect((await $.tool.call({ tool: 'Edit', tool_use_id: 't', file_path: '/work/back/a.ts', old_string: 'a', new_string: 'b' } as never)).deny).toBeUndefined()
  expect((await $.tool.call({ tool: 'Bash', tool_use_id: 't', command: 'git commit -m x' } as never)).deny).toBeUndefined()
  expect(runs).toEqual([])
})
