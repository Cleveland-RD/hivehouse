# The nine bubble categories

A bubble is anything in a diff that does one of these. Each has a small example of what it looks like.

1. **Breaks existing functionality.** A new bug, a regression, or something that stops working.
   *Example:* a helper now returns `null` for an empty list where callers did `list.length`; the empty-list page crashes.

2. **Architecturally incorrect.** Wrong layer, wrong pattern, or a violation of the established design.
   *Example:* a rule specific to one document type added to shared pipeline code that is meant to stay template-agnostic.

3. **Code duplication.** Repeats logic that already exists instead of reusing it; the same set of permitted values
   written out beside a declaration that already exists.
   *Example:* a second copy of the status list `['draft','sent','paid']` next to the `STATUSES` constant.

4. **Unnecessary overhead or performance issue.** N+1 queries, redundant work, wasteful allocations, a blocking call where
   async would do.
   *Example:* a query per row inside a loop over an invoice list, with no join or batch.

5. **Security or auth gaps.** A missing permission check, missing tenant or user scoping, unvalidated input at an API
   boundary, or access broadened unintentionally.
   *Example:* a new route loads a record by id without checking it belongs to the signed-in user.

6. **Silent failure or data corruption.** A swallowed exception, a catch that hides bugs, a default fallback that masks a
   changed upstream contract, transactional safety removed from a multi-write path, a missing soft-delete filter that
   lets deleted rows resurface.
   *Example:* `catch { return [] }` around a fetch, so an outage shows as "no results".

7. **API contract drift.** A changed response shape, a removed field, or a renamed query parameter, without checking every
   consumer (pages, exports, other services).
   *Example:* a field renamed in the response; the export job that reads the old name now writes blanks.

8. **Convention drift.** Solves a problem differently from how the codebase already solves it.
   *Example:* hand-rolled pagination where every other list uses the shared paginator; a hard delete where the project
   mandates soft delete.

9. **Stale or misleading names, comments or labels.** An identifier, comment or UI label says one thing while the code
   does another.
   *Example:* a tooltip that still names a removed field; a variable called `finalized` holding a draft value; a
   "Total active clients" label when the active filter is off.
