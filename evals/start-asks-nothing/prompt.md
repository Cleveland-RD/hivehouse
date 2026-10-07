---
description: A fully specified task in a project whose facts are all recorded gets no question, only the plan.
expected_outcome: No HH-CLARIFY line; an HH-PLAN line; no hh-spawn call.
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, AskUserQuestion]
---

/hivehouse:start Add a --count flag to src/records.sh that prints only the number of records as a bare integer and a newline, and leave the default output unchanged. Add one test for it in tests/test_records.sh. Done when make test passes. Out of scope: every other file, other flags, and the README. No paid steps, no new dependencies.
