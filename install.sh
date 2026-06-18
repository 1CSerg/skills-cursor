#!/usr/bin/env bash
# Связывает скиллы из этого репозитория с ~/.cursor/skills/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURSOR_SKILLS="${HOME}/.cursor/skills"

mkdir -p "$CURSOR_SKILLS"

linked=0
for dir in "$REPO_ROOT"/*/; do
  [[ -f "${dir}SKILL.md" ]] || continue
  name="$(basename "$dir")"
  dest="${CURSOR_SKILLS}/${name}"
  ln -sfn "$dir" "$dest"
  echo "linked: $name -> $dest"
  linked=$((linked + 1))
done

if [[ "$linked" -eq 0 ]]; then
  echo "warning: no SKILL.md directories found in $REPO_ROOT" >&2
  exit 1
fi

echo ""
echo "installed: $linked skill(s)"
echo "source:    $REPO_ROOT"
echo "target:    $CURSOR_SKILLS"
echo "restart Cursor if skills do not appear immediately"
