---
name: godot-3d-collision-areas
description: >
  Godot 4.6 3D collision system — Area3D signals, CollisionShape3D primitives,
  collision layer/mask management, one-way platform patterns via layer toggling,
  down-jump implementation, and 2.5D constraints. All C# / .NET 10.
  Triggers: collision, Area3D, hitbox, hurtbox, one-way platform, down jump,
  collision layer, collision mask, attack area, 2.5D.
---

# Godot 4.6 3D Collision & Areas (C#)

## Quick Reference

### Collision Node Types

| Node | Purpose | Detects Via | Use For |
|------|---------|-------------|---------|
| CharacterBody3D | Physics body with `MoveAndSlide()` | Collision layer/mask | Player, enemies, NPCs |
| StaticBody3D | Immovable geometry | Collision layer/mask | Floors, walls, platforms |
| RigidBody3D | Physics-simulated body | Collision layer/mask | Crates, projectiles |
| Area3D | Overlap detection (no physics) | Signals + layer/mask | Hitboxes, hurtboxes, triggers |
| RayCast3D | Single-ray intersection test | Mask only | Ground detection, line of sight |
| ShapeCast3D | Shape sweep intersection test | Mask only | Wide attack sweeps, ledge detection |

For RayCast3D/ShapeCast3D details, see `references/raycast-shapecast.md`.
For attack hitbox enable/disable patterns, see `references/attack-hitbox-pattern.md`.

### Layer vs Mask -- One Sentence

**Layer** = "I exist on these layers." **Mask** = "I detect objects on these layers."

A collision occurs when **A's mask overlaps B's layer** OR **B's mask overlaps A's layer**.

### CrystalMagica Collision Layers

From `project.godot` -- active assignments:

| Layer | Bit | Name | Used By |
|-------|-----|------|---------|
| 1 | 1 | Environment | StaticBody3D floors, walls, platforms |
| 2 | 2 | Player | Player CharacterBody3D |
| 3 | 4 | PlayerHurtbox | Player Area3D (receives damage) |
| 4 | 8 | PlayerHitbox | Player weapon Area3D (deals damage) |

Planned additions for Loop 3 / Loop 5:

| Layer | Bit | Name | Purpose |
|-------|-----|------|---------|
| 5 | 16 | Enemy | Enemy CharacterBody3D |
| 6 | 32 | EnemyHurtbox | Enemy Area3D (receives damage) |
| 7 | 64 | EnemyHitbox | Enemy attack Area3D (deals damage) |
| 8 | 128 | Projectiles | Bullet/spell Area3D |
| 9 | 256 | Pickups | Collectible Area3D |
| 10 | 512 | Triggers | Checkpoints, zone transitions |
| 11 | 1024 | OneWayPlatforms | Platforms the player can drop through |

---

## Area3D -- Overlap Detection

Area3D detects when physics bodies or other areas enter/exit its collision shape. It does **not** block movement.

### Node Hierarchy

```
Area3D (hitbox or hurtbox)
  +-- CollisionShape3D (defines the detection region)
```

### Key Properties

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `Monitoring` | bool | true | This area detects other bodies/areas entering it |
| `Monitorable` | bool | true | Other monitoring areas can detect this area |
| `CollisionLayer` | uint | 1 | Layers this area exists on |
| `CollisionMask` | uint | 1 | Layers this area scans for overlaps |

**Rule**: A hitbox needs `Monitoring = true` (it detects). A hurtbox needs `Monitorable = true` (it gets detected). Set both to true unless you have a specific reason to optimize.

### Signals

| Signal | Parameter | Fires When |
|--------|-----------|------------|
| `BodyEntered` | `Node3D body` | A PhysicsBody3D enters the area |
| `BodyExited` | `Node3D body` | A PhysicsBody3D leaves the area |
| `AreaEntered` | `Area3D area` | Another Area3D enters overlap |
| `AreaExited` | `Area3D area` | Another Area3D leaves overlap |
| `BodyShapeEntered` | `Rid bodyRid, Node3D body, long bodyShapeIndex, long localShapeIndex` | Per-shape granularity |
| `BodyShapeExited` | `Rid bodyRid, Node3D body, long bodyShapeIndex, long localShapeIndex` | Per-shape granularity |

