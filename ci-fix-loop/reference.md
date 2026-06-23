# Reference: ci-fix-loop

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

`plan: gemini`, `fix: codex` — or explicit `plan_model` / `fix_model` slugs. Default: Composer.

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

## CI fix plan format

```markdown
## CI Fix Plan

### Failures
1. [source: local|github] Job/check name
   - Evidence: log excerpt or test output
   - Root cause: …

### Fix steps
1. …
2. …

### Files
- path/to/file.go — change …

### Local verify
- go test ./internal/...
```

Orchestrator passes the full block to Fix (step 2).

---

## Plan

Step 1, `plan_model`, readonly:

```text
Full Repository Path: <abs path>
Iteration: <N> of 20
Branch: <branch>
PR: <number|none>

Failure context:
<local gate output + gh pr checks + log-failed excerpts>

<semantic_search: on | on (indexing) | omit>

Instructions:
Planning agent (read-only). Find GitHub/local CI build errors and plan fixes.
Subagent common applies. Do NOT modify files or commit. Minimize scope.
Do NOT propose weakening CI or editing .github/workflows/* to pass.
End with ## CI Fix Plan (see CI fix plan format).
```

---

## Fix

Step 2, `fix_model`:

```text
Full Repository Path: <abs path>
Iteration: <N> of 20
Branch: <branch>
PR: <number|none>

CI Fix Plan:
<## CI Fix Plan from step 1>

<semantic_search: on | on (indexing) | omit>

Instructions:
Fix ONLY per CI Fix Plan / Fix steps order. Subagent common applies.
Do NOT edit .github/workflows/* unless plan explicitly requires user-approved workflow change.
After fixes: commit in Russian (why, not file list) — see Commits. Do NOT push.
Report: ## Fix report / Fixed / Files changed / Commits / Blockers
```

---

## ci-investigator

Optional parallel subagent per failed GitHub check:

```text
Full Repository Path: <abs path>
Diff: branch changes
Change Description:
<brief summary of branch vs base>

Custom Instructions:
Investigate failed check: <check name>. Return root cause and suggested fix (no file edits).
```

`subagent_type: ci-investigator`, `readonly: true`.

Merge investigator summaries into step 1 Plan prompt as extra failure context.

---

## Local CI gate

Default commands (CI job `test` + `lint` from `.github/workflows/ci.yml`). Override via user `Local CI:` input.

```bash
go build -v ./...
go test -v -race -count=1 ./...
COVERAGE_MIN=80 COVERAGE_PKG_MIN=50 COVERAGE_PACKAGES="./internal/..." bash scripts/dev/check-coverage.sh
go vet ./...
make lint
```

If `make lint` unavailable: `golangci-lint run ./...`

Windows: run via Git Bash where scripts require bash; `go build` / `go test` / `go vet` work in PowerShell.

Orchestrator runs gate after step 2 and in preflight. Stop on first failing command; capture output for next Plan iteration.

---

## GitHub wait

After successful local gate and push:

```bash
# Preferred (PR open)
gh pr checks --watch

# No PR or need specific run
gh run list --branch <branch> --limit 1 --json databaseId,status,conclusion
gh run watch <run-id> --exit-status
```

On failure: `gh run view <run-id> --log-failed` → feed into next step 1.

---

## Commits: HEREDOC

Subject + body — **Russian only**. Describe **why**, not a file list.

### Bash

```bash
git commit -m "$(cat <<'EOF'
исправление CI: <кратко почему>

<описание>
EOF
)"
```

### PowerShell

```powershell
git commit -m @'
исправление CI: <кратко почему>

<описание>
'@
```

| Context | Example subject (Russian) |
|---------|---------------------------|
| Test fix | `исправление CI: падение TestFoo при race` |
| Coverage | `исправление CI: покрытие пакета chunk ниже 80%` |
| Lint | `исправление CI: golangci-lint unused в service` |

Hook fail → no amend; fix and new commit or STOP.

Push (orchestrator after local gate):

```bash
git push
# or: git push -u origin HEAD
```
