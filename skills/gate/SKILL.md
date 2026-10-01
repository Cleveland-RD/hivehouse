---
name: gate
description: Run the project's gate into a log file, verify every step's result line and the commit rules, and refuse to call anything green without the log. Use before landing or handing back work, and when verifying a builder's gate log.
when_to_use: When asked to "run the gate", "gate this", "verify the gate log", or before reporting work as done or green.
allowed-tools: Bash(hm-gate-verify *) Bash(hm-slot status) Bash(hm-slot release *) Bash(hm-settings resolve *) Read
---

# hivemind: gate

Read `${CLAUDE_PLUGIN_ROOT}/rules/RULES.md` first. Call every `hm-*` executable and every `git` command on its own, never
inside a compound command. No git rule is pre-approved, so each `git` call asks; `hm-gate` and `hm-slot run` are not
pre-approved either and will ask. That is intended.

**Never report green without the log path and the `hm-gate-verify` line.** A last exit code alone proves nothing: a
gate can skip a step and still exit 0.

## 1. Find the gate

Use the project's recorded gate command (`CLAUDE.md`, `CLAUDE.local.md`, `.hivemind/`). If none is recorded, ask the
orchestrator or owner; do not invent one. Commit first: the gate runs on the committed tip. Note the base branch and
the tip hash being gated (`git rev-parse HEAD`), and that the tree is clean (`git status`): a log vouches only for a
clean, committed tree.

## 2. Check the slot

`hm-slot status`. If another job holds it, wait or report who holds it; never run beside it, and never release a slot
you did not take.

## 3. Run it into a log

Choose the log path (outside the tracked tree, for example `.hivemind/tmp/<name>-gate.log`).

- A gate made of separate commands: `hm-gate --log <file> -- <name> <command> [<name> <command> ...]`. It takes the
  slot itself (never wrap it in `hm-slot run`), runs every step even after a failure, and writes `<name> exit <n>`
  after each. Step names are letters, digits, `_`, `.`, `-` only, and never `..`.
- A gate that is already one script printing `<step> exit <n>` lines:
  `hm-slot run gate -- <script>` with its output redirected to the log file, as the project records it.

## 4. Verify the log

For a log `hm-gate` wrote: `hm-gate-verify log <file> --commit <tip>`

It starts with a header naming every step it set out to run, the commit and whether the tree was dirty, so no
`--expect` is needed: a gate stopped part way is red because a named step has no line. It passes only if the log has
at least one `<step> exit <n>` line, every one is `exit 0`, no step appears twice, and the header names the commit you
gave on a clean tree. A log left from an earlier run, or from uncommitted changes, is RED.

For a project's own gate script, which writes no header: `hm-gate-verify log <file> --expect <every step the project's
gate has, comma-separated>`, **without** `--commit`. With `--commit` such a log is always RED ("vouches for no commit"),
so never pass it. The report then says that log names no commit: it shows the steps passed, not which commit they ran
on. On failure the command names the steps; report those, not a summary.

## 5. Verify the commits

Resolve the safety values first, each on its own call, so a project cannot loosen the owner's:

- `hm-settings resolve files_per_commit ${user_config.files_per_commit}`
- `hm-settings resolve allow_attribution ${user_config.allow_attribution}`

Then: `hm-gate-verify commits <base>..<tip> --max-files <resolved files_per_commit> --style ${user_config.commit_style} --attribution <deny, or allow when the resolved allow_attribution is true>`

All three flags are required, so nothing is loosened by leaving one out. Add `--no-body` when the rules say one-line
subjects only (a body is otherwise a warning). It checks the subject style, the files per commit against the first
parent (a merge counts only the files where it differs from git's own merge of its parents, its own content) and any
attribution trailer. An empty range is red: nothing checked is not a pass. Report each violation with its commit.

## 6. Report

Verdict first: `GREEN` or `NOT GREEN`. Then: the log path, the `hm-gate-verify log` line, the `commits` result, the commit
gated, and what was not run and why. If anything failed, stop; do not re-run hoping for a different result:
find the cause first (root cause before any fix).