All signals require `Monitoring = true`.

### C# Signal Connection

```csharp
public override void _Ready()
{
    var hitbox = GetNode<Area3D>("Hitbox");
    hitbox.BodyEntered += OnHitboxBodyEntered;
    hitbox.BodyExited += OnHitboxBodyExited;

    // Or for area-to-area (hitbox vs hurtbox):
    hitbox.AreaEntered += OnHitboxAreaEntered;
}

private void OnHitboxBodyEntered(Node3D body)
{
    if (body is CharacterBody3D target && target.IsInGroup("enemies"))
    {
        // Deal damage
    }
}

private void OnHitboxAreaEntered(Area3D area)
{
    if (area.IsInGroup("enemy_hurtbox"))
    {
        // Area-to-area detection (hitbox overlaps hurtbox)
    }
}
```

### Querying Overlaps (Non-Signal)

```csharp
var hitbox = GetNode<Area3D>("Hitbox");
if (hitbox.HasOverlappingBodies())
{
    foreach (Node3D body in hitbox.GetOverlappingBodies())
    {
        // Process each overlapping body
    }
}

if (hitbox.HasOverlappingAreas())
{
    foreach (Area3D area in hitbox.GetOverlappingAreas())
    {
        // Process each overlapping area
    }
}
```

**Timing**: `GetOverlappingBodies()` and `GetOverlappingAreas()` return results from the most recent physics frame. They do **not** update mid-frame -- if you reposition a shape and query immediately in the same frame, you get stale results.

**There is no `ForceUpdateOverlaps()` on Area3D in Godot 4.6.** Unlike `RayCast3D.ForceRaycastUpdate()` and `ShapeCast3D.ForceShapecastUpdate()`, Area3D has no force-update method. If you need an immediate intersection test after repositioning (before the next physics frame), use a `PhysicsDirectSpaceState3D` query:

```csharp
// Immediate overlap query using PhysicsServer3D direct space state
var spaceState = GetWorld3D().DirectSpaceState;
var query = new PhysicsShapeQueryParameters3D
{
    Shape = hitboxShape,                  // the Shape3D resource
    Transform = hitbox.GlobalTransform,   // current world transform
    CollisionMask = hitbox.CollisionMask, // same mask as the Area3D
    CollideWithAreas = true,              // detect Area3D nodes (hurtboxes)
    CollideWithBodies = true,             // detect PhysicsBody3D nodes
};

var results = spaceState.IntersectShape(query);
foreach (var result in results)
{
    var collider = result["collider"].As<Node3D>();
    // Process immediate overlap
}
```

For most gameplay patterns (hitboxes, hurtboxes, triggers), the per-physics-frame update cycle is sufficient. Reserve `PhysicsDirectSpaceState3D` queries for cases where you teleport a shape and must know the result before the next `_PhysicsProcess` call.

---

## CollisionShape3D -- Shape Primitives

Every collision-aware node needs at least one CollisionShape3D child.

### Shape Types

| Shape | Class | Best For | Sizing |
|-------|-------|----------|--------|
| Box | `BoxShape3D` | Platforms, walls, rectangular hitboxes | `Size = new Vector3(w, h, d)` |
| Sphere | `SphereShape3D` | Radial triggers, pickup zones | `Radius = float` |
| Capsule | `CapsuleShape3D` | Player/enemy body collision | `Radius`, `Height` |
| Cylinder | `CylinderShape3D` | Pillars, area triggers | `Radius`, `Height` |

### 2.5D Sizing Convention

CrystalMagica is 2.5D: gameplay on X/Y plane, Z is depth only. All collision shapes must span the full Z-depth so objects always overlap along Z.

