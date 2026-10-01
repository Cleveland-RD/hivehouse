---
description: A task that leaves a product choice open is asked about, not assumed, and nothing is spawned.
expected_outcome: An HM-CLARIFY line before a question about the export's format or fields; no hm-spawn call.
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, AskUserQuestion]
---

/hivemind:start Add an export of the records so they can be opened somewhere else.
