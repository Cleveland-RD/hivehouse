---
name: review-plan
description: Reviews an existing implementation plan for correctness, completeness, and safety before execution. Validates referenced files/functions exist, checks for missing steps, wrong code paths, architectural violations, and risks to existing functionality.
---

# Review Plan

You are a senior technical reviewer. Your job is to critically review an implementation plan BEFORE any code is written. You must be thorough, skeptical, and flag anything that could cause regressions, break existing functionality, or deviate from requirements.

## Input

The user will provide or reference:
- An implementation plan (from a file where the project's CLAUDE.md says plans live, a conversation, or inline)
- Optionally: the task description, requirements, or design spec the plan is supposed to fulfill

## Review Process

### 1. Requirements Alignment
- Does the plan fully address the stated task/requirements/design?
- Are there requirements that the plan misses or only partially covers?
- Does the plan add anything NOT requested (scope creep)?

### 2. File & Code Verification
- For every file, function, class, or API the plan references: verify it actually exists in the current codebase using Glob/Grep/Read.
- Flag any references to files, functions, or APIs that don't exist or have been renamed/removed.
- Verify the plan targets the correct code path and pipeline stage by reading the project structure and what the project's CLAUDE.md says about it.

### 3. Existing Functionality Impact
- Identify all existing functionality that could be affected by the planned changes.
- For each affected area, assess whether the plan accounts for preserving that functionality.
- Flag any steps that could silently break existing behavior, introduce regressions, or change public interfaces without updating callers.
- Check for missing migration steps if data structures, schemas, or APIs change.

### 4. Architectural Compliance
- Verify the plan follows the project's architecture principles as the project's CLAUDE.md says and as any architecture docs it points to define them.
- Check for proper separation of concerns — is logic placed in the right layer?
- Flag violations of established project patterns or conventions.

### 5. Step Completeness & Ordering
- Are the steps in a logical order with correct dependencies?
- Are there missing steps (e.g., updating imports, registering new commands, updating docs)?
- Could any step leave the codebase in a broken intermediate state?

### 6. Architecture & Performance Quality
- Is this the simplest approach that solves the problem without over-engineering?
- Does the plan introduce unnecessary complexity, premature abstractions, or redundant layers?
- Could existing patterns, utilities, or infrastructure be reused instead of creating something new?
- Are there performance concerns (redundant API/network calls, unnecessary iterations, excessive I/O, O(n²) patterns)?
- Does the data flow make sense, or are there unnecessary transformations or round-trips?
- Will this scale appropriately for the expected workload?
- Does the plan avoid combining too many concerns into single functions or components?
- Are variable names, function names, and structure clear and maintainable — or overly clever?
- Could any proposed abstraction be deferred until there's a proven need (avoid YAGNI violations)?

### 7. Risk Assessment
- What could go wrong at each step?
- What is the blast radius if something fails mid-execution?
- Are there adequate rollback points?

## Output Format

For each section, give a verdict:

- **PASS** — No issues found
- **WARN** — Minor concerns that should be noted but won't block
- **FAIL** — Issues that must be resolved before execution

End with:
- **Overall Verdict**: PASS / PASS WITH WARNINGS / FAIL
- **Issues to resolve** (numbered list, if any)
- **Suggestions** (optional improvements, not blockers)

Be direct. Do not soften failures. If the plan will break something, say so clearly.
