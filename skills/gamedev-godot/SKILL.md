---
name: gamedev-godot
description: Godot 4.6 game development with C# (.NET 10). Scene authoring, node hierarchy, C# scripting patterns, signals, physics, networking, and Godot MCP server workflow. Load this skill for any Godot project work.
---

# Godot 4.6 Development (C#)

## Engine & Language

- **Godot 4.6** with **C# (.NET 10)** — never GDScript.
- For C# scripts, use Write/Edit tools with Godot C# conventions (not GDScript MCP tools).

## Core Expertise

- **Scene architecture**: Node hierarchy design, scene composition, inherited scenes
- **C# scripting**: Exports, signals, `[Export]` attributes, `_Ready()` / `_Process()` / `_PhysicsProcess()` lifecycle
- **2D systems**: TileMaps, physics (CharacterBody2D, RigidBody2D, Area2D), AnimationPlayer, collision layers
- **Networking**: Custom binary protocol, server/client architecture
- **Performance**: Object pooling, spatial partitioning, draw call optimization

## Godot MCP Server

The Godot MCP server is a **plugin running inside the Godot editor** (33 core + 78 dynamic tools via ToolSearch).

### Before any scene operation
- Check `editor_status` — abort if not connected
- Use `tool_catalog` and `tool_groups` to discover available tools

### Inspection workflow
`editor_status` → `project_info` → `scene_nodes` → `scene_node_properties` → `script_info` → `class_info`

### Build workflow
`scene_create` → `scene_node_add` → `scene_node_set` → `signal_connect` → `scene_save`

### Run & debug workflow
`editor_run` → `editor_debug_output` → `editor_stop`

## Execution Rules

1. **Inspect before modifying.** Use `class_info` to verify types, properties, signals before making changes.
2. **Build incrementally.** Small testable steps — run and check output after each change.
3. **C# over GDScript.** Always. No exceptions.
4. **Verify after changes.** Run the scene and check debug output.

## Scene Scaffolding Pattern

1. Clarify: scene name, root node type, expected behaviors, parent scene
2. `scene_create` with appropriate root node
3. Build node hierarchy with `scene_node_add` (collision shapes, sprites, areas)
4. Write C# script stub to `scripts/` using Write tool
5. Connect signals with `signal_connect`
6. `scene_save`, smoke test with `editor_run` if safe
