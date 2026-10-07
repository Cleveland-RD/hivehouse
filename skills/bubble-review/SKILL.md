---
name: bubble-review
description: Review a change at a stated depth (glance, delta, standard, full bubble) from a scratch copy, and give a PASS or FAIL verdict with REQUIRED, SHOULD and NOTE findings across nine bubble categories. Use when asked to review a diff, branch or tip.
when_to_use: When asked to review, "find bubbles", "any bubbles?", or to judge a builder's tip before landing.
allowed-tools: Bash(hh-resolve *) Bash(hh-gate-verify *) Bash(hh-slot status) Bash(hh-slot release *) Bash(hh-settings resolve *) Read Grep Glob
---

# hivehouse: bubble-review

Run `hh-resolve rules` and `hh-resolve role reviewer` and read the files they print first (the project's or the user's own
`custom/` file when there is one, else the plugin's). A bubble is anything
in a diff that fits one of the nine categories in `${CLAUDE_SKILL_DIR}/categories.md`; read that file before a standard
or full review. You are read-only: you change no code in any worktree.

Call every `hh-*` executable and every `git` command on its own, never inside a compound command. No git rule is
pre-approved, so each `git` call asks. Test runs go through `hh-slot run`, which is not pre-approved and will ask; that
is intended.

## Depth

The orchestrator states the depth in the request. You may raise it with a reason; never lower it.

| Depth | When | Work |
|---|---|---|
| Glance | tests, comments, copy, docs only | read the diff and the gate log |
| Delta | fixes after a review | new commits only, one break per fix |
| Standard | ordinary change | diff against the task, changed tests run, a break per new guard |
| Full bubble | money, auth, data writes, migrations, cross-service contracts, concurrency, large changes | all nine categories, probes, optional second opinion |

If no depth is stated, ask; if you cannot ask, take standard and say so.

## Procedure

1. **Task and diff.** Read the task first, then `git log <base>..<tip>` and `git diff <base>..<tip>`. Note every file
   and function changed and whether it is the right place.
2. **Scratch copy.** Work in a scratch directory, never the builder's worktree or the main tree: `git archive -o
   <scratch>.tar <tip>`, then `tar -x -f <scratch>.tar -C <scratch>` (two commands, no pipe). Save a copy of any file before you break it and restore it with `cp`, never `git checkout`.
3. **Gate log.** For a log `hh-gate` wrote: `hh-gate-verify log <file> --commit <tip>`. For a project's own headerless log:
   `hh-gate-verify log <file> --expect <steps>` instead, never with `--commit` (that is always RED), and say in the
   verdict that the log names no commit. Then the commit rules with
   `hh-gate-verify commits <base>..<tip> --max-files <n> --style <style> --attribution <allow|deny>`, each value from
   `hh-settings resolve`, so a project cannot loosen the owner's.
4. **Changed tests only,** through `hh-slot run --wait <label> -- <command>`. Do not run the whole suite unless asked.
5. **Break each new guard** with one change: count that the change matched exactly once, confirm the test fails, restore
   by copy. A break that matched twice or not at all is not evidence.
6. **Scan the nine categories** against the diff (full bubble: probe each with a concrete input). Look also at
   what consumes each changed thing (callers, other services, exports), not only the changed lines.
7. **Second opinion** (a read-only Codex run or a Fable subagent) only when the orchestrator relays the owner's request
   for one. Treat its findings as claims to verify, not verdicts.

## Verdict

First line: `PASS` or `FAIL`, the depth, and the tip hash reviewed. Then findings grouped by category, each with
file:line and the evidence, as:

- **REQUIRED**: blocks landing;
- **SHOULD**: fix soon, does not block;
- **NOTE**: information.

Then what you did not run and why (unrun checks are never implied). FAIL if any REQUIRED exists.
