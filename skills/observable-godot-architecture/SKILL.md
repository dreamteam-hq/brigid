---
name: ObservableGodot Architecture
description: ObservableGodot project reference — C++ GDExtension interceptors, .NET data fabric, Parquet output, three-tier pipeline
triggers:
  - ObservableGodot
  - observable godot
  - telemetry
  - packet capture
  - RPC capture
category: gamedev
---

# ObservableGodot Architecture

## What it does

Captures every RPC call and network packet in Godot multiplayer games with zero game code changes.
Three-tier pipeline: **C++ GDExtension interceptors** → **.NET 10 data fabric** → **Parquet files**.

## Module inventory

| Directory | Purpose |
|---|---|
| `extensions/` | C++ interceptors for SceneMultiplayer, ENetConnection |
| `capture/` | C# data fabric — ringbuffer, columnar writer |
| `games/` | Test games |
| `analysis/` | Jupyter + Altair + Quarto |
| `netcode-explorer/` | Blazor dashboard + DuckDB.NET |

## Key files

- **telemetry_abi.h** — C-ABI contract (ABI v2). Do not modify without approval.
- **extension_api.4.6.1.json** — Godot API surface. Only trusted source for API signatures.
- **GODOT_API_NOTES.md** — Confirmed signatures and usage notes.
- **project-learnings.md** — API quirks and workarounds.
- **CHANGELOG.md** — Append-only architectural decisions.

## Build commands

```bash
# .NET build
dotnet build
dotnet build -c Release
dotnet build -p:SkipNativeBuild=true

# C++ extensions
cd extensions && python3 -m SCons platform=macos target=template_debug arch=arm64

# Analysis / dashboard
scripts/jupyter.sh
scripts/netcode-explorer.sh
```

## Do not do

- Push to KervanaLLC repos.
- Cross tier boundaries (C++ ↔ .NET ↔ analysis).
- Modify `telemetry_abi.h` without approval.
- Use API signatures from sources other than `extension_api.json`.
- Use Parquet.Net v4 POCO API.
- Block on the hot path.
