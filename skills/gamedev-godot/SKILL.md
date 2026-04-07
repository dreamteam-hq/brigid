---
name: gamedev-godot
description: Godot 4.6 game development with C# (.NET 10). Scene authoring, node hierarchy, C# scripting patterns, signals, physics, networking, and Godot MCP server workflow. Load this skill for any Godot project work.
triggers:
  - Godot
  - Godot 4.6
  - scene authoring
  - node hierarchy
  - C# scripting
  - physics
  - Godot MCP
  - GodotObject
  - _Ready
  - _Process
version: "1.0.0"
---

# Godot 4.6 Development (C#)

Godot 4.6 with C# (.NET 10) is the client stack for CrystalMagica. This skill covers project structure, script conventions, scene lifecycle, the MCP workflow for scene inspection, and common pitfalls. Never GDScript. Never GodotObject without a reason.

## Project Structure

A Godot C# project always has a `.csproj` at the repo root (or in the Godot project folder) alongside the `project.godot` file. Scripts are `.cs` files; scenes are `.tscn` files; reusable data types are `.tres` resource files.

```
CrystalMagica.Game/
├── project.godot           # Godot project settings, autoloads, input map
├── CrystalMagica.Game.csproj
├── scenes/
│   ├── main.tscn           # Root scene (entry point)
│   ├── player/
│   │   ├── player.tscn     # Scene: CharacterBody3D root
│   │   └── player.cs       # Matches root node class
│   └── ui/
│       └── hud.tscn
├── scripts/
│   ├── autoloads/          # Singletons registered in project.godot
│   └── resources/          # Custom Resource subclasses (.cs only)
├── assets/
│   ├── textures/
│   └── audio/
└── addons/                 # Editor plugins (if any)
```

**Scene naming convention:** one `.tscn` per root node type, same name as its C# script. `player.tscn` + `PlayerNode.cs` where `PlayerNode` extends `CharacterBody3D`.

**No GDScript rule.** If you open a `.gd` file, close it and write a `.cs` equivalent. The codebase must be a single language. The Godot MCP's GDScript tools (`gdscript_*`) are off-limits.

## C# Script Conventions

All scripts are `partial class` — Godot's source generator emits the other partial. Never seal Godot node classes (the generator can't extend them).

```csharp
using Godot;

public partial class PlayerNode : CharacterBody3D
{
    [Export] public float MoveSpeed { get; set; } = 5f;
    [Export] public float JumpVelocity { get; set; } = 8f;

    [Signal] public delegate void HealthChangedEventHandler(int newHealth);
    [Signal] public delegate void DiedEventHandler();

    private int _health = 100;

    public override void _Ready()
    {
        // Safe: all child _Ready calls are complete before this fires
        SetPhysicsProcess(false);  // Idle until Bind() is called
    }

    public void Bind(CharacterData data)
    {
        _health = data.Health;
        SetPhysicsProcess(true);
    }

    public override void _PhysicsProcess(double delta)
    {
        // Hot loop — no allocations, no null checks (Bind guards entry)
    }
}
```

**`[Export]`** — exposes a field or property to the Godot editor. Supports primitives, `NodePath`, `PackedScene`, `Resource` subclasses, and enums. Arrays of exported types use `[Export] public Godot.Collections.Array<PackedScene> ...`.

**`[Signal]`** — declares a signal. The delegate name must end in `EventHandler`; the signal name is the delegate name minus `EventHandler`. Emit with `EmitSignal(SignalName.HealthChanged, newHealth)`. Connect in C# with `+=`.

**No `[Export]` on Godot node references stored as fields.** Store node references as typed fields populated in `_Ready` via `GetNode<T>`. `[Export] public PlayerNode Player` causes issues with cross-scene references; use `NodePath` exports instead and resolve in `_Ready`.

## Scene Tree Lifecycle

Godot processes the tree in two distinct passes on add:

1. **`_EnterTree()`** — fires top-down as each node joins the tree. The node is in the tree but children may not be yet. Use for registration with autoloads or global systems.
2. **`_Ready()`** — fires bottom-up. All children have completed their `_Ready` before the parent's fires. Safe to call `GetNode<T>` on any child here.

On remove:

3. **`_ExitTree()`** — fires top-down on removal. Disconnect signals here to prevent callbacks on freed nodes.

Per-frame:

4. **`_Process(double delta)`** — called every frame. Used for UI, animations, non-physics logic.
5. **`_PhysicsProcess(double delta)`** — called at the physics tick rate (default 60 Hz). Used for movement, collision checks. Always apply physics here, never in `_Process`.

```csharp
public override void _EnterTree()
{
    // Register with a global singleton or event bus
    GameEvents.Instance.PlayerSpawned += OnAnotherPlayerSpawned;
}

public override void _ExitTree()
{
    // Disconnect to avoid callbacks after free
    GameEvents.Instance.PlayerSpawned -= OnAnotherPlayerSpawned;
}

public override void _Ready()
{
    // Cache child references — safe here
    _sprite = GetNode<Sprite3D>("Sprite3D");
    _collider = GetNode<CollisionShape3D>("CollisionShape3D");
}
```

**Disabling process loops.** Nodes call `SetProcess(false)` / `SetPhysicsProcess(false)` to pause their loop without removing them from the tree. CrystalMagica uses this in `_Ready` to keep nodes inert until `Bind()` provides required data, eliminating null guards in the hot loop.

## MCP Server Workflow