```csharp
// Platform collision -- matches Main.tscn convention
var platformShape = new BoxShape3D { Size = new Vector3(5.0f, 0.25f, 4.0f) };

// Player capsule -- CapsuleShape3D is inherently Z-symmetric

// Hitbox for melee attack -- box extending in front of player
var hitboxShape = new BoxShape3D { Size = new Vector3(1.5f, 1.0f, 4.0f) };
```

### Disabling Shapes at Runtime

```csharp
// Toggle individual shape
var shape = GetNode<CollisionShape3D>("Hitbox/CollisionShape3D");
shape.Disabled = true;   // stops detecting/blocking
shape.Disabled = false;  // resumes

// Toggle entire area's monitoring
var hitbox = GetNode<Area3D>("Hitbox");
hitbox.Monitoring = false;  // stops all detection
hitbox.Monitoring = true;   // resumes
```

Use `CollisionShape3D.Disabled` for shapes that toggle frequently (attack hitboxes).
Use `Area3D.Monitoring` when you want to pause all detection on an area.

---

## Collision Layer Management in C#

### Layer Constants Pattern

```csharp
public static class PhysicsLayers
{
    // Layer numbers (1-based, matching project.godot)
    public const int Environment = 1;
    public const int Player = 2;
    public const int PlayerHurtbox = 3;
    public const int PlayerHitbox = 4;
    public const int Enemy = 5;
    public const int EnemyHurtbox = 6;
    public const int EnemyHitbox = 7;
    public const int Projectiles = 8;
    public const int Pickups = 9;
    public const int Triggers = 10;
    public const int OneWayPlatforms = 11;

    // Bitmask helpers (0-based bit positions)
    public const uint EnvironmentBit = 1 << 0;
    public const uint PlayerBit = 1 << 1;
    public const uint OneWayPlatformsBit = 1 << 10;
}
```

### C# API -- Cheat Sheet

```csharp
// Set which layers this node IS ON (layer)
characterBody.CollisionLayer = 0;                           // clear all
characterBody.SetCollisionLayerValue(2, true);              // Player layer

// Set which layers this node DETECTS (mask)
characterBody.CollisionMask = 0;                            // clear all
characterBody.SetCollisionMaskValue(1, true);               // detect Environment
characterBody.SetCollisionMaskValue(11, true);              // detect OneWayPlatforms

// Bitmask math (when setting multiple at once)
characterBody.CollisionLayer = 1 << (2 - 1);               // layer 2 only
characterBody.CollisionMask = (1 << 0) | (1 << 10);        // layers 1 + 11

// Read a specific layer/mask bit
bool isOnPlayerLayer = characterBody.GetCollisionLayerValue(2);
bool detectsEnv = characterBody.GetCollisionMaskValue(1);
```

**Critical**: `SetCollisionLayerValue` / `SetCollisionMaskValue` use **1-based** layer numbers (1-32).
Bitmask integers use **0-based** bit positions: layer N = bit (N - 1).

### Static vs Runtime Configuration

Prefer `.tscn` (inspector) for static config. Use code only for runtime toggling.

```
# In Player.tscn -- static config
[node name="Player" type="CharacterBody3D"]
collision_layer = 2       # Player layer
collision_mask = 1025     # Environment (1) + OneWayPlatforms (1024)
```

```csharp
// In C# -- runtime toggling only
public void DisablePlatformCollision()
{
    SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, false);
}
```

### Mask Configuration Matrix

This matrix shows the **target configuration** for the full combat system. See the "Status" column for what exists today vs what is planned.

