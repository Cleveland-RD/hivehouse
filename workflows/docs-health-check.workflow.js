/**
 * docs-health-check.workflow.js
 * ------------------------------------------------------------------
 * A documentation health-check for the current project (or for named project groups passed as args).
 * For each repo it: audits docs vs the last N days of git history + live code,
 * flags inconsistencies / missing info / structure problems, synthesizes a
 * MINIMAL-CHURN change plan, and (in apply mode) applies it to the WORKING TREE.
 * It NEVER commits: you review the uncommitted diff.
 *
 * INVOKE (a plugin workflow is namespaced by its plugin, so as a command it is /hivehouse:docs-health-check):
 *   /hivehouse:docs-health-check                  -> the current project (git top level of the working directory), report only, 30 days
 *   /hivehouse:docs-health-check apply            -> the same, applying the plan to the working tree (uncommitted)
 *   /hivehouse:docs-health-check report 60        -> report only, last 60 days
 * Or programmatically:
 *   Workflow({ scriptPath: "<plugin root>/workflows/docs-health-check.workflow.js", args: { mode: "apply", sinceDays: 60 } })
 *   Workflow({ scriptPath: "...", args: { groups: [{ name: "Backend", repos: ["/abs/api", "/abs/web"] }] } })  // named groups
 *   Workflow({ scriptPath: "...", args: { groups: [...], group: "Backend" } })                              // one of them
 *
 * ARGS (all optional):
 *   groups:     [{ name, repos: [absPath,...] }]   named project groups. Omit = the current project only.
 *   group:      string | string[]                  run only these named group(s) from `groups`; needs `groups`.
 *   sinceDays:  number                             default 30  (window for "recent changes")
 *   mode:       "report" | "apply"                 default "report"  (apply = write to working tree, NO commit)
 *   reportPath: absolute path for the md report    default <first repo>/.hivehouse/reports/docs-health-report-<date>.md
 *               (.hivehouse/ is where hivehouse keeps per-project state and git ignores it, so report mode leaves the tree as it was)
 *
 * The workflow runtime has no shell or working-directory global, so the current project is found by one small agent
 * that runs `git rev-parse --show-toplevel`.
 *
 * NOTE ON ACCESS: agents inspect repos with Bash (git/grep/find/sed) so it works
 * regardless of which dirs are "added". In apply mode the apply agents WRITE files;
 * if a target repo is not in your working set you may get permission prompts: add
 * the repos with /add-dir (or run from a session that includes them) for a smooth apply.
 * ------------------------------------------------------------------
 */

export const meta = {
  name: 'docs-health-check',
  description: 'Audit the current project\'s docs (or named project groups) and optionally fix them: inconsistencies, structure, missing info. Never commits.',
  whenToUse: 'Periodic documentation sweep of the current project, or of named project groups passed via args.',
  phases: [
    { title: 'Audit', detail: 'one read-only agent per repo: inventory, recent-change gaps, inconsistencies' },
    { title: 'Cross-repo', detail: 'one agent per group of two or more repos: shared concepts, terminology/structure drift, unification' },
    { title: 'Plan + apply', detail: 'per repo: minimal-churn plan, then apply to working tree (no commit) unless mode=report' },
    { title: 'Report', detail: 'consolidate findings + applied changes + human-decision items into one markdown report' },
  ],
}

// ----------------------------- config -----------------------------
// Normalize args so this works whether invoked programmatically with an OBJECT
// (Workflow({ args: { mode: "apply", sinceDays: 60 } })) OR as a slash command with
// positional TEXT (/hivehouse:docs-health-check apply 60). Token rules for the text form:
//   a number (optional trailing 'd') -> sinceDays ; "report"/"apply" -> mode ;
//   anything else -> group name(s), which need `groups` to name them.
function normalizeArgs(a) {
  if (a && typeof a === 'object' && !Array.isArray(a)) return a
  const text = (typeof a === 'string') ? a : (Array.isArray(a) ? a.join(' ') : '')
  const out = {}, names = []
  for (const t of text.trim().split(/[\s,]+/).filter(Boolean)) {
    const lt = t.toLowerCase()
    if (lt === 'report' || lt === 'apply') out.mode = lt
    else if (/^\d+d?$/.test(lt)) out.sinceDays = parseInt(lt, 10)
    else names.push(t)
  }
  if (names.length) out.group = names
  return out
}
const A = normalizeArgs(args)

