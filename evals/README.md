# Eval cases

Cases for `claude plugin eval` ([plugin evals](https://code.claude.com/docs/en/plugin-evals)). They check the start
skill's behaviour before anything is spawned:

| Case | The run passes when |
|---|---|
| `start-plans-and-waits` | a clear task in a project whose facts are all recorded is planned (`HM-PLAN:`) and nothing is spawned, edited, written or sent before the OK |
| `start-asks-open-point` | a task that leaves a product choice open is asked about (`HM-CLARIFY:` and `AskUserQuestion`) and nothing is spawned |
| `start-asks-nothing` | a fully specified task gets no question (no marker, no `AskUserQuestion`), only the plan, and nothing is spawned |

Every grader is free (no judge model). The markers are matched in the trace at the start of an assistant text or after
an escaped newline, since the skill's own instructions name them only in backticks; `tests/test_evals.sh` keeps both
true and checks every case's files and scaffold without running Claude.

A model that writes `HM-CLARIFY:` inside `AskUserQuestion`'s question field, rather than on its own line, is graded as not
asking: a known false negative.

## Running them is a paid step

Only on the owner's word. From the plugin root:

```bash
claude plugin eval . --scaffold --trust-plugin --ablation none --max-cost-usd 3 \
  --allow-tools "Bash(hm-slot status)" "Bash(hm-context *)" "Bash(hm-gate-verify *)" "Bash(hm-settings resolve *)" "Bash(hm-manifest *)" "Bash(hm-disk *)" "Edit(./.hivehouse/**)"
```

- The grant is the start skill's own `allowed-tools`, less what would act before the owner's OK: `hm-spawn`, `hm-rotate`,
  `hm-self-rotate`, `hm-slot release` and the writes to `CLAUDE.md`. A spawn the skill attempts is then denied and still
  recorded, which the `nothing-spawned` grader catches. `tests/test_evals.sh` refuses a grant the skill does not list.
- No `Write(...)` grant: Claude Code checks file paths against `Edit(...)` rules only, which apply to every built-in tool
  that edits a file, Write included, and it never consults a `Write(path)` rule
  ([permissions](https://code.claude.com/docs/en/permissions)).
- `--ablation none`: without the plugin `/hivehouse:start` does not exist, so a baseline arm would measure nothing and
  double the cost.
- Three cases, three runs each, nine runs in all, under the `--max-cost-usd 3` ceiling. The first paid run is smaller,
  `--runs 1 --case <one case>`, on the owner's word, to settle what is open below before nine runs are paid for.

Open until the first run:

- whether the session hook and the `hm-*` checks can write their state under the run's temporary home inside the Bash
  sandbox;
- what `AskUserQuestion` returns in a run with nobody to answer it;
- whether a call the grant denies is counted by a `tool_used` grader, which `nothing-spawned` and the waiting graders rely
  on to see an attempt that was refused;
- whether first-run.md's step 3 checks pass under the grant: `tmux -V`, `jq --version` and `git status` running
  unprompted as read-only commands, and `hm-disk` through its grant;
- whether a scaffold runs from its case directory, so the wrapper's `$(dirname "$0")` finds `scaffold-records.sh`
  (a run whose scaffold fails scores 0 with `scaffold failed`, so this cannot pass unseen).
