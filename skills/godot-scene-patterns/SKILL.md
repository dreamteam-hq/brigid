---
name: Godot Scene Patterns
description: Scene composition patterns for Godot 4.6 C# — inherited scenes, PackedScene instantiation, node ownership, scene tree lifecycle
triggers:
  - scene tree
  - scene composition
  - PackedScene
  - scene lifecycle
  - node ownership
  - inherited scene
  - scene patterns
category: gamedev
---

# Godot 4.6 C# Scene Composition Patterns

## Scene-as-Prefab

`PackedScene` is Godot's prefab equivalent. Instantiate with the generic form to get a typed root node:

```csharp
var scene = GD.Load<PackedScene>("res://scenes/enemy.tscn");
Enemy enemy = scene.Instantiate<Enemy>();
parentNode.AddChild(enemy);
```

`Instantiate<T>()` casts the root node. If the root script doesn't extend `T`, you get `null` (not an exception).

**Scenes vs code-created nodes:** Use scenes when the subtree has visual layout, exported properties tuned in the editor, or is reused across contexts. Use code-created nodes for runtime-dynamic structures (pooled projectiles, procedural geometry) or trivial nodes like a single `Timer`. A hybrid is common: instantiate a scene, then attach code-created children at runtime.

## Inherited Scenes

An inherited scene (`.tscn` with `type="inherited"`) references a base scene. Overrides are stored as deltas — only changed properties serialize. This is useful for enemy variants sharing a base skeleton but differing in stats or child configuration.

**Limitations:** Inherited scenes cannot remove nodes from the base, only add or override. Structural changes to the base propagate automatically, which can break overrides if node paths change. Deep inheritance chains (3+ levels) become brittle; prefer composition (attach variant data via exported `Resource` subclasses) when the variation is primarily data-driven rather than structural.

Re-saving an inherited scene after base changes is required to resolve conflicts — Godot marks stale overrides but does not auto-fix.

## Node Ownership

`Node.Owner` controls which nodes serialize into a `PackedScene`. When you call `AddChild(node)`, the child's `Owner` is **not** set automatically. Nodes with `Owner == null` are excluded from `PackedScene.Pack()` and from saved `.tscn` files.

In the editor, nodes added as part of the scene have `Owner` set to the scene root. Nodes instantiated from sub-scenes have `Owner` set to their own sub-scene root — they are internal to that sub-scene boundary and do not appear in the parent scene's serialization.

**Practical rule:** If you `AddChild()` at runtime and later need to `Pack()` or save the scene, call `child.Owner = GetTree().EditedSceneRoot` (editor) or `child.Owner = sceneRoot` (runtime). For purely runtime nodes that should never serialize, leave `Owner` null — this is the common case.

`Node.GetChildren()` returns all children regardless of ownership. To find "scene-owned" children only, filter on `Owner`.

## Lifecycle Ordering

Godot processes the tree depth-first, children before parent:

1. **`_EnterTree()`** — called as each node is added to the tree, top-down (parent enters before children).
2. **`_Ready()`** — called bottom-up. A parent's `_Ready` fires only after all children's `_Ready` calls complete.

This means in `_Ready()`, you can safely reference child nodes. You **cannot** safely reference siblings or parent state that depends on `_Ready`, because sibling order is not guaranteed relative to your own `_Ready`.

**Deferred calls:** `CallDeferred("MethodName")` and `SetDeferred("property", value)` queue execution for the end of the current frame's idle processing. Use this to avoid modifying the tree mid-iteration (e.g., freeing nodes inside `_Process`).

**CrystalMagica pattern — deferred activation:**

```csharp
public override void _Ready()
{
    SetPhysicsProcess(false);  // Inert until explicitly bound
    // ... cache node references, subscribe to signals
}

public void Bind(EntityData data)
{
    _data = data;
    SetPhysicsProcess(true);   // Now live
}
```

This prevents `_PhysicsProcess` from running on frames between `_Ready` and when the owning system provides required data. It eliminates null-checks inside the hot loop and makes the node's contract explicit: no ticking without initialization.

## Coordinator Pattern

Sibling nodes should not reach across to each other. A parent or ancestor node mediates:

```csharp
// BattleArena.cs (parent coordinator)
public override void _Ready()
{
    var hud = GetNode<BattleHud>("BattleHud");
    var player = GetNode<PlayerUnit>("PlayerUnit");

    player.HealthChanged += (hp) => hud.UpdateHealth(hp);
    player.Defeated += () => OnBattleEnd(victory: false);
}
```

Siblings expose signals; the coordinator wires them. This keeps each subtree testable in isolation (you can instantiate `PlayerUnit` in a test scene without `BattleHud` existing) and avoids fragile `GetNode("../Sibling")` paths that break on reparenting.

For deeply nested communication that would require long coordinator chains, use an autoload event bus — but prefer direct signal wiring at the coordinator level for local interactions.

## Resource Preloading

**`GD.Load<T>(path)`** — synchronous load, blocks the calling thread. Fine for small resources or anything called during loading screens. Godot caches loaded resources; subsequent `GD.Load` calls with the same path return the cached instance.

**`ResourceLoader.LoadThreadedRequest(path)`** — initiates async loading on a background thread. Poll with `ResourceLoader.LoadThreadedGetStatus(path)` and retrieve with `ResourceLoader.LoadThreadedGet(path)`.

```csharp
ResourceLoader.LoadThreadedRequest("res://scenes/boss_arena.tscn");

// Check each frame or on timer
var status = ResourceLoader.LoadThreadedGetStatus("res://scenes/boss_arena.tscn");
if (status == ResourceLoader.ThreadLoadStatus.Loaded)
{
    var scene = ResourceLoader.LoadThreadedGet("res://scenes/boss_arena.tscn") as PackedScene;
}
```

Use threaded loading for large scenes/textures that would cause frame hitches. For resources under ~1MB that are needed immediately, `GD.Load` is simpler and the cache makes repeated access free.

**Caution:** `ResourceLoader.LoadThreadedGet` must be called from the main thread. The background thread only handles I/O and parsing.

## Scene Change Management

**`GetTree().ChangeSceneToPacked(packedScene)`** — replaces the current scene root. The old scene is freed. This is the simple path for linear scene flow (menu to game to results).

**Manual tree manipulation** — for overlapping scenes, additive loading, or transition effects:

```csharp
var current = GetTree().CurrentScene;
GetTree().Root.RemoveChild(current);

var next = nextScene.Instantiate();
GetTree().Root.AddChild(next);
GetTree().CurrentScene = next;
```

`ChangeSceneToPacked` calls `queue_free()` on the old scene internally, so all deferred calls and signals from the old scene complete before teardown. Manual manipulation gives control over timing but requires you to manage freeing the old scene yourself.

For transitions (fade-out, loading screen), use a persistent autoload node that orchestrates the swap — it survives scene changes since autoloads live under `/root` above `CurrentScene`.
