---
name: task-loop
description: >-
  Runs tasks in a plan-execute-review-fix loop via subagents with configurable
  models (default Composer): MCP index_status first, snapshot commit, readonly
  plan, dev execution, readonly review, fix cycles until PASS, final commit.
  Passes semantic search availability to subagents. Skips snapshot commit, plan,
  and execution for review-only tasks. Use when the user invokes /task-loop or
  task loop.
disable-model-invocation: true
---

# Iterative task execution

The orchestrator **only coordinates** subagents — it does not write code or review.

**Commits:** step 2 (snapshot) — **`implement` only**; step 8 (final) — after PASS in either mode. Invoking this skill = permission for those commits. **Never snapshot-commit in `review` mode.** Commit messages must be in Russian (subject + body).

Templates, MCP, HEREDOC: [reference.md](reference.md).

## Quick start

0. `index_status` → `semantic_search: on` / `on (indexing)` / off
1. Input: task, mode, models
2. `implement`: 2 → 3 → 4 → 5 ↔ 6 → 8 → 9
3. `review`: skip 2–4 → 5 ↔ 6 → 8 → 9

## Iteration counters

Initialize at orchestration start: `dev_cycles = 0`, `review_cycles = 0`.

| Counter | When +1 | In report |
|---------|---------|-----------|
| `dev_cycles` | step 4 or step 6 completes | yes — Step 9 |
| `review_cycles` | step 5 completes | no — limit only |

`dev_cycles` = primary execute (0 or 1) + post-review fixes (0..N).

Rules:
- increment **after** the subagent step completes successfully (not on retry);
- retry (max 1) does not increment again if the step was not counted as complete;
- on STOP at review limit — report accumulated `dev_cycles` in step 9.

## Step 0. `index_status`

Before all steps: `CallMcpTool` → `index_status` (server semantic-search-zvec-go). Criteria and markers — [reference.md](reference.md#semantic-search-context).

The orchestrator does not call `semantic_search`. Insert `semantic_search: …` into step 3–6 prompts only when search is available.

## Step 1. Input

- **Original Task** — verbatim into all subagents.
- **mode**: `implement` (default) | `review`
  - **`review`** when the user asks to review (keywords: «ревью», «review», «code review», «проверь», «провести ревью», …) or `mode: review`. **No step 2** — do not commit uncommitted changes before work.
  - **`implement`** — explicit `mode: implement` or task requires code changes.
- **Models**: `plan_model`, `dev_model`, `review_model` — default Composer; slugs and aliases — [reference.md](reference.md#models).

```
Task Progress:
- [ ] 0 index_status
- [ ] 1 input
- [ ] 2 snapshot / skip
- [ ] 3 plan / skip
- [ ] 4 execute / skip
- [ ] 5–6 review/fix (review: N/5, dev_cycles: M)
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

**Never run in `review` mode** — even if there are uncommitted changes. Go straight to step 5.

`implement` only: `git status` + `git diff` + `git log -3`; no changes → step 3.

Otherwise: stage (no secrets), commit in Russian — [reference.md](reference.md#commits). Hook fail → no amend, new commit or STOP.

## Step 3. Plan (`implement` only)

Task per table. Save `## Execution plan` → pass verbatim to step 4. Readonly; do not modify files.

## Step 4. Execute (`implement` only)

Task per table. Follow the plan; report deviations. Save report for step 9.

Pass `Dev cycle: 1` to the Execute prompt. After Execute completes → `dev_cycles += 1`.

## Step 5. Review

First step in `review`; in `implement` — after 4 and after each 6.

At launch → pass `<N> = review_cycles + 1` to the Review prompt. After Review completes → `review_cycles += 1`.

Task per table. Criteria: task complete, code quality, tests/linter.

Parse `## Verdict` / `## Errors` / `## Fix plan` — [reference.md](reference.md#verdict-format).

**Orchestrator rule (strict):** step 8 **only** when **both** are true:
1. `## Verdict` is `PASS` (not «conditional pass», «pass with notes», etc.)
2. `## Errors` is exactly `none` or empty — **any** listed item (critical / major / minor / info) → step 6

| Condition | → |
|-----------|---|
| Verdict `PASS` **and** Errors `none`/empty | step 8 |
| Verdict `FAIL`, or Errors has any item | step 6 |
| Verdict `PASS` but Errors not `none` | **step 6** (reviewer must not mix PASS + open errors) |
| Unrecognized format | FAIL; retry review with format reminder |

Review agent: open findings → `## Errors` + Verdict `FAIL`. Observations that need no fix → `## Notes` (orchestrator ignores for step 6/8).

**Cycle 5 ↔ 6:** until strict PASS, max 10 **review** cycles (`review_cycles`, step 5 runs). Limit reached → STOP without final commit. No commits between iterations.

## Step 6. Fix

Only on FAIL. Task per table. Fix listed errors only; do not commit. → step 5 (not 3–4).

At launch → pass `Dev cycle: <N>` where `<N> = dev_cycles + 1`. After Fix completes → `dev_cycles += 1`.

## Step 8. Final commit

Only after PASS. No changes → skip. Otherwise: stage, Russian message (why, not file list) — [reference.md](reference.md#commits). Hook handling — same as step 2.

## Step 9. Report

| Field | Value |
|-------|-------|
| Task | brief |
| Semantic search | on / on (indexing) / off |
| Mode, models | … |
| Snapshot, plan | hash / skip / n/a |
| dev_cycles | `N` (execute + fixes) |
| Outcome | PASS / STOP |
| Final commit | hash / skip |
| Files | from subagent reports |

## Safeguards

- **Review mode**: never step 2 (no pre-work snapshot commit), even with dirty tree.
- Semantic search: step 0 required; when `on` — [Subagent common](reference.md#subagent-common).
- Commits, secrets, hooks, models, retry, fix scope — as above.
- Bugbot (optional): 2+ critical in one area → suggest `/review-bugbot`.

## Examples

`/task-loop Add email validation` · `/task-loop mode: review Review uncommitted changes` · `/task-loop plan: gemini, dev: codex Refactor coordinator`