// args.groups, when given, is a non-empty list of { name, repos } with absolute repo paths: say so plainly, never a TypeError
function checkGroups(list) {
  if (!Array.isArray(list) || !list.length) {
    throw new Error('docs-health-check: args.groups must be a non-empty list of { name, repos }, e.g. [{ name: "Backend", repos: ["/abs/api", "/abs/web"] }]')
  }
  list.forEach((g, i) => {
    const ok = g && typeof g === 'object' && typeof g.name === 'string' && g.name !== ''
      && Array.isArray(g.repos) && g.repos.length > 0 && g.repos.every((r) => typeof r === 'string' && r.startsWith('/'))
    if (!ok) {
      throw new Error(`docs-health-check: args.groups[${i}] needs a name and a non-empty repos list of absolute paths, e.g. { name: "Backend", repos: ["/abs/api"] }`)
    }
  })
  return list
}
const named = A.groups === undefined || A.groups === null ? null : checkGroups(A.groups)
if (A.group && !named) {
  throw new Error(`docs-health-check: group ${JSON.stringify(A.group)} was named but no groups were passed. Pass args.groups, or omit the group to check the current project.`)
}
let groups
if (named) {
  groups = named
  // Optional selector: run only specific group(s) by name; case-insensitive. Omit to run every named group.
  if (A.group) {
    const want = (Array.isArray(A.group) ? A.group : [A.group]).map((s) => String(s).toLowerCase())
    groups = named.filter((g) => want.includes(String(g.name).toLowerCase()))
    if (!groups.length) {
      throw new Error(`docs-health-check: no group matched ${JSON.stringify(A.group)}. Available: ${named.map((g) => g.name).join(', ')}`)
    }
  }
} else {
  // The current project: the runtime has no shell or working directory, so one small agent reads the git top level.
  const where = await agent('Run `git rev-parse --show-toplevel` with Bash in your working directory and return the absolute path it prints. If it fails, return an empty string for root.', {
    label: 'find-project-root', schema: { type: 'object', additionalProperties: false, required: ['root'], properties: { root: { type: 'string' } } },
  })
  const root = where && typeof where.root === 'string' ? where.root.trim().replace(/\/+$/, '') : ''
  if (!root.startsWith('/')) throw new Error('docs-health-check: the working directory is not inside a git repository, so there is no current project. Run it from a repo, or pass args.groups.')
  groups = [{ name: root.split('/').pop() || 'project', repos: [root] }]
}
const sinceDays = A.sinceDays || 30
const mode = (A.mode === 'apply') ? 'apply' : 'report'
// default: <first repo>/.hivehouse/reports/docs-health-report-<date>.md, the date filled in by the report agent. .hivehouse/ is
// where hivehouse keeps per-project state; it is git-ignored through .git/info/exclude, so the report is never an untracked file
// (which would make report mode change the tree and turn a gate's dirty check red).
const firstRepo = groups[0].repos[0].replace(/\/+$/, '')
const reportPath = A.reportPath || `${firstRepo}/.hivehouse/reports/docs-health-report-<date>.md`
const reportInState = !A.reportPath
// the line hh_ensure_state writes (bin/hh-lib.sh), the same one and only when absent
const IGNORE_STATE = `Before writing the report, make sure git ignores .hivehouse/ in ${firstRepo}: run \`git -C ${firstRepo} ls-files -- .hivehouse\`; if it prints anything, those files are tracked, so do not write under .hivehouse/ at all: write the report OUTSIDE every repository, to \`\${TMPDIR:-/tmp}/docs-health-report-<date>.md\` (resolve $TMPDIR with Bash), and say so in the reportPath you return and in the summary. Otherwise run \`common=$(git -C ${firstRepo} rev-parse --path-format=absolute --git-common-dir)\`, then \`mkdir -p "$common/info"\`, \`touch "$common/info/exclude"\` and \`grep -qx '/.hivehouse/' "$common/info/exclude" || echo '/.hivehouse/' >> "$common/info/exclude"\` (append that exact line, and only when it is absent), and \`mkdir -p ${firstRepo}/.hivehouse/reports\`.`
const WRITE_UNLESS_TRACKED = `Unless the check above sent the report to \${TMPDIR:-/tmp}, write the report to ${reportPath} (create the file; replace <date> with today's date).`
const WRITE_GIVEN = `Write the report to ${reportPath} (create the file; replace <date> with today's date).`
const base = (p) => p.replace(/\/+$/, '').split('/').pop()

