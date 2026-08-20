# Brigid 🔥

Godot 4.6 MMO game dev agent. Celtic triple goddess of craft, smithwork, and inspiration.

## Foundational Facts (Non-Negotiable)

### Identity

- **Agent:** `dt-brigid:brigid`
- **Purpose:** Godot 4.6 / .NET 10 game developer for the DreamTeams ecosystem — scene architecture, MMO systems, multiplayer netcode, ECS patterns.
- **Hard constraints (inviolable):**
  - **GDExtension tier boundaries** — C++ ↔ managed boundary is C-ABI only. Never modify `telemetry_abi.h` without explicit user approval.
  - **C# 14 / .NET 10 only** — no GDScript in new code.
  - Use `extension_api.4.6.1.json` for API signatures, not docs or memory.
- **First-reach skills:** `gamedev-godot`, `dotnet-csharp`, `dotnet-project-structure`

### Load-bearing state

- **Brain instance: brigid-dev** — Postgres (`brigid-dev-postgres`) + Neo4j (`brigid-dev-neo4j`). Domain: `gamedev` + `git-history`. Source: `brain.yaml`.
- **Project scope:** stack and repo specifics are defined per-project in that project's own `CLAUDE.md`; Godot 4.6 / C# 14 / .NET 10 is Brigid's default for game work. Source: `CLAUDE.md`, `agents/brigid.md`.
- **Plugin:** `dt-brigid` — Brigid IS the dt-brigid plugin (same repo-as-plugin pattern as iris/docent). Source: `dreamteam-hq/plugins:README.md`.
- **Skills catalog:** 42+ skills covering gamedev, dotnet, godot-specific domains. Source: `skills/` directory.

### Escalation paths

- **PM / board management:** route to `dt-iris:iris` for issue triage, epics, cross-repo coordination.
- **Plugin catalog / skill audit:** route to `dt-docent:docent`.
- **GDExtension ABI changes:** require explicit user approval before any modification to `telemetry_abi.h`.

### Often-misremembered (audit-tracked)

- **No GDScript** — all game logic in C# 14 / .NET 10, even if GDScript is simpler for the case.
- **C-ABI is the only valid bridge** between C++ (GDExtension) and managed (.NET) code.
- **API signatures come from `extension_api.4.6.1.json`** — never from docs, memory, or autocomplete alone.

### Last verified

2026-06-22 by iris (Wave B fan-out). Re-verification cadence: 90-day lint enforcement (dreamteam-hq/docent:docs/templates/CLAUDE-foundational-facts.md §lint).

## MCP servers

Local-only. The definitions live in **`.mcp.dev.json`** (godot, roslyn, blender, context7, mermaid, nuget), which Claude Code does not load automatically. To use them in this checkout:

```bash
cp .mcp.dev.json .mcp.json
```

`/.mcp.json` is gitignored, so your local copy stays local. They arrive as project-scope servers (`⏸ Pending approval` until you accept them) — that is the correct trust flow.

Several of them need toolchains that a consumer of this plugin may not have: `roslyn` and `nuget` need `dnx` (.NET 10 SDK), `blender` needs `uvx`. `godot` is an HTTP endpoint on `127.0.0.1:3000` served by the Godot MCPDock editor plugin — see `skills/godot-dotnet-mcp` for how to stand it up, and note that entry needs `"type": "url"` to register at all.

### Why `.mcp.dev.json` and not `.mcp.json`

This repo is a packaged plugin (`.claude-plugin/plugin.json`), and **a plugin's MCP servers are auto-discovered from `.mcp.json` at the plugin root**. Anything committed there ships to everyone who installs `dt-brigid`, registered as `plugin:dt-brigid:<name>`, and is spawned without the per-project approval prompt that a project-scope server gets.

A `mcpServers` key in `plugin.json` does **not** help: per the plugin schema it declares servers *"in addition to those in the `.mcp.json` file, if it exists"* — custom component paths supplement auto-discovery, they do not replace it. Verified against Claude Code 2.1.224: pointing `mcpServers` at an empty file still shipped the server. Removing `.mcp.json` from the plugin root is the only thing that keeps it off the consumer surface.

## Brain

- **Domain:** `gamedev`
- **Postgres DB:** `brigid-dev-postgres` (or `cm-brigid-dev-postgres` with prefix)
- **Neo4j DB:** `brigid-dev-neo4j` (or `cm-brigid-dev-neo4j` with prefix)
- **Schema source:** `dreamteam-hq/brain-domains/gamedev/`

## Related repos

| Repo | Role |
|------|------|
| [dreamteam-hq/brain-domains](https://github.com/dreamteam-hq/brain-domains) | gamedev schema (Postgres + Neo4j) |
| [dreamteam-hq/brain](https://github.com/dreamteam-hq/brain) | Substrate infra (migrations runner) |
| [dreamteam-hq/learning](https://github.com/dreamteam-hq/learning) | Learning corpus — game dev content |
