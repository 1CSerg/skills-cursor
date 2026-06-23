# Cursor Skills

[Agent Skills](https://cursor.com/docs) для Cursor IDE: хранятся в Git, подключаются симлинками в `~/.cursor/skills/`.

## Структура

```
Cursor/
├── install.ps1              # Windows
├── install.sh               # Linux / macOS
├── task-loop/
│   ├── SKILL.md
│   └── reference.md
├── ci-fix-loop/
│   ├── SKILL.md
│   └── reference.md
└── README.md
```

Каждая подпапка с `SKILL.md` — отдельный скилл. Имя папки = идентификатор в Cursor.

## Установка

### Windows

```powershell
cd D:\path\to\Skills\Cursor
.\install.ps1
```

Скрипт создаёт symlink (или junction, если symlink недоступен) для каждого скилла:

`%USERPROFILE%\.cursor\skills\<skill-name>` → `<repo>\<skill-name>`

### Linux / macOS

```bash
cd ~/path/to/Skills/Cursor
chmod +x install.sh
./install.sh
```

### Новая машина

1. `git clone <url> Skills/Cursor`
2. Запустить `install.ps1` или `install.sh`
3. Перезапустить Cursor

## Обновление скиллов

```bash
git pull
# повторить install.ps1 / install.sh при добавлении новых папок
```

Редактируйте файлы в этом репозитории — Cursor читает их через ссылку, отдельное копирование не нужно.

## Скиллы

| Скилл | Описание |
|-------|----------|
| [task-loop](task-loop/SKILL.md) | Итеративное выполнение задач: index_status → снимок → план → реализация → ревью → исправления → коммит |
| [ci-fix-loop](ci-fix-loop/SKILL.md) | Цикл починки CI: план → исправление → локальная проверка → push → ожидание GitHub checks (до 20 итераций) |

**Вызов:** `/task-loop <задача>` · `/ci-fix-loop` — или прикрепите скилл к сообщению.

## Добавление нового скилла

1. Создать папку `my-skill/` с `SKILL.md` (frontmatter: `name`, `description`).
2. Запустить install-скрипт.
3. Закоммитить в этот репозиторий.

Не использовать `~/.cursor/skills-cursor/` — зарезервировано Cursor.

## Удаление

```powershell
Remove-Item "$env:USERPROFILE\.cursor\skills\task-loop" -Force
# для symlink/junction; для обычной папки добавьте -Recurse
```

Файлы в репозитории останутся; при необходимости снова запустите `install.ps1`.
