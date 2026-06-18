---
name: task-loop
description: >-
  Runs tasks in a plan-execute-review-fix loop via subagents with configurable
  models (default Composer): MCP index_status first, snapshot commit, readonly
  plan, dev execution, readonly review, fix cycles until PASS, final commit.
  Passes semantic search availability to subagents. Skips plan and execution
  for review-only tasks. Use when the user invokes /task-loop or task loop.
disable-model-invocation: true
---

# Iterative task execution

The orchestrator **only coordinates** subagents — it does not write code or review; it commits only on steps 2 and 8.

Invoking this skill = permission for the initial and final commit. **Commit messages must be in Russian** (subject + body).

Templates, MCP, HEREDOC: [reference.md](reference.md).

## Quick start

0. `index_status` → `semantic_search: on` / `on (indexing)` / off
1. Input: task, mode, models
2. `implement`: 2 → 3 → 4 → 5 ↔ 6 → 8 → 9
3. `review`: skip 2–4 → 5 ↔ 6 → 8 → 9

## Step 0. `index_status`

Before all steps: `CallMcpTool` → `index_status` (server semantic-search-zvec-go). Criteria and markers — [reference.md](reference.md#semantic-search-context).

The orchestrator does not call `semantic_search`. Insert `semantic_search: …` into step 3–6 prompts only when search is available.

## Step 1. Input

- **Original Task** — verbatim into all subagents.
- **mode**: `implement` (default) | `review` — auto from keywords («ревью», «review», «code review», …) or explicit `mode: review` / `mode: implement`.
- **Models**: `plan_model`, `dev_model`, `review_model` — default Composer; slugs and aliases — [reference.md](reference.md#models).

```
Task Progress:
- [ ] 0 index_status
- [ ] 1 input
- [ ] 2 snapshot / skip
- [ ] 3 plan / skip
- [ ] 4 execute / skip
- [ ] 5–6 review/fix (N/5)
- [ ] 8 final commit
- [ ] 9 report
```

## Subagents

Common: `subagent_type: generalPurpose`, `run_in_background: false`. **Retry: max 1 per step → STOP.**

| Step | description | readonly | model | Prompt |
|------|-------------|----------|-------|--------|
| 3 Plan | Plan task execution | true | plan_model | [Plan](reference.md#plan) |
| 4 Execute | Execute task | false | dev_model | [Execute](reference.md#execute) |
| 5 Review | Review task result | true | review_model | [Review](reference.md#review) |
| 6 Fix | Fix review findings | false | dev_model | [Fix](reference.md#fix) |

+ `semantic_search: on` / `on (indexing)` when available (see [Subagent common](reference.md#subagent-common)).

## Step 2. Snapshot commit (`implement` only)

Skip in `review`. `git status` + `git diff` + `git log -3`; no changes → step 3.

Otherwise: stage (no secrets), commit in Russian — [reference.md](reference.md#commits). Hook fail → no amend, new commit or STOP.

## Step 3. Plan (`implement` only)

Task per table. Save `## Execution plan` → pass verbatim to step 4. Readonly; do not modify files.

## Step 4. Execute (`implement` only)

Task per table. Follow the plan; report deviations. Save report for step 9.

## Step 5. Review

First step in `review`; in `implement` — after 4 and after each 6.

Task per table. Criteria: task complete, code quality, tests/linter.

Parse `## Verdict` / `## Errors` / `## Fix plan` — [reference.md](reference.md#verdict-format):

| Condition | → |
|-----------|---|
| PASS or empty Errors | step 8 |
| FAIL + Errors | step 6 |
| Unrecognized format | FAIL; retry review with format reminder |

**Cycle 5 ↔ 6:** until PASS, max 5 iterations (count step 5 runs). Limit reached → STOP without final commit. No commits between iterations.

## Step 6. Fix

Only on FAIL. Task per table. Fix listed errors only; do not commit. → step 5 (not 3–4).

## Step 8. Final commit

Only after PASS. No changes → skip. Otherwise: stage, Russian message (why, not file list) — [reference.md](reference.md#commits). Hook handling — same as step 2.

## Step 9. Report

| Field | Value |
|-------|-------|
| Task | brief |
| Semantic search | on / on (indexing) / off |
| Mode, models | … |
| Snapshot, plan | hash / skip / n/a |
| Iterations 5↔6 | N |
| Outcome | PASS / STOP |
| Final commit | hash / skip |
| Files | from subagent reports |

## Safeguards

- Semantic search: step 0 required; when `on` — [Subagent common](reference.md#subagent-common).
- Commits, secrets, hooks, models, retry, fix scope — as above.
- Bugbot (optional): 2+ critical in one area → suggest `/review-bugbot`.

## Examples

`/task-loop Add email validation` · `/task-loop mode: review Review uncommitted changes` · `/task-loop plan: gemini, dev: codex Refactor coordinator`