| Node | Layer (I am) | Mask (I detect) | Status |
|------|-------------|-----------------|--------|
| Player CharacterBody3D | 2 (Player) | 1 (Environment), 11 (OneWayPlatforms) | **Partial** -- Player.tscn sets layer=2, mask=1 (default). Layer 11 does not exist in project.godot yet. |
| Player Hurtbox (Area3D) | 3 (PlayerHurtbox) | 7 (EnemyHitbox) | **Planned** -- layers 3, 7 defined in project.godot but hurtbox node not wired yet |
| Player Hitbox (Area3D) | 4 (PlayerHitbox) | 6 (EnemyHurtbox) | **Planned** -- layers 4, 6 defined in project.godot but hitbox node not wired yet |
| Enemy CharacterBody3D | 5 (Enemy) | 1 (Environment) | **Planned** -- layer 5 not in project.godot yet (Loop 3) |
| Enemy Hurtbox (Area3D) | 6 (EnemyHurtbox) | 4 (PlayerHitbox), 8 (Projectiles) | **Planned** -- layers 6, 8 not in project.godot yet (Loop 3) |
| Enemy Hitbox (Area3D) | 7 (EnemyHitbox) | 3 (PlayerHurtbox) | **Planned** -- layer 7 not in project.godot yet (Loop 3) |

Hitboxes detect hurtboxes, not body layers. This keeps combat detection independent of physics movement.

---

## One-Way Platforms in 3D

