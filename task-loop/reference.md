# Справочник: task-loop

## Модели

### Допустимые slug

| Slug | Display name |
|------|--------------|
| `composer-2.5-fast` | Composer (default) |
| `gemini-3.1-pro` | Gemini 3.1 Pro |
| `gpt-5.3-codex` | GPT-5.3 Codex |
| `gpt-5.5-medium` | GPT-5.5 Medium |
| `kimi-k2.5` | Kimi K2.5 |

Если пользователь запросил модель вне списка — сообщить о недоступности и использовать `composer-2.5-fast`.

### Алиасы в сообщении пользователя

Оркестратор нормализует (регистронезависимо):

| Алиас | Slug |
|-------|------|
| `composer`, `composer-2.5`, `composer-2.5-fast` | `composer-2.5-fast` |
| `gemini`, `gemini-3.1`, `gemini-3.1-pro` | `gemini-3.1-pro` |
| `codex`, `gpt-5.3`, `gpt-5.3-codex` | `gpt-5.3-codex` |
| `gpt-5.5`, `gpt-5.5-medium`, `medium` | `gpt-5.5-medium` |
| `kimi`, `kimi-k2.5` | `kimi-k2.5` |

Синтаксис:

- `plan: gemini` → `plan_model: gemini-3.1-pro`
- `dev: codex` → `dev_model: gpt-5.3-codex`
- `review: gemini` → `review_model: gemini-3.1-pro`
- `plan_model: composer-2.5-fast, dev_model: codex, review_model: kimi` — явные slug

Не указано → все три `composer-2.5-fast`.

---

## Semantic search context

### Шаг 0: вызов `index_status`

Оркестратор вызывает MCP **до всех остальных шагов**:

```
CallMcpTool:
  server: <имя сервера semantic-search-zvec-go в проекте, см. .cursor/mcp.json или MCP file system>
  toolName: index_status
  arguments: {}
```

Сначала прочитать схему `index_status.json` в MCP file system.

### Критерии доступности

| `available` | Условие |
|-------------|---------|
| `true` | Вызов успешен и индекс пригоден для поиска: `zvec_open_ok: true` **или** `indexing.running: true` **или** `zvec_doc_count > 0` |
| `false` | MCP не подключён, tool error, `zvec_open_ok: false` при idle и пустом индексе, stub-сборка без поиска |

**Индексация в процессе** (`indexing.running: true`) → `available: true`.

### Строка для промптов субагентов

Одна строка, **только если** `available: true`. Иначе — не вставлять.

| Состояние | Строка |
|-----------|--------|
| Доступен, idle | `semantic_search: on` |
| Доступен, индексация | `semantic_search: on (indexing)` |
| Недоступен | omit |

Правило для шаблонов Plan / Execute / Review / Fix (одна фраза в Instructions):

```text
Prefer MCP semantic_search over broad grep; params: query, limit (no top_k).
```

---

## Формат вердикта

Review-агент **обязан** завершить ответ этими блоками (оркестратор парсит их):

```markdown
## Verdict
PASS

## Errors
none

## Fix plan
none
```

При находках:

```markdown
## Verdict
FAIL

## Errors

1. [severity: critical] Описание проблемы
   - Location: path/to/file.go:42
   - Evidence: что наблюдено (тест упал, логика неверна, …)
   - Fix: конкретное действие для dev-агента

2. [severity: major] …

## Fix plan

1. Сначала исправить … (файл X)
2. Затем добавить тест …
3. Прогнать `go test ./...`
```

Правила:

- `severity`: `critical` | `major` | `minor`
- При `PASS`: `Errors` = `none` или пустой список
- `Fix plan` — упорядоченные шаги только при `FAIL`

---

## Формат плана

Plan-агент **обязан** завершить ответ блоком `## Execution plan`:

```markdown
## Execution plan

### Approach
Краткий подход (2–4 предложения).

### Prerequisites
- что проверить / прочитать перед правками (или none)

### Steps
1. Конкретное действие (файл, функция, тест)
2. …

### Files
- path/to/file — что изменить

### Tests
- команды для проверки после выполнения

### Risks
- edge cases и ограничения (или none)
```

Оркестратор передаёт весь блок `## Execution plan` в промпт Execute (шаг 4).

---

## Plan

Шаблон промпта для шага 3 (`plan_model`, `readonly: true`):

