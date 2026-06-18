#Requires -Version 5.1
<#
.SYNOPSIS
  Связывает скиллы из этого репозитория с ~/.cursor/skills/

.DESCRIPTION
  Для каждой подпапки с SKILL.md создаёт symlink (или junction) в
  %USERPROFILE%\.cursor\skills\<name> -> <repo>\<name>

  Повторный запуск обновляет ссылки. Существующие каталоги/ссылки с тем же
  именем удаляются перед созданием новой ссылки.

.EXAMPLE
  .\install.ps1
  .\install.ps1 -RepoRoot "D:\path\to\Skills\Cursor"
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$CursorSkills = Join-Path $env:USERPROFILE '.cursor\skills'

if (-not (Test-Path -LiteralPath $CursorSkills)) {
    New-Item -ItemType Directory -Path $CursorSkills -Force | Out-Null
}

function Remove-LinkOrDirectory {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Remove-Item -LiteralPath $Path -Force
    } else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function New-SkillLink {
    param(
        [string] $Source,
        [string] $Destination
    )
    Remove-LinkOrDirectory -Path $Destination
    try {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $Source | Out-Null
        return 'SymbolicLink'
    } catch {
        New-Item -ItemType Junction -Path $Destination -Target $Source | Out-Null
        return 'Junction'
    }
}

$linked = @()
Get-ChildItem -LiteralPath $RepoRoot -Directory | ForEach-Object {
    $skillFile = Join-Path $_.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillFile)) { return }

    $dest = Join-Path $CursorSkills $_.Name
    $linkType = New-SkillLink -Source $_.FullName -Destination $dest
    $linked += [PSCustomObject]@{
        Name = $_.Name
        Source = $_.FullName
        Destination = $dest
        LinkType = $linkType
    }
}

if ($linked.Count -eq 0) {
    Write-Warning "В $RepoRoot не найдено папок со SKILL.md"
    exit 1
}

Write-Host "Установлено скиллов: $($linked.Count)"
$linked | Format-Table Name, LinkType, Destination -AutoSize
Write-Host ""
Write-Host "Источник: $RepoRoot"
Write-Host "Цель:     $CursorSkills"
Write-Host "Перезапустите Cursor, если скилл не появился сразу."