// ----------------------------- shared rules -----------------------------
const EXCLUSIONS = `Do NOT touch, move, rewrite, or rename any of: HANDOFF.md files and anything under .hivehouse/ (session snapshots and team state), backup or operational-data folders under docs/ (any directory named like *-backups), generated files, node_modules, .next, .git, or anything matched by .gitignore. Leave them untouched.`

const CONVENTIONS = `Conventions this repo set should converge on (apply only where it does not cause churn-for-churn):
- File names: kebab-case (lowercase, hyphen-separated). Conventional ROOT files keep their canonical names: README.md, CLAUDE.md, AGENTS.md, LICENSE, CHANGELOG.md, and a docs index named docs/README.md.
- Each repo has a docs index hub at docs/README.md linking its docs with one-line blurbs (relative links). No hardcoded counts.
- Completed/shipped plans live in docs/plans/archive/ ; reference docs in docs/reference/ ; specs in docs/specs/.
- Cross-repo references are LABELED PROSE ("see \`docs/reference/x.md\` in the <repo-name> repo"), NEVER relative file links (the repos are separate checkouts).
- NO hard deletes: completed/dead docs move to docs/plans/archive/ via git mv; anything you would truly delete goes into deleteCandidates (surfaced, never applied).
- MINIMAL CHURN: preserve already-correct locations; only relocate genuinely misplaced files. Do not reshuffle a taxonomy that already works.`

const INSPECT = `Use Bash for all inspection so it works on any repo path: \`git -C <repo> log\`, \`git -C <repo> status\`, \`find <repo>/docs -name '*.md'\`, \`sed -n\`/\`head\` to read headers, \`grep -rn\` under <repo>/src to verify claims against live code. Always VERIFY a doc claim against the actual code before asserting it is correct or stale.`

// ----------------------------- schemas -----------------------------
const AUDIT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repo', 'docInventory', 'recentChangeGaps', 'inconsistencies', 'structureNotes', 'hasIndex'],
  properties: {
    repo: { type: 'string' },
    hasIndex: { type: 'boolean', description: 'does docs/README.md (or equivalent index) already exist?' },
    docInventory: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['path', 'classification', 'recommendedAction'],
        properties: {
          path: { type: 'string' },
          classification: { type: 'string', enum: ['current', 'stale', 'completed-plan', 'superseded', 'working-doc', 'misplaced', 'operational-data', 'unknown'] },
          summary: { type: 'string' },
          issues: { type: 'string' },
          recommendedAction: { type: 'string', enum: ['keep', 'edit', 'rewrite', 'archive', 'relocate', 'rename', 'delete-candidate', 'leave-untouched'] },
          target: { type: 'string', description: 'new path if relocate/rename/archive; else empty' },
        },
      },
    },
    recentChangeGaps: {
      type: 'array', description: 'notable changes from the last N days of git log, and whether docs reflect them',
      items: {
        type: 'object', additionalProperties: false,
        required: ['change', 'documented'],
        properties: {
          change: { type: 'string' },
          documented: { type: 'string', enum: ['yes', 'partial', 'no'] },
          gap: { type: 'string' },
          recommendedDocAction: { type: 'string' },
          codeAnchors: { type: 'string' },
        },
      },
    },
    inconsistencies: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['kind', 'detail'],
        properties: {
          kind: { type: 'string', enum: ['naming', 'structure', 'stale-content', 'broken-link', 'missing-index', 'duplication', 'misleading-label', 'other'] },
          detail: { type: 'string' },
          fix: { type: 'string' },
        },
      },
    },
    structureNotes: { type: 'string', description: 'overall layout assessment + minimal-churn target for THIS repo' },
  },
}