```text
Full Repository Path: <absolute path to repo root>
Mode: implement
Original Task:
<дословный текст задачи от пользователя>

<semantic_search: on | on (indexing) — если доступен; иначе omit>

Instructions:
You are the planning agent (read-only). Design how to fulfill the Original Task.

- Explore the repository as needed. Prefer MCP semantic_search over broad grep; params: query, limit (no top_k).
- Do NOT modify files or commit.
- Minimize scope; follow existing conventions.
- Produce an actionable plan for the dev agent to execute in one pass.

End with the mandatory Execution plan format:

## Execution plan
### Approach
### Prerequisites
### Steps
(numbered, specific)
### Files
### Tests
### Risks
```

---

## Execute

Шаблон промпта для шага 4 (`dev_model`, `readonly: false`):

```text
Full Repository Path: <absolute path to repo root>
Mode: implement
Original Task:
<дословный текст задачи от пользователя>

Execution plan (follow this):
<вставить полный блок ## Execution plan из шага 3>

<semantic_search: on | on (indexing) — если доступен; иначе omit>

Instructions:
- Execute the Original Task by following the Execution plan step by step.
- Prefer MCP semantic_search over broad grep; params: query, limit (no top_k).
- Follow existing code conventions and minimize scope.
- Do NOT run a review pass or commit changes.
- Deviate from the plan only if a step is blocked — explain in the report.
- Run applicable tests/linters from the plan (and repo standards).
- Return a structured report:

## Execution report
### Done
- bullet list of what was implemented

### Files changed
- path/to/file (brief note)

### Plan deviations
- none | what differed from the plan and why

### Blockers
- none | description of anything unfinished
```

---

## Review

Шаблон промпта для шага 5 (`review_model`, `readonly: true`):

```text
Full Repository Path: <absolute path to repo root>
Mode: <implement|review>
Original Task:
<дословный текст задачи>

Review iteration: <N> of 5

<semantic_search: on | on (indexing) — если доступен; иначе omit>

Instructions:
You are the review agent (read-only). Evaluate work against the Original Task.
- Prefer MCP semantic_search over broad grep; params: query, limit (no top_k).

Check ALL of:
1. Task completion — are all requirements from Original Task met?
2. Code quality — bugs, regressions, conventions, edge cases.
3. Tests and linter — discover and run applicable repo commands
   (e.g. go test ./..., make test, go vet ./..., npm test).
   Failures count as errors.

Compare against:
- For mode=implement: changes made to fulfill the task (git diff, recent edits).
- For mode=review: the scope described in Original Task (branch changes,
  uncommitted changes, or paths named in the task).

Do NOT modify files. End with the mandatory Verdict format (see below).

## Verdict
PASS | FAIL

## Errors
(none or numbered list with severity, Location, Evidence, Fix)

## Fix plan
(none or ordered steps)
```

---

## Fix

Шаблон промпта для шага 6 (`dev_model`, `readonly: false`):

```text
Full Repository Path: <absolute path to repo root>
Mode: <implement|review>
Original Task:
<дословный текст задачи>

Review findings to fix:

<вставить полные блоки ## Errors и ## Fix plan из шага 5>

<semantic_search: on | on (indexing) — если доступен; иначе omit>

Instructions:
- Fix ONLY the listed errors, in the order of Fix plan.
- Prefer MCP semantic_search over broad grep; params: query, limit (no top_k).
- Do NOT expand scope beyond the review findings.
- Do NOT commit changes.
- Run applicable tests/linters to verify fixes.
- Return:

## Fix report
### Fixed
- bullet per resolved error

### Files changed
- path (what changed)

### Remaining issues
- none | anything you could not fix
```

---

## Коммиты: HEREDOC

**Обязательно:** subject и body — на **русском языке**. Описание отражает **зачем**, не перечень файлов.

### Bash

```bash
git commit -m "$(cat <<'EOF'
снимок: подготовка к выполнению задачи

Краткое описание изменений.
EOF
)"
```

### PowerShell

```powershell
git commit -m @'
снимок: подготовка к выполнению задачи

Краткое описание изменений.
'@
```

Финальный коммит — тот же формат и язык (русский); subject отражает выполненную задачу.

### Примеры subject

| Шаг | Пример |
|-----|--------|
| Снимок (шаг 2) | `снимок: подготовка к выполнению задачи` |
| Финал, implement | `Добавить валидацию email в форму регистрации` |
| Финал, review+фиксы | `Исправления по результатам ревью: утечка в coordinator` |

---

## Опциональная эскалация: Bugbot

Если после 2+ итераций остаются `critical` findings по одной области — оркестратор может предложить пользователю `/review-bugbot` для второго мнения. Не заменяет шаг 5.
