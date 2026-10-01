// Runs workflows/docs-health-check.workflow.js outside Claude Code with a fake agent(), parallel(), pipeline(), phase() and
// log(), as the runtime provides them, and prints one JSON line: { ok, err?, calls, mode, groups }.
// usage: node docs-health-harness.mjs <script> <args-json> <root the fake root-finder answers>
import fs from 'fs';
const [script, argsJson, rootAnswer] = process.argv.slice(2);
const AsyncFn = Object.getPrototypeOf(async function () {}).constructor;
const calls = [];
let reportPrompt = '';
const agent = async (prompt, opts) => {
  calls.push(opts.label);
  const l = opts.label;
  if (l === 'find-project-root') return { root: rootAnswer };
  if (l.startsWith('audit:')) return { repo: l, hasIndex: true, docInventory: [], recentChangeGaps: [], inconsistencies: [], structureNotes: '' };
  if (l.startsWith('xref:')) return { group: l, relationships: [], crossRepoInconsistencies: [], unifiedStructure: '' };
  if (l.startsWith('plan:')) return { repo: l };
  if (l.startsWith('apply:')) return { repo: l, applied: [], summary: '' };
  if (l === 'report') { reportPrompt = prompt; calls.push('report-prompt:' + prompt.match(/MODE: \w+/)[0] + ' | ' + (prompt.match(/[Ww]rite the report to (\S+)/) || [])[1]); return { reportPath: 'x', summary: '', topActions: [] }; }
  return null;
};
const parallel = (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)));
const pipeline = (items, ...stages) => Promise.all(items.map(async (item, i) => { let v = item; for (const st of stages) v = await st(v, item, i); return v; }));
const body = fs.readFileSync(script, 'utf8').replace('export const meta', 'const meta');
const args = argsJson === 'undefined' ? undefined : JSON.parse(argsJson);
try {
  const r = await new AsyncFn('args', 'agent', 'parallel', 'pipeline', 'phase', 'log', body)(args, agent, parallel, pipeline, () => {}, () => {});
  console.log(JSON.stringify({ ok: true, calls, mode: r.mode, groups: r.groups, reportPrompt }));
} catch (e) {
  console.log(JSON.stringify({ ok: false, err: e.message, calls }));
}
