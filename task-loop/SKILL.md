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

# Итеративное выполнение задач

Оркестратор: родительский агент **только координирует** субагентов — сам не пишет код, не ревьюит и не коммитит (кроме шагов 2 и 8).

Вызов скилла = явное разрешение на **начальный** и **финальный** коммит.

**Язык коммитов:** subject и body всех git-коммитов (шаги 2 и 8) — **обязательно на русском**, без исключений.

## Быстрый старт

0. **Сразу** вызвать MCP `index_status` (semantic-search-zvec-go) → однострочный маркер `semantic_search: on` / `on (indexing)` / off.
1. Распарсить вход (задача, mode, модели).
2. `implement`: снимок-коммит → plan-агент → dev-агент по плану → цикл ревью/фикса → финальный коммит → отчёт.
3. `review`: пропуск снимка, планирования и выполнения → цикл ревью/фикса → финальный коммит → отчёт.

Подробные шаблоны промптов и MCP: [reference.md](reference.md).

## Шаг 0. MCP `index_status` (первым делом)

**До** парсинга входа и любых других шагов оркестратор вызывает `index_status` MCP-сервера **semantic-search-zvec-go**.

1. Проверить схему инструмента в MCP file system (если доступен).
2. Вызвать `index_status` без аргументов через `CallMcpTool`.
3. По ответу определить доступность — см. [reference.md](reference.md#semantic-search-context).
4. Сформировать однострочный маркер и **включать в промпты субагентов** (шаги 3–6) только если поиск доступен.

| Результат | Маркер в промпте |
|-----------|------------------|
| Доступен, idle | `semantic_search: on` |
| Доступен, `indexing.running` | `semantic_search: on (indexing)` |
| Недоступен | **не вставлять** (pipeline продолжается) |

Оркестратор **сам** `semantic_search` не вызывает — только `index_status`. Субагенты используют `semantic_search`, если строка `on` присутствует.

## Шаг 1. Вход

### Обязательно

- **Original Task** — текст задачи дословно; передавать во все субагенты без сокращений.

### Режим (`mode`)

| Значение | Когда | Pipeline |
|----------|-------|----------|
| `implement` (default) | Реализация, рефакторинг, фикс, любая задача с изменением кода | 2 → 3 → 4 → 5 ↔ 6 → 8 → 9 |
| `review` | Первичная задача — ревью | **пропуск 2, 3 и 4** → 5 ↔ 6 → 8 → 9 |

**Автоопределение `review`**, если задача в основном про ревью и не просит менять код:
- ключевые слова: «ревью», «review», «code review», «проверь изменения», «провести ревью»;
- явный параметр: `mode: review` / `mode: implement` (приоритет над авто).

### Модели агентов

| Роль | Параметр | Default slug | Display |
|------|----------|--------------|---------|
| Планирование (шаг 3) | `plan_model` | `composer-2.5-fast` | Composer |
| Разработка (шаги 4, 6) | `dev_model` | `composer-2.5-fast` | Composer |
| Ревью (шаг 5) | `review_model` | `composer-2.5-fast` | Composer |

Допустимые slug — только из списка в [reference.md](reference.md). При неизвестной модели — сообщить пользователю и использовать Composer.

Парсинг алиасов: `plan: gemini`, `dev: codex`, `review: composer` — см. [reference.md](reference.md#модели).

Отслеживать прогресс чеклистом:

```
Task Progress:
- [ ] Шаг 0: index_status → semantic_search: on / off
- [ ] Шаг 1: вход распарсен
- [ ] Шаг 2: снимок-коммит (implement) / пропущен (review)
- [ ] Шаг 3: планирование (implement) / пропущен (review)
- [ ] Шаг 4: выполнение по плану (implement) / пропущен (review)
- [ ] Шаг 5–6: ревью/фикс (итерация N/5)
- [ ] Шаг 8: финальный коммит
- [ ] Шаг 9: отчёт
```

## Шаг 2. Снимок-коммит (только `implement`)

**Пропустить** в режиме `review`.

1. Параллельно: `git status`, `git diff`, `git log -3 --oneline`.
2. Нет изменений (чистое дерево) → пропуск, шаг 3 (планирование).
3. Иначе:
   - `git add` релевантные modified + untracked.
   - **Не** добавлять секреты (`.env`, `credentials.json`, `*.pem`, токены) — предупредить и исключить.
   - Сообщение **обязательно на русском** (subject + body):

     ```
     снимок: подготовка к выполнению задачи

     <краткое описание текущих незакоммиченных изменений>
     ```

   - Коммит через HEREDOC (PowerShell: here-string `@'...'@`).
4. **Hook failure**: не `git commit --amend`. Исправить причину → **новый** коммит. Если не удаётся — STOP с отчётом.

## Шаг 3. Plan-агент: планирование (только `implement`)

**Пропустить** в режиме `review`.

```
Task:
  subagent_type: generalPurpose
  readonly: true
  model: <plan_model>
  run_in_background: false
  description: "Plan task execution"
```

Промпт — шаблон `Plan` из [reference.md](reference.md#plan). Включить `semantic_search: on` или `on (indexing)`, если доступен.

Plan-агент **не изменяет файлы** — только исследует репозиторий и формирует план для dev-агента.

**Retry**: одна повторная попытка при падении субагента; затем STOP.

Сохранить полный блок `## Execution plan` из ответа — передать в шаг 4 дословно.

## Шаг 4. Dev-агент: выполнение по плану (только `implement`)

**Пропустить** в режиме `review`.

```
Task:
  subagent_type: generalPurpose
  readonly: false
  model: <dev_model>
  run_in_background: false
  description: "Execute task"
```

Промпт — шаблон `Execute` из [reference.md](reference.md#execute). Вложить `## Execution plan` из шага 3; при доступном поиске — строку `semantic_search: on` / `on (indexing)`.

Dev-агент следует плану; отклоняется только если план блокирует выполнение задачи — тогда указать в отчёте.

**Retry**: одна повторная попытка при падении субагента; затем STOP.

Сохранить отчёт субагента (файлы, блокеры) для финального отчёта.

## Шаг 5. Review-агент: ревью

Первый активный шаг в режиме `review`. В `implement` — после шага 4 и после каждого шага 6.

```
Task:
  subagent_type: generalPurpose
  readonly: true
  model: <review_model>
  run_in_background: false
  description: "Review task result"
```

Промпт — шаблон `Review` из [reference.md](reference.md#review). При доступном поиске — строку `semantic_search: on` / `on (indexing)`.

### Критерии ошибок

1. **Задача** — требования `Original Task` не закрыты или ревью неполное.
2. **Качество** — баги, регрессии, конвенции, edge cases.
3. **Тесты/линтер** — запустить применимые команды репозитория; падения = ошибки.

### Парсинг ответа

Оркестратор читает блоки `## Verdict`, `## Errors`, `## Fix plan` (формат в [reference.md](reference.md#формат-вердикта)).

| Условие | Действие |
|---------|----------|
| `Verdict: PASS` или пустой `Errors` | → шаг 8 |
| `Verdict: FAIL` + непустой `Errors` | → шаг 6 |
| Нет распознаваемого формата | Считать FAIL; одна retry ревью с напоминанием о формате |

**Retry**: одна повторная попытка при падении субагента; затем STOP.

## Шаг 6. Dev-агент: исправление

Только при `Verdict: FAIL` с непустым `Errors`.

```
Task:
  subagent_type: generalPurpose
  readonly: false
  model: <dev_model>
  run_in_background: false
  description: "Fix review findings"
```

Промпт — шаблон `Fix` из [reference.md](reference.md#fix). При доступном поиске — строку `semantic_search: on` / `on (indexing)`.

Исправить **только** перечисленные ошибки; не расширять scope; не коммитить.

После исправления → **шаг 5** (не шаги 3 и 4 — план и выполнение не повторяются).

**Retry**: одна повторная попытка при падении; затем STOP.

## Шаг 7. Цикл 5 ↔ 6

- Повторять до `Verdict: PASS`.
- **Максимум 5** итераций ревью (считать каждый запуск шага 5).
- При исчерпании лимита — STOP: перечислить нерешённые `Errors`, не делать финальный коммит успеха.
- Между итерациями **нет** коммитов (только шаги 2 и 8).

## Шаг 8. Финальный коммит (после PASS)

Оба режима. Только если workflow завершился с `Verdict: PASS` (не STOP).

1. `git status`, `git diff`.
2. Нет изменений → пропуск (нормально для `review` без фиксов).
3. Иначе:
   - Stage релевантных изменений; исключить секреты.
   - Сообщение **обязательно на русском** — отражает **зачем**, не список файлов:
     - `implement`: отразить исходную задачу.
     - `review` с фиксами: «Исправления по результатам ревью: …».
   - HEREDOC; hook failure — как в шаге 2.

## Шаг 9. Финальный отчёт

Кратко сообщить пользователю:

| Поле | Содержание |
|------|------------|
| Задача | `Original Task` (кратко) |
| Semantic search | `on` / `on (indexing)` / `off` |
| Mode | `implement` / `review` |
| Модели | `plan_model`, `dev_model`, `review_model` |
| Снимок | hash / пропущен / не применимо |
| План | выполнен (шаг 3) / не применимо |
| Итерации | число циклов 5↔6 |
| Итог | PASS / STOP (+ причина) |
| Финальный коммит | hash / пропущен |
| Файлы | затронутые пути из отчётов субагентов |

## Safeguards

- **Semantic search**: шаг 0 обязателен; при `on` — prefer `semantic_search` (см. reference).
- **Коммиты**: subject и body — **только на русском**; не использовать английский, даже если репозиторий или код на английском.
- **Секреты**: никогда не коммитить `.env`, credentials, ключи; предупредить при обнаружении.
- **Hooks**: при отклонении коммита — исправить и новый коммит, не amend.
- **Модели**: только slug из reference; недоступная модель → Composer + предупреждение.
- **Субагенты**: max 1 retry на шаг; не запускать fix без FAIL.
- **Scope**: fix-агент не добавляет фичи вне `Fix plan`.
- **Bugbot** (опционально): при повторяющихся critical findings можно эскалировать через `/review-bugbot` — не часть основного flow.

## Примеры вызова

**Реализация (default):**
```
/task-loop Добавить валидацию email в форму регистрации
```

**Ревью:**
```
/task-loop mode: review Провести ревью незакоммиченных изменений
```

**С моделями:**
```
/task-loop plan: gemini, dev: codex Рефакторинг coordinator.go
```