const XREF_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['group', 'relationships', 'crossRepoInconsistencies', 'unifiedStructure'],
  properties: {
    group: { type: 'string' },
    relationships: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['topic'],
        properties: { topic: { type: 'string' }, repoA: { type: 'string' }, repoB: { type: 'string' }, codeAnchor: { type: 'string' }, suggestedCrossRef: { type: 'string', description: 'which doc should carry a prose ref to which, and the prose text' } },
      },
    },
    crossRepoInconsistencies: {
      type: 'array', description: 'terminology drift, divergent doc structure, duplicated-but-diverging content across the group',
      items: { type: 'object', additionalProperties: false, required: ['detail'], properties: { detail: { type: 'string' }, repos: { type: 'string' }, fix: { type: 'string' } } },
    },
    unifiedStructure: { type: 'string', description: 'recommended unified taxonomy + naming convention for the whole group, minimal-churn' },
  },
}

const PLAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repo', 'taxonomy', 'moves', 'archives', 'deleteCandidates', 'create', 'rewrite', 'edit', 'index', 'crossRefs', 'referenceUpdates'],
  properties: {
    repo: { type: 'string' },
    taxonomy: { type: 'string', description: 'target structure for this repo, minimal-churn' },
    moves: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['from', 'to', 'reason'], properties: { from: { type: 'string' }, to: { type: 'string' }, reason: { type: 'string' } } }, description: 'content-UNCHANGED relocations/renames (incl. kebab renames) via git mv' },
    archives: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['from', 'to', 'reason'], properties: { from: { type: 'string' }, to: { type: 'string' }, reason: { type: 'string' } } }, description: 'completed/dead docs git mv into docs/plans/archive/' },
    deleteCandidates: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['path', 'reason'], properties: { path: { type: 'string' }, reason: { type: 'string' } } }, description: 'NEVER applied — surfaced to human only' },
    create: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['path', 'brief'], properties: { path: { type: 'string' }, brief: { type: 'string' }, crossRefs: { type: 'array', items: { type: 'string' } } } } },
    rewrite: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['path', 'brief'], properties: { path: { type: 'string' }, oldPath: { type: 'string' }, brief: { type: 'string' }, crossRefs: { type: 'array', items: { type: 'string' } } } } },
    edit: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['path', 'changes'], properties: { path: { type: 'string' }, changes: { type: 'string', description: 'precise targeted staleness fixes; preserve the rest' } } } },
    index: { type: 'object', additionalProperties: false, required: ['path', 'brief'], properties: { path: { type: 'string' }, brief: { type: 'string' } } },
    crossRefs: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['fromDoc', 'linkText'], properties: { fromDoc: { type: 'string' }, linkText: { type: 'string', description: 'labeled prose ref to the other repo' } } } },
    referenceUpdates: { type: 'array', description: 'ACTIVE files (not archived plans, not HANDOFF) that reference a doc being moved/renamed and must be repointed', items: { type: 'object', additionalProperties: false, required: ['file', 'change'], properties: { file: { type: 'string' }, change: { type: 'string' } } } },
  },
}

const APPLY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repo', 'applied', 'summary'],
  properties: {
    repo: { type: 'string' },
    applied: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['action', 'path'], properties: { action: { type: 'string' }, path: { type: 'string' }, detail: { type: 'string' } } } },
    deferred: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['path', 'why'], properties: { path: { type: 'string' }, why: { type: 'string' } } } },
    deleteCandidates: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['path', 'reason'], properties: { path: { type: 'string' }, reason: { type: 'string' } } } },
    judgmentCalls: { type: 'array', items: { type: 'string' }, description: 'reversible decisions the human should sanity-check' },
    brokenLinksAfter: { type: 'array', items: { type: 'string' }, description: 'broken intra-repo links remaining after apply (should be empty in touched files)' },
    summary: { type: 'string' },
  },
}

const REPORT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['reportPath', 'summary', 'topActions'],
  properties: {
    reportPath: { type: 'string' },
    summary: { type: 'string' },
    topActions: { type: 'array', items: { type: 'string' }, description: 'prioritized cross-project action items for the human' },
  },
}

