# defect-scan on Windows

defect-scan runs on Windows. Pick the path that matches your shell:

| Your shell | How to run |
|---|---|
| **WSL** or **Git-Bash** (recommended) | Use defect-scan exactly as on macOS/Linux — it's a POSIX-sh tool. |
| **Native PowerShell / cmd** | Use the fallback shim: `windows/defect-scan.ps1` |

## Why there's no separate native engine

defect-scan's whole engine is one POSIX shell library (`skills/scan/lib/detect.sh`).
Maintaining a second PowerShell reimplementation would double the surface and let the
two drift — the exact failure mode we warn about between the Claude and Codex
harnesses. Instead, the PowerShell fallback **delegates** to that one engine via the
`bash` that ships with Git for Windows.

This is safe to rely on because **every defect-scan subcommand needs `git`**, and Git
for Windows bundles `bash`. So if you can run defect-scan at all (you have git), you
have a POSIX shell for it to use.

## PowerShell fallback

```powershell
# From a checkout of defect-scan:
./windows/defect-scan.ps1 preflight          # verify tools are present
./windows/defect-scan.ps1 stacks .
./windows/defect-scan.ps1 scope "" --full .
```

The shim locates `bash` in this order: `bash` on `PATH` → Git for Windows
(`%ProgramFiles%\Git\bin\bash.exe`) → WSL. If none is found it tells you to install
Git for Windows (`winget install Git.Git`). Arguments pass straight through to
`detect.sh`, so behavior is identical to every other platform.

> The Claude Code / Codex skill invocations call `detect.sh` directly. This shim is
> only for driving the deterministic plumbing from a native Windows shell.

> **WSL caveat:** when the shim falls through to WSL, only the script path is
> translated (`wslpath`); a path-valued *argument* you pass (e.g. an absolute
> `C:\...` scan target) is **not** translated and would reach `detect.sh` as a
> Windows path. The shim is best-effort for cwd-relative use under WSL — for absolute
> Windows paths, prefer Git-Bash (no translation needed) or run from inside WSL.
