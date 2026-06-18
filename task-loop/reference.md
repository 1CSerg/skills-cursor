# Reference: task-loop

## Models

| Slug | Display |
|------|---------|
| `composer-2.5-fast` | Composer (default) |
| `gemini-3.1-pro` | Gemini 3.1 Pro |
| `gpt-5.3-codex` | GPT-5.3 Codex |
| `gpt-5.5-medium` | GPT-5.5 Medium |
| `kimi-k2.5` | Kimi K2.5 |

Unknown model → warn user, use Composer.

| Alias | Slug |
|-------|------|
| `composer`, `composer-2.5` | `composer-2.5-fast` |
| `gemini`, `gemini-3.1` | `gemini-3.1-pro` |
| `codex`, `gpt-5.3` | `gpt-5.3-codex` |
| `gpt-5.5`, `medium` | `gpt-5.5-medium` |
| `kimi` | `kimi-k2.5` |

`plan: gemini`, `dev: codex`, `review: gemini` — or explicit `*_model` slugs. Default: all Composer.

---

## Subagent common

All templates below assume:

```text
Task: generalPurpose, run_in_background: false
Exploration: Prefer MCP semantic_search over broad grep; query, limit (no top_k).
```

Placeholder (only when search is available): `<semantic_search: on | on (indexing) | omit>`

---

## Semantic search context

`CallMcpTool` → `index_status` (server: semantic-search-zvec-go, args: `{}`). Read schema from MCP file system.

| available | Condition |
|-----------|-----------|
| true | success and (`zvec_open_ok` **or** `indexing.running` **or** `zvec_doc_count > 0`) |
| false | MCP/error/stub/empty index while idle |

| State | Prompt line |
|-------|-------------|
| idle | `semantic_search: on` |
| indexing | `semantic_search: on (indexing)` |
| false | omit |

---

## Verdict format

```markdown
## Verdict
PASS

## Errors
none

## Fix plan
none
```

FAIL (single-error example):

```markdown
## Verdict
FAIL

## Errors
1. [severity: critical] Description
   - Location: path/file.go:42
   - Evidence: test failed / incorrect logic
   - Fix: concrete action

## Fix plan
1. Fix … 2. Run go test ./...
```

`severity`: critical | major | minor.

---

## Execution plan format

```markdown
## Execution plan
### Approach
### Prerequisites
### Steps
### Files
### Tests
### Risks
```

Orchestrator passes the full block to Execute (step 4).

---

## Plan

Step 3, `plan_model`, readonly:

```text
Full Repository Path: <abs path>
Mode: implement
Original Task:
<verbatim>

<semantic_search: on | on (indexing) | omit>

Instructions:
Planning agent (read-only). Fulfill Original Task. Subagent common applies.
Do NOT modify files or commit. Minimize scope.
End with ## Execution plan (see Execution plan format).
```

---

## Execute

Step 4, `dev_model`:

```text
Full Repository Path: <abs path>
Mode: implement
Original Task:
<verbatim>

Execution plan:
<## Execution plan from step 3>

<semantic_search: on | on (indexing) | omit>

Instructions:
Follow Execution plan. Subagent common applies. No review, no commit.
Report: ## Execution report / Done / Files changed / Plan deviations / Blockers
```

---

## Review

Step 5, `review_model`, readonly:

```text
Full Repository Path: <abs path>
Mode: <implement|review>
Original Task:
<verbatim>

Review iteration: <N> of 5

<semantic_search: on | on (indexing) | omit>

Instructions:
Review agent (read-only). Subagent common applies.
Check: task done, code quality, tests/linter (failures = errors).
Scope: implement → git diff; review → scope from task.
Do NOT modify files. End with Verdict (see Verdict format).
```

---

## Fix

Step 6, `dev_model`:

```text
Full Repository Path: <abs path>
Mode: <implement|review>
Original Task:
<verbatim>

Review findings:
<## Errors + ## Fix plan from step 5>

<semantic_search: on | on (indexing) | omit>

Instructions:
Fix ONLY listed errors, Fix plan order. Subagent common applies. No commit.
Report: ## Fix report / Fixed / Files changed / Remaining issues
```

---

## Commits: HEREDOC

Subject + body — **Russian only**. Describe **why**, not a file list.

### Bash

```bash
git commit -m "$(cat <<'EOF'
снимок: подготовка к выполнению задачи

<описание>
EOF
)"
```

### PowerShell

```powershell
git commit -m @'
снимок: подготовка к выполнению задачи

<описание>
'@
```

| Step | Example subject (Russian) |
|------|---------------------------|
| Snapshot | `снимок: подготовка к выполнению задачи` |
| Final implement | `Добавить валидацию email в форму` |
| Final review+fixes | `Исправления по ревью: утечка в coordinator` |

---

## Bugbot (optional)

2+ critical findings in one area → suggest `/review-bugbot`. Does not replace step 5.
