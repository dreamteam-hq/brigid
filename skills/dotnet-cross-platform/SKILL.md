---
name: dotnet-cross-platform
description: Guides cross-platform .NET development by preferring framework APIs over shell commands and isolating OS-specific code in a single helper class. Load when writing code that must run on both macOS and Windows.
triggers:
  - cross-platform
  - cross platform
  - macOS Windows
  - platform specific
  - shelling out
  - Process.GetProcesses
  - IPGlobalProperties
  - OS specific code
  - portable code
version: "1.0.0"
---

# Cross-Platform Patterns

## Prefer .NET APIs over shelling out

Use `System.Diagnostics.Process` and `System.Net.NetworkInformation` before reaching for `ps`, `lsof`, `wmic`, or `netstat`. Only shell out when no .NET API exists.

| Need | .NET API | Don't use |
|------|----------|-----------|
| List processes | `Process.GetProcesses()` | `ps aux` |
| Process name | `Process.ProcessName` | `ps -o comm=` |
| Start time | `Process.StartTime` | `ps -o lstart=` |
| CPU time | `Process.TotalProcessorTime` | — |
| Memory | `Process.WorkingSet64` | — |
| Thread count | `Process.Threads.Count` | — |
| Port in use | `IPGlobalProperties.GetActiveTcpListeners()` | `lsof -i` |

## Isolate platform-specific code

When you must shell out, put ALL platform calls in a single `static class PlatformHelper` with:
- A `RuntimeInformation.IsOSPlatform()` check
- macOS and Windows branches
- A private `RunShell()` helper for process execution
- try/catch returning empty string on failure

This keeps platform-specific code to one place instead of scattered throughout.

## Things that still need platform calls

- **Command-line args of another process**: `ps -o args=` (macOS) / `wmic` (Windows)
- **Parent PID**: `ps -o ppid=` (macOS) / `wmic` (Windows)
- **Port listener details**: `lsof -i` (macOS) / `netstat -ano` (Windows)

## Process property access on macOS

`Process.StartTime`, `TotalProcessorTime`, and `WorkingSet64` may throw on macOS due to sandboxing or permissions. Always wrap in try/catch and show "N/A" on failure.
