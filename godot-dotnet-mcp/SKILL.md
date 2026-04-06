---
name: godot-dotnet-mcp
description: Comprehensive guide to the Godot .NET MCP server — programmatic scene manipulation, script analysis, C# binding audits, and runtime diagnostics for Godot 4.6+ projects
version: 1.0.0
agent: brigid
tags: [godot, mcp, dotnet, csharp, scene-manipulation, game-dev]
---

# Godot .NET MCP — Skill Reference

An MCP server plugin running inside the Godot editor. Agents read live project state, manipulate scenes and scripts directly, and diagnose C# bindings without any external process.

**Repository**: [LuoxuanLove/godot-dotnet-mcp](https://github.com/LuoxuanLove/godot-dotnet-mcp)

---

## Table of Contents

1. [Setup and Transport](#setup-and-transport)
2. [Architecture](#architecture)
3. [Workflow: Start Here](#workflow-start-here)
4. [Intelligence Tools](#intelligence-tools)
5. [Scene Tools](#scene-tools)
6. [Node Tools](#node-tools)
7. [Script Tools](#script-tools)
8. [Resource Tools](#resource-tools)
9. [Project Tools](#project-tools)
10. [Editor Tools](#editor-tools)
11. [Debug Tools](#debug-tools)
12. [Physics Tools](#physics-tools)
13. [Signal Tools](#signal-tools)
14. [Group Tools](#group-tools)
15. [Filesystem Tools](#filesystem-tools)
16. [Animation Tools](#animation-tools)
17. [Material Tools](#material-tools)
18. [Shader Tools](#shader-tools)
19. [Lighting Tools](#lighting-tools)
20. [Navigation Tools](#navigation-tools)
21. [Particle Tools](#particle-tools)
22. [UI Tools](#ui-tools)
23. [Audio Tools](#audio-tools)
24. [TileMap Tools](#tilemap-tools)
25. [Geometry Tools](#geometry-tools)
26. [Plugin Runtime Tools](#plugin-runtime-tools)
27. [Plugin Evolution Tools](#plugin-evolution-tools)
28. [Plugin Developer Tools](#plugin-developer-tools)
29. [Custom Tools](#custom-tools)
30. [CrystalMagica Workflows](#crystalmagica-workflows)
31. [Anti-Patterns](#anti-patterns)

---

## Setup and Transport

### Installation

**Option 1 — Direct copy** (recommended for CrystalMagica):
Copy `addons/godot_dotnet_mcp/` into your project's `addons/` directory. Enable in Project > Project Settings > Plugins.

**Option 2 — Git submodule**:
```bash
git submodule add https://github.com/LuoxuanLove/godot-dotnet-mcp.git _godot-dotnet-mcp
# Copy addons/godot_dotnet_mcp/ from the submodule into your project
```

**Option 3 — Release package**: Download from GitHub Releases.

### Requirements

- Godot 4.6+ (Mono/.NET build)
- .NET SDK matching your Godot version

### Transport Configuration

| Property | Default | Notes |
|----------|---------|-------|
| Port | `3000` | Configurable via MCPDock > Server panel |
| Protocol | HTTP | Streamable HTTP transport |
| Health check | `GET http://127.0.0.1:3000/health` | Verify server is running |
| Tool discovery | `GET http://127.0.0.1:3000/api/tools` | List all registered tools |
| MCP endpoint | `POST http://127.0.0.1:3000/mcp` | MCP protocol calls |

### Claude Code Configuration

Add to your MCP config (`.mcp.json` or project settings):

```json
{
  "mcpServers": {
    "godot": {
      "type": "url",
      "url": "http://127.0.0.1:3000/mcp"
    }
  }
}
```

The MCPDock UI can generate config snippets for Claude Code, Cursor, Claude Desktop, Codex CLI, and Gemini CLI.

### Server Startup

The server auto-starts from saved settings when the plugin is enabled. Manual control is available via MCPDock > Server panel. Port changes are saved and take effect on next server restart.

---

## Architecture

### Editor-Native Execution

The plugin runs embedded in the Godot editor process. This means:
- Tool calls reflect **actual live editor state** (open scenes, selected nodes, project settings)
- No external process or sidecar — zero serialization overhead for scene tree access
- Write operations are immediately visible in the editor
- Runtime bridge captures errors from the running game process

### Tool Registry

25 built-in tool categories organized into 5 domains:

| Domain | Categories |
|--------|-----------|
| **core** | intelligence, scene, node, resource, project, script, editor, debug, filesystem, group, signal |
| **visual** | animation, material, shader, lighting, particle, tilemap, geometry |
| **gameplay** | physics, navigation, audio |
| **interface** | ui |
| **plugin** | plugin_runtime, plugin_evolution, plugin_developer |

Plus a **user** domain for custom tools (see [Custom Tools](#custom-tools)).

### Tool Naming Convention

MCP tool names follow the pattern: `{category}_{tool_name}` for top-level tool names exposed over the wire. Within each category, tools use an `action` parameter to select the specific operation.

### Path Conventions

| Path type | Format | Example |
|-----------|--------|---------|
| Resource path | `res://` prefix | `res://Scenes/Enemy.tscn` |
| Node path (relative) | From scene root | `World/Player` |
| Node path (absolute) | `/root/` prefix | `/root/Main/World/Player` |
| Script path | `res://` prefix | `res://Views/EnemyNode.cs` |

---

## Workflow: Start Here

The recommended agent workflow for any task:

```
1. intelligence project_state     -> snapshot: file counts, errors, compile status
2. intelligence project_advise    -> actionable recommendations + next-tool suggestions
3. Use scene/node/script tools    -> targeted changes based on advice
4. intelligence runtime_diagnose  -> verify no regressions
```

Always start with `project_state`. It costs one call and tells you whether the project is healthy before you touch anything.

---

## Intelligence Tools

The intelligence layer is the primary entry point for agent interactions. These tools aggregate data from across the project and provide high-level analysis.

### project_state

Snapshot of current project health.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `error_limit` | integer | 10 | Max errors to include |
| `include_runtime_health` | boolean | false | Include plugin runtime health summary |

Returns: file counts, runtime errors, compile errors, bridge status.

### project_advise

Actionable suggestions based on live project state.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `goal` | string | `"general"` | Goal context (e.g., `"fix_errors"`, `"add_feature"`) |
| `include_suggestions` | boolean | true | Include diagnostic suggestions |
| `include_workflow` | boolean | true | Include next-tool recommendations |

Returns: prioritized suggestions with specific tool calls to make next.

### project_configure

Read or modify project settings, autoloads, and input actions.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | string | yes | `get_settings`, `set_setting`, `list_autoloads`, `add_autoload`, `remove_autoload`, `list_input_actions` |
| `setting` | string | | Setting path |
| `value` | any | | New value |
| `name` | string | | Autoload name |
| `path` | string | | Script path for autoload |

### project_run

Launch the project in the editor.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scene` | string | no | Custom scene path; runs main scene if omitted |

### project_stop

Stop the currently running project. No parameters.

### runtime_diagnose

Full error report with stacktraces for debugging.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `include_compile_errors` | boolean | true | Include .NET compile errors |
| `include_performance` | boolean | false | Include FPS/memory snapshot |
| `tail` | integer | 20 | Number of recent runtime errors |
| `include_gd_errors` | boolean | false | Include GDScript Output panel errors |

### scene_validate

Quick integrity check of a `.tscn` file.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scene` | string | yes | Scene path (`res://...*.tscn`) |

Returns: validity status, issues array, missing dependencies.

### scene_analyze

Deep inspection: node count, attached scripts with class_name/base_type, signal bindings.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scene` | string | yes | Scene path (`res://...*.tscn`) |

Returns: node count, binding count, script metadata array, issues.

### scene_patch

Apply structured edits to a `.tscn` file.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `scene` | string | yes | Scene path |
| `ops` | array | yes | List of patch operations |
| `dry_run` | boolean | no | Preview mode (default: `true`) |

Supported operations: `add_node`, `remove_node`, `set_property`, `attach_script`, `reparent_node`, `rename_node`, `update_property`.

**Always use `dry_run: true` first** to preview changes before applying.

### bindings_audit

Audit C# `[Export]`/`[Signal]`/`NodePath` binding consistency against scene references. C# files only.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `script` | string | no | C# script path to audit |
| `scene` | string | no | Scene path to audit its scripts |
| `include_warnings` | boolean | | Default: true |

Returns: total_issues count, results array with kind, issues (severity/type/message).

### script_analyze

Inspect `.gd` or `.cs` scripts: class structure, methods, exports, signals, variables, scene references.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `script` | string | yes | Script path (`res://...`) |
| `include_diagnostics` | boolean | no | Enable LSP diagnostics (`.gd` only) |

Returns: class_name, base_type, methods[], exports[], signals[], variables[], scene_refs[].

### script_patch

Add or edit script members via patch operations.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `script` | string | yes | Script path |
| `ops` | array | yes | Operation objects |
| `dry_run` | boolean | no | Preview without executing (default: `true`) |

Operations: add methods/exports/variables/signals, replace bodies, delete/rename members.

### project_index_build

Build an in-memory symbol index over all scripts, scenes, and resources. **Must be called before** `project_symbol_search` or `scene_dependency_graph`.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `include_resources` | boolean | no | Include `.tres`/`.res` files (default: true) |

### project_symbol_search

Find scripts, scenes, or classes by name. **Requires `project_index_build` first.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `symbol` | string | yes | Name to search for |

### scene_dependency_graph

Scene-to-scene dependency map from ExtResource references. **Requires `project_index_build` first.**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `root_scene` | string | no | Specific scene to traverse from; omit for full project |
| `max_depth` | integer | no | Max traversal depth (default: 4) |

---

## Tool Catalog

25 tool categories across 5 domains with ~200+ actions. See [references/tool-catalog.md](references/tool-catalog.md) for the full tool reference.

| Domain | Categories |
|--------|-----------|
| **core** | scene, node, script, resource, project, editor, debug, filesystem, group, signal |
| **visual** | animation, material, shader, lighting, particle, tilemap, geometry |
| **gameplay** | physics, navigation, audio |
| **interface** | ui |
| **plugin** | plugin_runtime, plugin_evolution, plugin_developer |


## Custom Tools

### Creating Custom Tools

1. Create a `.gd` file in `res://addons/godot_dotnet_mcp/custom_tools/`
2. Implement three methods:
   - `get_tools() -> Array[Dictionary]` -- tool definitions
   - `execute(tool_name: String, args: Dictionary) -> Dictionary` -- tool handler
   - `get_registration() -> Dictionary` (optional) -- metadata

3. **All tool names must use the `user_` prefix** -- this is enforced by the registry

4. The plugin loads custom tools automatically without rebuild

### Custom Tool Template

```gdscript
@tool
extends RefCounted

func get_registration() -> Dictionary:
    return {
        "display_name": "My Custom Tool",
        "hot_reloadable": true
    }

func get_tools() -> Array[Dictionary]:
    return [{
        "name": "user_my_action",
        "description": "Description of what this tool does",
        "inputSchema": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ["do_thing"]},
                "param": {"type": "string"}
            },
            "required": ["action"]
        }
    }]

func execute(tool_name: String, args: Dictionary) -> Dictionary:
    match tool_name:
        "user_my_action":
            return {"success": true, "result": "done"}
    return {"error": "Unknown tool"}
```

### Custom Tool Management

Use the [Plugin Evolution Tools](#plugin-evolution-tools) to scaffold, audit, and manage custom tools without manual file editing.


## CrystalMagica Workflows

See [references/crystalmagica-workflows.md](references/crystalmagica-workflows.md) for 6 detailed workflows tied to actual project files.

---

## Anti-Patterns

### Do NOT use MCP for:

1. **Visual layout work** -- Positioning UI elements, UV mapping, sprite placement. The Godot editor is better for spatial tasks. Use MCP to read/verify layout, not to author it.

2. **Direct .tscn file editing** -- When `scene_patch` exists, never edit `.tscn` text files directly. The patch tool handles Godot's internal ID tracking and resource references correctly.

3. **Bypassing MVVM** -- CrystalMagica uses MVVM. When using `script edit_cs` to modify Views, do not add business logic. Views bind to ViewModels; ViewModels hold state. The `script_patch` tool should add bindings and subscriptions to Views, not game logic.

4. **Skipping dry_run** -- Always use `dry_run: true` on `scene_patch` and `script_patch` before applying changes. This catches errors before they corrupt files.

5. **Ignoring project_state** -- Do not jump straight to making changes. Call `project_state` first to understand the current health. If there are existing compile errors, fix those before adding new code.

6. **Modifying .godot/imported/** -- Never touch imported resources. Use the resource tools to work with source assets.

7. **Calling runtime tools when the game is not running** -- `runtime_bridge`, `runtime_diagnose`, and `performance` tools require an active game session. Call `scene run action="play_main"` first.

8. **Forgetting to build .NET** -- After C# changes, call `debug dotnet action="build"` before testing. Unlike GDScript, C# requires compilation.

### Do USE MCP for:

1. **Verification** -- After any manual edit, use `bindings_audit` and `scene_validate` to catch wiring errors
2. **Discovery** -- `project_index_build` + `project_symbol_search` to find classes and scenes
3. **Diagnostics** -- `runtime_diagnose` for full error reports with stacktraces
4. **Batch operations** -- `scene_patch` with multiple ops for atomic scene changes
5. **C# binding inspection** -- `script_analyze` and `bindings_audit` to verify `[Export]`, `[Signal]` attributes
6. **Pre-flight checks** -- `project_state` + `project_advise` before starting any task
