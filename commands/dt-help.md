---
name: dt-help
description: List all skills, commands, MCP servers, and agents available in the loaded plugins. Use when you want to discover what capabilities are available, search for a skill by keyword, or see what a plugin includes.
allowed-tools:
  - Bash
  - Read
---

Catalog all loaded DreamTeams capabilities.

**Usage:**
- `/dt-help` — list everything loaded (skills, commands, agents, MCP servers by plugin)
- `/dt-help dt-brigid` — show everything in a specific plugin
- `/dt-help skills` — list all skills only
- `/dt-help <keyword>` — search for capabilities matching a keyword

**What it does:**

Read `dreamteams.yaml` and enumerate the loaded plugins, skills, commands, agents, and MCP servers.

For `/dt-help` with no arguments: list all plugins with their skill count and command count, then print each plugin's skills and commands grouped by plugin.

For `/dt-help <plugin-name>`: show the full component list for that plugin (skills, commands, hooks, MCP servers, agents).

For `/dt-help <keyword>`: search skill descriptions and command descriptions for the keyword, return matching items with their plugin and a one-line description.

**Data source:** Read `dreamteams.yaml` directly (parse with Bash). No GitHub API needed.

**Output format:**

```
dt-brigid (40 skills, 2 commands)
  Skills: brigid-voice, crystal-magica-architecture, gamedev-godot, ...
  Commands: /dt-help, /brain-status, ...

dt-core (21 skills, 9 commands)
  Skills: board-status, bg-status, doc-standards, git-workflow, ...
  Commands: /merged, /release, /standup, /status, ...
```

For keyword search:
```
Found 3 matches for "godot":
  dt-brigid / skill / gamedev-godot — Godot 4.6 engine patterns and best practices
  dt-brigid / skill / godot-scene-patterns — Scene tree architecture for Godot games
  dt-brigid / skill / godot-signals-csharp — Signal system with C# bindings
```

**Implementation:**

1. Parse any argument from the invocation.
2. Read `dreamteams.yaml` with Bash (e.g., `python3 -c "import yaml, sys; d = yaml.safe_load(open('dreamteams.yaml')); ..."`).
3. Route to the matching operation:
   - No argument -> Browse (list all plugins)
   - Argument matches a plugin name -> show full component list for that plugin
   - Argument is `skills`, `commands`, `agents`, or `mcp` -> Browse filtered to that component type
   - Anything else -> Search across skill and command names + descriptions
4. Render output using the format above. Keep it one screen for the default view; paginate with headers for long lists.

**Constraints:**
- Read-only. Never modify any file.
- If `dreamteams.yaml` is not found at the repo root, print: `dreamteams.yaml not found — run this command from the repo root.`
- If a plugin name is given but does not exist in the registry, print: `Plugin '<name>' not found. Run /dt-help to list available plugins.`
