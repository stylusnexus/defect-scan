#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Windows/PowerShell fallback for defect-scan.

.DESCRIPTION
  defect-scan's engine is one POSIX-sh library (skills/scan/lib/detect.sh). Rather
  than maintain a second, divergent implementation, this fallback runs that engine
  through the POSIX shell that Windows developers already have.

  Why a delegating shim (not a native rewrite): every defect-scan subcommand shells
  out to `git`, and Git for Windows bundles `bash`. So "has git but no bash" is
  effectively impossible — and the tool needs git regardless. Delegating keeps a
  single source of truth and guarantees identical behavior across platforms.

.EXAMPLE
  ./windows/defect-scan.ps1 stacks .
  ./windows/defect-scan.ps1 scope "" --full .
#>
[CmdletBinding()]
param(
  # Not named $Args — that shadows PowerShell's automatic variable (PSScriptAnalyzer
  # PSAvoidAssignmentToAutomaticVariable). These are the subcommand + flags to pass
  # straight through to detect.sh.
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Passthru
)

$ErrorActionPreference = 'Stop'

# Resolve detect.sh relative to this script (works regardless of caller's cwd).
$detect = Join-Path $PSScriptRoot '..\skills\scan\lib\detect.sh'
if (-not (Test-Path $detect)) {
  Write-Error "defect-scan: cannot find detect.sh at $detect"
  exit 1
}

# Locate a POSIX bash, in order of preference.
function Find-Bash {
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }                      # bash already on PATH (Git-Bash/MSYS/WSL shim)
  foreach ($p in @(
      "$env:ProgramFiles\Git\bin\bash.exe",
      "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
      "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
    if ($p -and (Test-Path $p)) { return $p }            # Git for Windows
  }
  if (Get-Command wsl -ErrorAction SilentlyContinue) { return 'wsl' }  # WSL fallback
  return $null
}

$bash = Find-Bash
if (-not $bash) {
  Write-Error @"
defect-scan: no POSIX shell found.
Install Git for Windows (bundles Git-Bash) or enable WSL, then re-run.
  winget install Git.Git      # or: https://git-scm.com/download/win
defect-scan delegates to that bash; there is no separate native engine to install.
"@
  exit 1
}

# Delegate to the shared engine. `bash <script> <args...>` runs identically to the
# Claude/Codex harness invocations on macOS/Linux.
if ($bash -eq 'wsl') {
  & wsl bash (& wsl wslpath -a $detect) @Passthru
} else {
  & $bash $detect @Passthru
}
exit $LASTEXITCODE
