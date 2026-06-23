---
name: ci-fix-loop
description: >-
  Orchestrates GitHub CI fixes in a plan-fix-wait loop via subagents: readonly
  plan, implement fixes, local CI gate, push, gh checks watch; max 20 iterations.
  Use when CI is red, GitHub Actions failed, or user invokes /ci-fix-loop.
disable-model-invocation: true
---

# CI fix loop

The orchestrator **only coordinates** subagents — it does not write code or run fixes itself.

**Commits and push:** invoking this skill = permission to commit (Russian messages) and `git push` after local gate passes. Templates: [reference.md](reference.md).

## Quick start

0. `index_status` → `semantic_search: on` / `on (indexing)` / off
1. Preflight: branch, PR, failed checks, local gate
2. Loop (max 20): plan → fix → local gate → push → GitHub wait
3. Report

```
Task Progress:
- [ ] 0 index_status
- [ ] Preflight
- [ ] Loop iteration N/20
  - [ ] 1 Plan subagent
  - [ ] 2 Fix subagent
  - [ ] Local CI gate
  - [ ] Push (if ahead)
  - [ ] 3 GitHub CI wait
- [ ] Report
```

## Step 0. `index_status`

Before all steps: `CallMcpTool` → `index_status` (server semantic-search-zvec-go). Criteria — [reference.md](reference.md#semantic-search-context).

The orchestrator does not call `semantic_search`. Insert `semantic_search: …` into step 1–2 prompts only when search is available.

## Input

Optional overrides from user message:

- **PR** — number or URL (default: current branch PR via `gh pr view`)
- **Local CI:** — custom command list (default: [reference.md](reference.md#local-ci-gate))
- **fix_model** — default Composer; slugs — [reference.md](reference.md#models)

## Preflight (orchestrator)

1. Context: `git branch --show-current`; `gh pr view --json number,url,headRefName,baseRefName` (no PR → work on branch push).
2. Collect failures:
   - **GitHub:** `gh pr checks` or `gh run list --branch … --limit 5`; `gh run view --log-failed` for failed jobs.
   - **Local gate:** run default commands — [reference.md](reference.md#local-ci-gate).
3. If no local **and** no GitHub failures → **SUCCESS**, skip loop.

Save failure summaries for step 1 prompts.

## Main loop (max 20 iterations)

Continue while CI failures exist. Count each full pass through steps 1–3.

1. **Запуск субагента в режиме план** — поиск ошибок сборки git и план их исправления.
2. **Запуск субагента для исправления** ошибок сборки.
3. **Подождать завершения сборки git.** Если есть ошибки — перейти на шаг 1.

**Mode both** (orchestrator between steps 2 and 3):

| After step | Action |
|------------|--------|
| 2 Fix | **Local CI gate** — rerun gate commands. Fail → step 1, **no push**. |
| Local pass | **Push** if commits ahead of remote (`git push`). |
| Push / existing commits | **GitHub wait** — `gh pr checks --watch` or `gh run watch` — [reference.md](reference.md#github-wait). |
| GitHub fail | → step 1 |
| GitHub pass | → Report SUCCESS |

Iteration limit (20) reached with failures → STOP and report.

## Subagents

Common: `run_in_background: false`. **Retry: max 1 per step → STOP.**

| Step | description | subagent_type | readonly | model | Prompt |
|------|-------------|---------------|----------|-------|--------|
| 1 Plan | Plan CI fixes | generalPurpose | true | plan_model | [Plan](reference.md#plan) |
| 2 Fix | Fix CI errors | generalPurpose | false | fix_model | [Fix](reference.md#fix) |

Optional before step 1: parallel `ci-investigator` per failed GitHub check — [reference.md](reference.md#ci-investigator).

+ `semantic_search: on` / `on (indexing)` when available.

## Step 1. Plan

Task per table. Parse and save `## CI Fix Plan` — pass verbatim to step 2. Readonly; do not modify files.

Required plan sections — [reference.md](reference.md#ci-fix-plan-format).

## Step 2. Fix

Task per table. Follow plan only. Commit after fixes (Russian, why not file list) — [reference.md](reference.md#commits). Hook fail → no amend, new commit or STOP. Do **not** push — orchestrator pushes after local gate.

Report: `## Fix report` / Fixed / Files changed / Commits / Blockers.

## Step 3. GitHub CI wait

Orchestrator only (not a subagent):

```bash
gh pr checks --watch
# or: gh run watch <run-id> --exit-status
```

Re-check `gh pr checks` / failed logs. Any failure → next iteration step 1.

## Report

| Field | Value |
|-------|-------|
| Branch / PR | … |
| Semantic search | on / on (indexing) / off |
| Iterations | N / 20 |
| Commits | hashes |
| Local gate | pass / fail (last) |
| GitHub checks | URL, pass / fail |
| Outcome | SUCCESS / STOP |

## Safeguards

- Fix only errors in PR/branch scope; **never** weaken CI or edit `.github/workflows/*` just to pass.
- Unrelated failures → check branch behind base (`git fetch` + merge/rebase `origin/main`) before hacks.
- No secrets in commits; respect pre-commit hooks.
- Full CI matrix (zvec/treesitter/windows) runs on GitHub only — local gate is stub job + lint.
- Orchestrator does not implement fixes — delegate to subagents.

## Examples

`/ci-fix-loop` · `/ci-fix-loop PR #42` · `/ci-fix-loop fix: codex`