Godot 4 has **no built-in one-way collision for 3D** (unlike 2D's `one_way_collision`). Implement via collision layer toggling.

### Architecture

```
World/Level/
  +-- Floor (StaticBody3D)           layer=1 (Environment)
  +-- PlatformA (StaticBody3D)       layer=11 (OneWayPlatforms)
      +-- Mesh (MeshInstance3D)
      +-- Collision (CollisionShape3D)
```

The player's CharacterBody3D mask includes layer 11 by default. To drop through, temporarily remove layer 11 from the player's mask.

### Down-Jump Implementation (Loop 3)

> **Prerequisite**: The `move_down` input action does **not** exist in `project.godot` yet. The current input map defines: `move_left`, `move_right`, `jump`, `run`, `quit`. Before using this pattern, add `move_down` to the input map (e.g., bound to S / Down arrow / gamepad D-pad down). Without it, `Input.IsActionJustPressed("move_down")` silently returns `false` and the drop-through never triggers.

```csharp
public partial class PlayerNode : CharacterBody3D
{
    private const float DropThroughDuration = 0.25f;
    private bool _isDroppingThrough;

    public override void _PhysicsProcess(double delta)
    {
        // ... existing gravity/movement ...

        if (IsOnFloor() && !_isDroppingThrough)
        {
            if (Input.IsActionJustPressed("move_down")
                && Input.IsActionJustPressed("jump"))
            {
                StartDropThrough();
            }
        }

        // ... MoveAndSlide() ...
    }

    private async void StartDropThrough()
    {
        _isDroppingThrough = true;

        // Remove one-way platform layer from mask
        SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, false);

        // Small downward nudge to clear the platform surface
        Velocity = Velocity with { Y = -2.0f };

        // Wait, then re-enable
        await ToSignal(
            GetTree().CreateTimer(DropThroughDuration),
            SceneTreeTimer.SignalName.Timeout);

        SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, true);
        _isDroppingThrough = false;
    }
}
```

### Why Layer Toggling (Not Shape Disabling)

| Approach | Pros | Cons |
|----------|------|------|
| Disable platform's CollisionShape3D | Simple | Affects ALL players (breaks multiplayer) |
| Toggle player's collision mask | Per-player, multiplayer safe | Toggles all platforms on that layer |
| Area3D velocity check | No layer toggling | Complex, frame-timing issues |

**Use mask toggling.** It is multiplayer-safe and one toggle handles every one-way platform.

### Edge Cases

- **Player inside platform when mask re-enables**: `MoveAndSlide()` pushes them out. Tune the timer so the player has fully cleared the platform.
- **Simultaneous down+jump**: Use `IsActionJustPressed` for both in the same frame.
- **Multiple platform types**: Assign different layers (11, 12) and toggle selectively.

---

## 2.5D Collision Constraints

CrystalMagica uses 3D nodes but gameplay is on the X/Y plane. Z is visual depth only.

### Rules

1. All collision shapes must have sufficient Z-depth (4.0 in CrystalMagica) so objects always overlap along Z.
2. Player and enemy movement never changes Z position.
3. Hitbox/hurtbox shapes use the same Z-depth as body collision shapes.
4. RayCast3D and ShapeCast3D `TargetPosition` should have Z = 0.
5. Camera is orthographic on Z -- perspective does not affect collision.

### Z-Depth in Shapes

```csharp
// Platform -- matches Main.tscn convention
var platformBox = new BoxShape3D { Size = new Vector3(5.0f, 0.25f, 4.0f) };

// Hitbox -- must span the same Z range
var hitboxBox = new BoxShape3D { Size = new Vector3(1.5f, 1.0f, 4.0f) };

// SphereShape3D: use Radius >= 2.0 for full Z coverage
// Prefer BoxShape3D for hitboxes where Z-depth control matters
```

---

## Anti-Patterns

### 1. Hitbox Always Active

Leaving `Monitoring = true` and `CollisionShape3D.Disabled = false` outside attack animations. The player damages enemies by walking near them. Always disable both when not attacking.

### 2. Layer/Mask Confusion

Setting the hitbox's **layer** to the enemy hurtbox layer instead of its **mask**. Layer = "I am." Mask = "I see."

### 3. Forgetting Z-Depth in 2.5D

`BoxShape3D.Size = new Vector3(1.5, 1.0, 0.1)` -- if the enemy is at Z=0.5, they never overlap a shape with depth 0.1. Always use full Z-depth (4.0).

### 4. Timer Lambda Instead of Async

```csharp
// BAD -- callback can fire after node is freed
GetTree().CreateTimer(0.25).Timeout += () => SetCollisionMaskValue(11, true);

// GOOD -- async tied to node lifetime
await ToSignal(GetTree().CreateTimer(0.25), SceneTreeTimer.SignalName.Timeout);
SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, true);
```

### 5. Polling Instead of Signals

Calling `GetOverlappingBodies()` in `_PhysicsProcess` when `BodyEntered`/`BodyExited` signals would suffice. Reserve polling for cases needing the full overlap list every frame.

### 6. Not Clearing Hit Tracking

Forgetting to clear the `HashSet<Node3D>` between attacks. Second swing misses already-hit enemies. See `references/attack-hitbox-pattern.md`.

### 7. Disabling Platform Shape for Drop-Through

Disabling the platform's `CollisionShape3D.Disabled = true` to let one player drop through removes the platform for ALL players in multiplayer. Toggle the individual player's mask instead.

### 8. Magic Number Layers

```csharp
// BAD
SetCollisionMaskValue(11, false);

// GOOD
SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, false);
```

---

## References

| File | Content |
|------|---------|
| `references/attack-hitbox-pattern.md` | Area3D attack hitbox enable/disable, hit tracking, enemy hurtbox setup |
| `references/raycast-shapecast.md` | RayCast3D ground/edge/wall detection, ShapeCast3D sweep patterns |

## Cross-References

This skill extends the collision layer strategy and body type selection covered in `godot-physics-3d`. Load that skill first for foundational 3D physics concepts; load this skill when the task involves Area3D overlap detection, hitbox/hurtbox patterns, or one-way platforms.

| Skill | When to Load |
|-------|-------------|
| `godot-physics-3d` | Collision layer strategy, CharacterBody3D movement physics, body type selection |
| `gamedev-3d-platformer` | Movement physics, coyote time, input buffering, state machine |
| `gamedev-godot` | Scene architecture, C# scripting, MCP server workflow |
| `gamedev-3d-ai` | Enemy patrol, pathfinding, behavior trees |
| `gamedev-multiplayer` | Netcode for hitbox/hurtbox replication |
| `server-authoritative-combat` | Server-side hit validation, lag compensation |
