# Brief template

The shape of a message that hands work to an agent. Fill every section; write "none" rather than omit one.

```
BRIEF: <what this is about, one line>

CONTEXT (facts only; after each, where it was verified)
- <fact> — <file:line, command run, or who said it and when>
- <fact> — <...>

TASK
<what to produce, in the terms the owner used. An open ask: "find out why X", "design Y",
not "do it this way".>

DONE WHEN
- <observable condition, checkable by a command or a file>
- <...>

CONSTRAINTS
- Worktree/branch: <own worktree path and branch, or read-only>
- Files: <what may be touched, what may not>
- Commits: <--max-files N (hm-settings files_per_commit), --style <S> (userConfig commit_style), --attribution <allow|deny> (hm-settings allow_attribution); no push>
- Heavy jobs: through hm-slot; paid steps only on the owner's word (state any price)
- Rules: .hivehouse/team/<agent>/RULES.md and your role file beside it

REPORT BACK
Verdict first (DONE / BLOCKED / FAIL), then evidence (commands, log path, tip hash), then what was not run and why.
Send it to <orchestrator name>.
```

## Never put in a brief

- **A proposal.** "I think we should use X" makes the receiver defend or attack X instead of reading the code.
- **A reading of the evidence.** Give the evidence and where it lives; let the receiver read it.
- **An option list.** "A, B or C?" limits the answer to what the sender already imagined.
- **A yes-or-no framing.** "Is it the cache?" gets "yes" or "no", not the cause.
- **Anything unverified.** If a fact was remembered, inferred or relayed, say so and say how to check it; otherwise leave it out.
- **The owner's words paraphrased into a stronger claim.** Quote them.