// ----------------------------- prompts -----------------------------
const auditPrompt = (repo) => `Read-only documentation audit of the repo at ${repo}.
${INSPECT}

Do all of the following:
1. INVENTORY every doc under ${repo}/docs (and doc-like .md at the repo root except README.md/CLAUDE.md). Classify each. Archived plans already under docs/plans/archive/ are correctly archived (classification completed-plan, action keep) — do NOT deep-read them.
2. RECENT CHANGES: run \`git -C ${repo} log --since="${sinceDays} days ago" --pretty=format:'%ad %s' --date=short\`. From the notable changes, determine for each whether the docs (incl. ${repo}/CLAUDE.md) reflect it — verify against live code under ${repo}/src. Record gaps.
3. INCONSISTENCIES: flag naming (non-kebab files), structure (loose root docs, missing docs index, snake_case dirs), stale content (doc contradicts code), broken intra-repo markdown links, duplication, and misleading labels/comments.
4. Note whether a docs index (docs/README.md) exists, and a minimal-churn target structure for THIS repo.

${EXCLUSIONS}
Return the structured audit. Be concrete; cite real paths.`

const xrefPrompt = (group, audits) => `Read-only cross-repo analysis for the "${group.name}" project group. Repos: ${group.repos.join(', ')}.
${INSPECT}

Per-repo audit findings (JSON):
${JSON.stringify(audits.filter(Boolean), null, 2)}

Identify:
1. RELATIONSHIPS: shared concepts/contracts spanning the repos (shared schemas, API contracts where one repo calls another, shared domain models). For each, name the code anchor and where a LABELED PROSE cross-reference should live.
2. CROSS-REPO INCONSISTENCIES: terminology drift, divergent doc structure between the repos, duplicated-but-diverging content, contracts documented on one side only.
3. UNIFIED STRUCTURE: a recommended unified taxonomy + naming convention for the whole group, MINIMAL-CHURN (preserve what already works).
${CONVENTIONS}
Return structured.`

const synthPrompt = (repo, audit, xref, group) => `You are the synthesis architect for the repo ${repo} (group "${group.name}"). Produce ONE MINIMAL-CHURN change plan.
${INSPECT}

This repo's audit (JSON):
${JSON.stringify(audit, null, 2)}

This group's cross-repo analysis (JSON):
${JSON.stringify(xref, null, 2)}

${CONVENTIONS}
${EXCLUSIONS}

Rules for the plan:
- moves[] = content-unchanged relocations/renames (kebab renames, folder moves) via git mv. archives[] = completed/dead docs into docs/plans/archive/.
- For EVERY move/rename, populate referenceUpdates[] with the ACTIVE files (CLAUDE.md, the docs index, agent defs, active plans, code comments — NOT archived plans, NOT HANDOFF) that reference the old path and must be repointed. Use grep to find them.
- create[] only to fill genuine gaps (prefer folding new content into CLAUDE.md when that is the repo's authoritative reference, to avoid duplication). edit[] = targeted staleness fixes. index = the docs/README.md hub (create if missing; no hardcoded counts).
- crossRefs[] = labeled prose cross-references to the sibling repo(s), from the xref analysis.
- deleteCandidates[] = surfaced only, never applied.
Use real absolute paths. Call out risks the human should sanity-check.`

const applyPrompt = (repo, plan) => `Apply this documentation change plan to the repo ${repo}. Work methodically and VERIFY as you go. ${INSPECT}

PLAN (JSON):
${JSON.stringify(plan, null, 2)}

EXECUTION ORDER and rules:
1. FIRST do all archives[] and moves[] via \`git -C ${repo} mv <from> <to>\` (create target dirs with mkdir -p first). git mv stages the rename — that is fine.
2. THEN apply referenceUpdates[]: for each, edit the ACTIVE file to repoint the old path to the new one. Verify with grep that no ACTIVE file still references an old path (archived plans + HANDOFF are intentionally left as historical).
3. THEN create[] (write new files), the index (docs/README.md — relative links, one-line blurbs, NO hardcoded counts), rewrite[], and edit[] (targeted; preserve the rest of each file). Add crossRefs[] as LABELED PROSE (never relative links to another repo). When writing prose that points at the other repo, use the repo NAME + a repo-relative path — NEVER an absolute filesystem path.
4. NEVER hard-delete (deleteCandidates are surfaced, not applied). ${EXCLUSIONS}
5. CRITICAL: do NOT run \`git commit\` and do NOT run \`git add -A\`. Leave all changes UNCOMMITTED in the working tree for human review. (git mv stages renames; that is acceptable.)
6. After applying, run a broken-link check: grep markdown links \`](path)\` in the docs you touched, URL-decode, resolve relative to each file, and confirm targets exist. Fix any breakage you introduced; report any that remain.
Verify each write by re-reading. Return the structured apply report.`