The Godot MCP server is an editor plugin that exposes the running Godot editor to external agents. It has two categories of tools: core tools (always available) and dynamic tools (load via `ToolSearch`).

**Before any scene operation, verify the editor is connected:**

```
mcp__godot__intelligence_project_state  →  check editor is open and project is loaded
```

If the editor is not connected, abort. Do not attempt scene operations against a disconnected editor.

### Inspection Workflow

Use this sequence to understand an existing scene before modifying it:

```
intelligence_project_state
  → intelligence_scene_analyze("res://scenes/player/player.tscn")
    → intelligence_script_analyze("res://scripts/PlayerNode.cs")
      → intelligence_project_symbol_search("PlayerNode")
```

`intelligence_scene_analyze` returns the node tree, types, and attached scripts. `intelligence_script_analyze` parses exported properties, signals, and method signatures. `intelligence_project_symbol_search` finds all usages — useful before renaming or deleting.

### Build Workflow

When creating a new scene:

```
intelligence_scene_analyze (parent scene, to understand attachment point)
  → [Write tool] write the .cs script stub
  → intelligence_scene_patch (add nodes to .tscn)
  → intelligence_scene_validate (check for broken references)
  → intelligence_project_run (smoke test)
```

Write C# scripts with the Write/Edit tools, never through the MCP's GDScript tools. Patch `.tscn` files via `intelligence_scene_patch` rather than editing raw text — the TSCN format has implicit node ID references that break on manual edits.

### Run and Debug Workflow

```
intelligence_project_run   →   start the editor's play mode
intelligence_runtime_diagnose  →  inspect running state, errors, node tree at runtime
intelligence_project_stop  →  stop play mode
```

Always stop play mode before patching scenes. Patching a running scene has undefined behavior.

## Common Pitfalls

**Null refs from scene tree timing.** Calling `GetNode<T>` in a constructor or field initializer always returns null — the scene tree doesn't exist yet. Call it in `_Ready` or later. If a node needs a reference before `_Ready`, it must be injected by the parent coordinator.

**`QueueFree` vs `Free`.** `Free()` destroys a node immediately, even mid-frame, which can crash if other code holds a reference. `QueueFree()` defers destruction to the end of the frame. Always use `QueueFree` unless you have an explicit reason for immediate destruction and are certain no callbacks fire afterward.

**Modifying the tree inside `_Process`.** Adding or removing children during `_Process` iteration can corrupt the tree traversal. Use `CallDeferred("AddChild", node)` or `node.CallDeferred("QueueFree")` to defer tree mutations to the end of the frame.

```csharp
// Wrong — may crash mid-iteration
public override void _Process(double delta)
{
    if (_shouldSpawn) AddChild(_projectile);  // Don't do this
}

// Correct
public override void _Process(double delta)
{
    if (_shouldSpawn) CallDeferred(Node.MethodName.AddChild, _projectile);
}
```

**Signal connections leaking across scene changes.** Signals connected to a freed node throw errors when emitted. Disconnect in `_ExitTree` or use `ConnectFlags.OneShot` for one-time signals. `+=` connections from C# lambda closures can also capture `this` and prevent GC — prefer named methods for connections that outlive the current scope.

**`[Export]` on non-Variant types.** Godot's variant system does not natively handle arbitrary C# types. Exporting `Dictionary<string, int>` silently fails. Use `Godot.Collections.Dictionary` for exported dictionaries. For complex exported data, create a `Resource` subclass.

**Confusing `_PhysicsProcess` and `_Process` for movement.** Physics (CharacterBody, RigidBody, collision queries) must run in `_PhysicsProcess`. Running movement in `_Process` makes it frame-rate dependent and desynchronizes from Godot's physics step.

## Anti-Patterns

**GDScript anywhere.** One language. If a collaborator adds `.gd` files, convert them to C# before the PR merges.

**Non-partial node classes.** Godot's source generator (`GodotSourceGenerators`) emits a partial class with property notification, signal dispatching, and serialization support. A non-partial class breaks codegen silently — the `[Export]` and `[Signal]` attributes appear to work but the generated code never wires them correctly.

**`GetNode` in constructors.** The node is not yet in the tree when the C# constructor runs. The engine calls `_Ready` after the full subtree is assembled. Cache node references in `_Ready`.

**Long inheritance chains for game entities.** Deep C# inheritance in Godot nodes (`Enemy` → `MovingEnemy` → `PatrollingEnemy` → `BossEnemy`) becomes brittle because Godot serializes the scene separately from the class hierarchy. Prefer composition: one base node class + exported `Resource` data objects for variant configuration.

**Autoloading everything.** Autoloads are globals and survive scene changes, which makes them convenient. But over-autoloading creates hidden coupling. Limit autoloads to true cross-scene singletons (input manager, audio bus, event bus). Local systems that one scene owns belong in that scene's subtree, not in an autoload.

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `godot-scene-patterns` | `PackedScene`, inherited scenes, coordinator pattern, resource preloading |
| `godot-signals-csharp` | Custom signals, typed delegates, signal bus, Rx integration |
| `godot-input-system` | `InputMap`, action-based input, input buffer, multiplayer input routing |
| `godot-networking-custom` | Custom binary WebSocket protocol, client-side netcode |
| `observable-godot-architecture` | MVVM pattern, Rx/DynamicData bindings in Godot nodes |
| `crystal-magica-architecture` | CrystalMagica-specific MVVM types: `PlayerNode`, `RemotePlayerNode`, `IBindable` |
