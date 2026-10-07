---
description: A clear task in a project whose facts are all recorded is planned, and nothing is spawned before the owner approves the plan.
expected_outcome: An HM-PLAN line with the team, then a stop to wait for approval; no hm-spawn call.
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, AskUserQuestion]
---

/hivehouse:start Add a --count flag to src/records.sh that prints only the number of records, and a test for it in tests/test_records.sh. Done when make test passes with the new test. Nothing else changes.