const reportPrompt = (allResults, applied) => `Write a single consolidated documentation health-check report (markdown) covering all groups, then return its path + a short summary.
${INSPECT}

MODE: ${mode} (${applied ? 'changes were APPLIED to working trees, uncommitted' : 'REPORT ONLY — nothing was changed'}).
Window: last ${sinceDays} days.

ALL RESULTS (JSON — audits, cross-repo analyses, plans${applied ? ', and apply reports' : ''}):
${JSON.stringify(allResults, null, 2)}

The report must have, per group and per repo: (a) recent-change documentation gaps, (b) inconsistencies (naming/structure/stale/broken-link/missing-index/duplication), (c) cross-repo issues + the unified-structure recommendation, (d) ${applied ? 'what was APPLIED (and any judgment calls / deferred items / remaining broken links)' : 'the recommended change plan'}, and (e) deleteCandidates (never auto-applied) for human decision. End with a prioritized, cross-project "Top actions" list.
Determine today's date with \`date +%F\` via Bash. ${reportInState ? IGNORE_STATE + '\n' + WRITE_UNLESS_TRACKED : WRITE_GIVEN}
If you cannot write to the path you chose, write the report OUTSIDE every repository, to \${TMPDIR:-/tmp}/docs-health-report-<date>.md (resolve $TMPDIR with Bash), and say so in the reportPath you return and in the summary. Never write the report inside a repository anywhere but at ${reportPath}${reportInState ? ', and never under .hivehouse/ when the check above found it tracked' : ''}. Return the actual reportPath you wrote, a short summary, and the top actions.`

// ----------------------------- run -----------------------------
log(`docs-health-check | mode=${mode} | window=${sinceDays}d | groups: ${groups.map((g) => `${g.name}(${g.repos.length})`).join(', ')}`)

const allResults = []
for (const group of groups) {
  const gname = group.name
  phase(`${gname}: Audit`)
  const audits = await parallel(
    group.repos.map((repo) => () => agent(auditPrompt(repo), { label: `audit:${base(repo)}`, phase: `${gname}: Audit`, schema: AUDIT_SCHEMA, agentType: 'Explore' }))
  )

  phase(`${gname}: Cross-repo`)
  // a group of one repo has nothing to compare across
  const xref = group.repos.length < 2
    ? { group: gname, relationships: [], crossRepoInconsistencies: [], unifiedStructure: 'Single repository: no cross-repo analysis.' }
    : await agent(xrefPrompt(group, audits), { label: `xref:${gname}`, phase: `${gname}: Cross-repo`, schema: XREF_SCHEMA })

  phase(`${gname}: Plan + apply`)
  const perRepo = await pipeline(
    group.repos,
    (repo, _orig, i) => agent(synthPrompt(repo, audits[i], xref, group), { label: `plan:${base(repo)}`, phase: `${gname}: Plan + apply`, schema: PLAN_SCHEMA }),
    (planResult, repo) => {
      if (!planResult) return { plan: null, apply: null }
      if (mode !== 'apply') return { plan: planResult, apply: null }
      return agent(applyPrompt(repo, planResult), { label: `apply:${base(repo)}`, phase: `${gname}: Plan + apply`, schema: APPLY_SCHEMA })
        .then((r) => ({ plan: planResult, apply: r }))
        .catch(() => ({ plan: planResult, apply: null }))
    }
  )

  allResults.push({ group: gname, repos: group.repos, audits, xref, perRepo })
  log(`${gname}: audited ${audits.filter(Boolean).length}/${group.repos.length} repos, planned ${perRepo.filter(Boolean).length}`)
}

phase('Report')
const report = await agent(reportPrompt(allResults, mode === 'apply'), { label: 'report', phase: 'Report', schema: REPORT_SCHEMA })

return { mode, sinceDays, groups: groups.map((g) => g.name), report, results: allResults }
