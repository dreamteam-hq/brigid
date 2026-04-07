---
name: GDExtension C# Interop
description: GDExtension C++ to C# interop via C-ABI — managed/native boundary, extension_api.json, ObservableGodot tier architecture
triggers:
  - GDExtension
  - gdextension
  - C-ABI
  - native interop
  - ObservableGodot
  - C++ interop
  - managed native
  - telemetry_abi
category: gamedev
version: "1.0.0"
---

# GDExtension C++ <-> C# Interop — ObservableGodot

## Three-Tier Architecture

| Tier | Language | Directory | Role |
|------|----------|-----------|------|
| 1 | C++20 | `extensions/` | GDExtension interceptors — hook engine calls |
| 2 | .NET 10 / C# 14 | `capture/` | Data fabric — receives telemetry via C-ABI |
| 3 | Python 3.12 | `analysis/` | Analysis notebooks (Jupyter) |

C-ABI is the **sole** Tier 1 <-> Tier 2 contract. There is no other communication path.

## Tier Boundary Rules (Inviolable)

- C++ must **never** reference managed types.
- C# must **never** dereference a C++ pointer beyond `[UnmanagedCallersOnly]` entry points.
- No GC-observable state crosses the ABI.
- Interceptors must be **transparent** — always delegate to the wrapped engine implementation.

Violating any of these rules will cause undefined behavior or GC corruption.

## C-ABI Contract

- Defined in `telemetry_abi.h`.
- Payload structs:
  - `RpcEventPayload` — 72 bytes
  - `PacketEventPayload` — 64 bytes
- **Do NOT modify without explicit approval.** The ABI is version-stamped.
- All fields are fixed-size, blittable, no pointers to managed memory.

## extension_api.json

- Godot **4.6.1** API surface.
- **Authoritative source** for virtual method signatures, enums, and ClassDB methods.
- Always use this file — not docs or training data — when you need an API signature.

## Per-Directory Language Rules

| Directory | Language | Notes |
|-----------|----------|-------|
| `extensions/` | C++20 only | GDExtension interceptors |
| `capture/` | C# 14 / .NET 10 only | Data fabric |
| `games/*/` | C# Godot .NET | Game projects |
| `analysis/` | Python 3.12 | Jupyter notebooks |

Do not mix languages within a directory boundary.

## Build System

### C++ (Tier 1)

```
scons platform=macos target=template_debug arch=arm64
scons platform=windows target=template_release arch=x86_64
```

### .NET (Tier 2)

```
dotnet build
dotnet build -p:SkipNativeBuild=true   # .NET-only iteration (skip C++ rebuild)
```

## Hot Path Constraints

`[UnmanagedCallersOnly]` receivers are on the hot path. Rules:

1. Use `TryWrite`, **never** `WriteAsync`.
2. Use `ArrayPool<T>` for zero-alloc buffering.
3. **No blocking** — no locks, no `Task.Wait()`, no synchronous I/O.

## No MCP Servers

This skill provides domain knowledge only. It does not expose or require any MCP servers.
