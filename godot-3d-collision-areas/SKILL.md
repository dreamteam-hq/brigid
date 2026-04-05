---
name: godot-3d-collision-areas
description: >
  Godot 4.6 3D collision system — Area3D signals, CollisionShape3D primitives,
  collision layer/mask management, ShapeCast3D sweep testing, RayCast3D detection,
  one-way platform patterns via layer toggling, down-jump implementation, and
  attack hitbox patterns. All C# / .NET 10. 2.5D focus (X/Y gameplay, Z depth).
  Triggers: collision, Area3D, hitbox, hurtbox, one-way platform, down jump,
  collision layer, collision mask, ShapeCast3D, RayCast3D, attack area.
scope: consumer
metadata:
  category: reference
  tags:
    domain: [gamedev, godot]
    depth: intermediate
    pipeline: build
provenance:
  origin: authored
  source: brigid-agent
  imported_at: 2026-04-05
  trust_level: vetted
quality: production
lifecycle:
  status: active
  created: 2026-04-05
---

# Godot 4.6 3D Collision & Areas (C#)

## Quick Reference

### Collision Node Types

| Node | Purpose | Detects Via | Use For |
|------|---------|-------------|---------|
| CharacterBody3D | Physics body with `MoveAndSlide()` | Collision layer/mask | Player, enemies, NPCs |
| StaticBody3D | Immovable geometry | Collision layer/mask | Floors, walls, platforms |
| RigidBody3D | Physics-simulated body | Collision layer/mask | Crates, projectiles |
| Area3D | Overlap detection (no physics) | Signals + layer/mask | Hitboxes, hurtboxes, triggers, zones |
| RayCast3D | Single-ray intersection test | Mask only | Ground detection, line of sight |
| ShapeCast3D | Shape sweep intersection test | Mask only | Wide attack sweeps, ledge detection |

### Layer vs Mask — One Sentence

**Layer** = "I exist on these layers." **Mask** = "I detect objects on these layers."

A collision occurs when **A's mask overlaps B's layer** OR **B's mask overlaps A's layer**.

### CrystalMagica Collision Layers

From `project.godot` — these are the active assignments:

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

### C# Layer Management — Cheat Sheet

```csharp
// Set which layers this node IS ON (layer)
characterBody.CollisionLayer = 0;                           // Clear all
characterBody.SetCollisionLayerValue(2, true);              // Player layer

// Set which layers this node DETECTS (mask)
characterBody.CollisionMask = 0;                            // Clear all
characterBody.SetCollisionMaskValue(1, true);               // Detect Environment
characterBody.SetCollisionMaskValue(11, true);              // Detect OneWayPlatforms

// Bitmask math (when setting multiple at once)
characterBody.CollisionLayer = 1 << (2 - 1);               // Layer 2 only
characterBody.CollisionMask = (1 << 0) | (1 << 10);        // Layers 1 + 11

// Read a specific layer/mask bit
bool isOnPlayerLayer = characterBody.GetCollisionLayerValue(2);
bool detectsEnvironment = characterBody.GetCollisionMaskValue(1);
```

Layer numbers in `SetCollisionLayerValue()` / `SetCollisionMaskValue()` are **1-based** (1 through 32).
Bitmask integers use **0-based** bit positions: layer N = bit (N - 1).

---

## Area3D — Overlap Detection

Area3D detects when physics bodies or other areas enter/exit its collision shape. It does not block movement.

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

**Rule**: A hitbox needs `Monitoring = true` (it detects). A hurtbox needs `Monitorable = true` (it gets detected). Set both to true unless you have a reason to optimize.

### Signals

| Signal | Parameter | Fires When |
|--------|-----------|------------|
| `BodyEntered` | `Node3D body` | A PhysicsBody3D enters the area |
| `BodyExited` | `Node3D body` | A PhysicsBody3D leaves the area |
| `AreaEntered` | `Area3D area` | Another Area3D enters overlap |
| `AreaExited` | `Area3D area` | Another Area3D leaves overlap |
| `BodyShapeEntered` | `Rid bodyRid, Node3D body, long bodyShapeIndex, long localShapeIndex` | Per-shape granularity |
| `BodyShapeExited` | `Rid bodyRid, Node3D body, long bodyShapeIndex, long localShapeIndex` | Per-shape granularity |

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
// Poll overlaps instead of using signals — useful for per-frame checks
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

Overlap queries update once per physics frame. Call `ForceUpdateOverlaps()` if you need immediate results after moving a shape.

---

## CollisionShape3D — Shape Primitives

Every collision-aware node (CharacterBody3D, StaticBody3D, Area3D) needs at least one CollisionShape3D child.

### Shape Types

| Shape | Class | Best For | Sizing |
|-------|-------|----------|--------|
| Box | `BoxShape3D` | Platforms, walls, rectangular hitboxes | `Size = new Vector3(width, height, depth)` |
| Sphere | `SphereShape3D` | Radial triggers, pickup zones, explosions | `Radius = float` |
| Capsule | `CapsuleShape3D` | Player/enemy body collision | `Radius = float`, `Height = float` |
| Cylinder | `CylinderShape3D` | Pillars, area triggers | `Radius = float`, `Height = float` |

### 2.5D Sizing Convention

CrystalMagica is 2.5D: gameplay on X/Y plane, Z is visual depth only. All collision shapes must span the full Z-depth of gameplay to prevent objects from missing each other along Z.

```csharp
// Platform collision — wide X, thin Y, full Z-depth
var platformShape = new BoxShape3D();
platformShape.Size = new Vector3(5.0f, 0.25f, 4.0f);  // matches Main.tscn pattern

// Player body — CapsuleShape3D already Z-symmetric
// CrystalMagica uses: Radius = 0.4, Height = 1.8

// Hitbox for melee attack — box extending in front of player
var hitboxShape = new BoxShape3D();
hitboxShape.Size = new Vector3(1.5f, 1.0f, 4.0f);  // wide Z to catch enemies
```

### Disabling Shapes at Runtime

```csharp
var collisionShape = GetNode<CollisionShape3D>("Hitbox/CollisionShape3D");

// Disable — shape stops detecting/blocking
collisionShape.Disabled = true;

// Enable — shape resumes
collisionShape.Disabled = false;

// Alternative: toggle the parent Area3D's monitoring
var hitbox = GetNode<Area3D>("Hitbox");
hitbox.Monitoring = false;  // Stops detecting
hitbox.Monitoring = true;   // Resumes detecting
```

Use `CollisionShape3D.Disabled` for shapes that toggle frequently (attack hitboxes).
Use `Area3D.Monitoring` when you want to pause all detection on an area.

---

## Collision Layer Management in C#

### Layer Constants Pattern

Define layer numbers as constants to avoid magic numbers throughout the codebase.

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

### Configuring Layers in Code vs Inspector

Prefer setting layers in the `.tscn` file (inspector) for static configuration. Use code only for runtime toggling.

```
# In Player.tscn — static config
[node name="Player" type="CharacterBody3D"]
collision_layer = 2       # Player layer
collision_mask = 1025     # Environment (1) + OneWayPlatforms (1024) = bit 0 + bit 10
```

```csharp
// In C# — runtime toggling only
public void DisablePlatformCollision()
{
    SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, false);
}

public void EnablePlatformCollision()
{
    SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, true);
}
```

### Mask Configuration Matrix

| Node | Layer (I am) | Mask (I detect) |
|------|-------------|-----------------|
| Player CharacterBody3D | 2 (Player) | 1 (Environment), 11 (OneWayPlatforms) |
| Player Hurtbox (Area3D) | 3 (PlayerHurtbox) | 7 (EnemyHitbox) |
| Player Hitbox (Area3D) | 4 (PlayerHitbox) | 6 (EnemyHurtbox) |
| Enemy CharacterBody3D | 5 (Enemy) | 1 (Environment) |
| Enemy Hurtbox (Area3D) | 6 (EnemyHurtbox) | 4 (PlayerHitbox), 8 (Projectiles) |
| Enemy Hitbox (Area3D) | 7 (EnemyHitbox) | 3 (PlayerHurtbox) |
| Projectile (Area3D) | 8 (Projectiles) | 1 (Environment), 6 (EnemyHurtbox) |

Hitboxes detect hurtboxes, not body layers. This keeps combat detection independent of physics movement.

---

## One-Way Platforms in 3D

Godot 4 has no built-in one-way collision for 3D (unlike 2D's `one_way_collision` property). Implement via collision layer toggling.

### Architecture

```
World/Level/
  +-- Floor (StaticBody3D)           layer=1 (Environment)
  +-- PlatformA (StaticBody3D)       layer=11 (OneWayPlatforms)
      +-- Mesh (MeshInstance3D)
      +-- Collision (CollisionShape3D)
```

The player's CharacterBody3D mask includes layer 11 (OneWayPlatforms) by default. To drop through, temporarily remove layer 11 from the player's mask.

### Down-Jump Implementation (Loop 3)

```csharp
public partial class PlayerNode : CharacterBody3D
{
    private const float DropThroughDuration = 0.25f;
    private bool _isDroppingThrough;

    public override void _PhysicsProcess(double delta)
    {
        // ... existing gravity/movement code ...

        if (IsOnFloor() && !_isDroppingThrough)
        {
            if (Input.IsActionJustPressed("move_down") && Input.IsActionJustPressed("jump"))
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
        var vel = Velocity;
        vel.Y = -2.0f;
        Velocity = vel;

        // Wait, then re-enable
        await ToSignal(GetTree().CreateTimer(DropThroughDuration), SceneTreeTimer.SignalName.Timeout);

        SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, true);
        _isDroppingThrough = false;
    }
}
```

### Why Layer Toggling Over Shape Disabling

| Approach | Pros | Cons |
|----------|------|------|
| Disable platform's CollisionShape3D | Simple, per-platform | Affects ALL players (multiplayer broken) |
| Toggle player's collision mask | Per-player, multiplayer safe | One toggle affects all platforms of that layer |
| Area3D velocity check | No layer toggling needed | Complex, potential frame-timing issues |

**Use mask toggling.** It is multiplayer-safe (each player controls their own mask) and one toggle handles every one-way platform in the scene.

### Edge Cases

**Player lands on platform during drop-through timer**: The timer re-enables the mask after 0.25s. If the player is still inside the platform's collision shape when the mask re-enables, `MoveAndSlide()` will push them out. Tune the timer so the player has fully cleared the platform.

**Simultaneous down+jump input**: Use `IsActionJustPressed` for both inputs in the same frame. If using input buffering, check the buffer in the same conditional.

**Multiple one-way platform layers**: If different platform types need independent toggling (e.g., thin vs thick platforms), assign them to different layers (11, 12) and toggle selectively.

---

## Attack Hitbox Pattern (Loop 5)

### Scene Structure

```
Player (CharacterBody3D)               layer=2
  +-- Collision (CollisionShape3D)      # physics body
  +-- Mesh (MeshInstance3D)
  +-- AttackHitbox (Area3D)             layer=4 (PlayerHitbox), mask=6 (EnemyHurtbox)
      +-- CollisionShape3D              # disabled by default
  +-- Hurtbox (Area3D)                  layer=3 (PlayerHurtbox), mask=7 (EnemyHitbox)
      +-- CollisionShape3D              # always active
```

### Enable/Disable on Attack

```csharp
public partial class PlayerNode : CharacterBody3D
{
    private Area3D _attackHitbox;
    private CollisionShape3D _attackShape;
    private bool _isAttacking;

    public override void _Ready()
    {
        _attackHitbox = GetNode<Area3D>("AttackHitbox");
        _attackShape = _attackHitbox.GetNode<CollisionShape3D>("CollisionShape3D");

        // Start disabled
        _attackHitbox.Monitoring = false;
        _attackShape.Disabled = true;

        // Connect signal for hit detection
        _attackHitbox.AreaEntered += OnAttackHit;
    }

    public void StartAttack()
    {
        if (_isAttacking) return;

        _isAttacking = true;
        _attackHitbox.Monitoring = true;
        _attackShape.Disabled = false;

        // Position hitbox in front of player based on facing direction
        float facing = /* 1.0f or -1.0f based on direction */;
        _attackHitbox.Position = new Vector3(facing * 0.8f, 0.0f, 0.0f);
    }

    public async void EndAttack()
    {
        _attackHitbox.Monitoring = false;
        _attackShape.Disabled = true;
        _isAttacking = false;
    }

    private void OnAttackHit(Area3D area)
    {
        // area is an enemy hurtbox — get the enemy node
        if (area.GetParent() is CharacterBody3D enemy)
        {
            // Apply damage, knockback, etc.
            GD.Print($"Hit enemy: {enemy.Name}");
        }
    }
}
```

### Hit Registration — Single-Hit vs Multi-Hit

For a single-hit attack (sword slash), track which enemies were already hit this swing:

```csharp
private readonly HashSet<Node3D> _hitThisSwing = new();

private void OnAttackHit(Area3D area)
{
    var enemy = area.GetParent() as CharacterBody3D;
    if (enemy == null || _hitThisSwing.Contains(enemy)) return;

    _hitThisSwing.Add(enemy);
    // Apply damage once
}

public void StartAttack()
{
    _hitThisSwing.Clear();
    // ... enable hitbox ...
}
```

For a multi-hit attack (spinning), skip the `HashSet` — let each overlap frame deal damage (with a per-enemy cooldown).

### Enemy Hurtbox Setup

```
Enemy (CharacterBody3D)                 layer=5 (Enemy)
  +-- Collision (CollisionShape3D)      # physics body
  +-- EnemyMesh (MeshInstance3D)
  +-- Hurtbox (Area3D)                  layer=6 (EnemyHurtbox), mask=4 (PlayerHitbox)
      +-- CollisionShape3D              # always active
  +-- Hitbox (Area3D)                   layer=7 (EnemyHitbox), mask=3 (PlayerHurtbox)
      +-- CollisionShape3D              # active during enemy attacks
```

---

## RayCast3D — Point Detection

### Ground Detection

```csharp
// RayCast3D child of CharacterBody3D, pointing downward
// TargetPosition = new Vector3(0, -0.1f, 0)
// CollisionMask = Environment layer

var groundRay = GetNode<RayCast3D>("GroundRay");
if (groundRay.IsColliding())
{
    Vector3 groundPoint = groundRay.GetCollisionPoint();
    Vector3 groundNormal = groundRay.GetCollisionNormal();
    Node3D groundObject = groundRay.GetCollider() as Node3D;
}
```

### Edge Detection for Enemy Patrol AI

```csharp
// Two RayCast3D nodes at the enemy's feet, slightly ahead of each side
// LeftEdgeRay:  Position = (-0.5, 0, 0), TargetPosition = (0, -1.5, 0)
// RightEdgeRay: Position = (0.5, 0, 0),  TargetPosition = (0, -1.5, 0)

var leftRay = GetNode<RayCast3D>("LeftEdgeRay");
var rightRay = GetNode<RayCast3D>("RightEdgeRay");

// If the ray ahead of the movement direction is NOT colliding, there is a ledge
if (movingRight && !rightRay.IsColliding())
{
    // Reverse direction — platform edge ahead
    movingRight = false;
}
else if (!movingRight && !leftRay.IsColliding())
{
    movingRight = true;
}
```

### Wall Detection

```csharp
// RayCast3D pointing forward from the enemy
// TargetPosition = new Vector3(1.0f, 0, 0) for right-facing
// CollisionMask = Environment layer

var wallRay = GetNode<RayCast3D>("WallRay");
if (wallRay.IsColliding())
{
    // Wall ahead — reverse patrol direction
}
```

### Important: ForceRaycastUpdate()

RayCast3D updates once per physics frame. If you move a raycast and need immediate results in the same frame:

```csharp
groundRay.ForceRaycastUpdate();
if (groundRay.IsColliding())
{
    // Result is now current
}
```

---

## ShapeCast3D — Sweep Detection

ShapeCast3D sweeps a shape from its position to `TargetPosition`, detecting all intersections along the path. More expensive than RayCast3D but detects area, not just a line.

### Attack Sweep Pattern

```csharp
// ShapeCast3D with a BoxShape3D, sweeping in front of the player
// Shape = BoxShape3D(Size: 1.0, 1.0, 4.0)
// TargetPosition = new Vector3(2.0f, 0, 0)  — sweep 2 units forward
// CollisionMask = EnemyHurtbox layer
// CollideWithAreas = true  (to detect Area3D hurtboxes)
// CollideWithBodies = false

var attackSweep = GetNode<ShapeCast3D>("AttackSweep");
attackSweep.ForceShapecastUpdate();

if (attackSweep.IsColliding())
{
    for (int i = 0; i < attackSweep.GetCollisionCount(); i++)
    {
        var collider = attackSweep.GetCollider(i) as Node3D;
        Vector3 hitPoint = attackSweep.GetCollisionPoint(i);
        // Process hit
    }
}
```

### ShapeCast3D vs Area3D for Hitboxes

| Criteria | ShapeCast3D | Area3D |
|----------|-------------|--------|
| Detection type | Instantaneous sweep (one frame) | Continuous overlap (enter/exit signals) |
| Best for | Fast attacks, dashes, ground pounds | Lingering hitboxes, damage zones, traps |
| Multiple hits | Returns all colliders in one call | Fires signal per body |
| Performance | More expensive per query | Cheaper per frame (physics engine tracks) |
| Frame timing | Explicit — call `ForceShapecastUpdate()` | Implicit — fires on physics frame |

**Use Area3D** for standard melee attacks (active for several frames).
**Use ShapeCast3D** for instant-hit attacks, ground slams, or "did I hit anything in this arc" queries.

---

## 2.5D Collision Constraints

CrystalMagica uses 3D nodes (CharacterBody3D, Area3D) but gameplay is on the X/Y plane. Z is visual depth only.

### Rules

1. All collision shapes must have sufficient Z-depth (4.0 in CrystalMagica) so objects always overlap along Z.
2. Player and enemy movement never changes Z position.
3. Hitbox/hurtbox shapes use the same Z-depth as body collision shapes.
4. RayCast3D and ShapeCast3D target positions should have Z = 0.
5. Camera is orthographic on the Z axis — perspective does not affect collision.

### Z-Depth in Shapes

```csharp
// Platform collision — matches Main.tscn convention
var platformBox = new BoxShape3D { Size = new Vector3(5.0f, 0.25f, 4.0f) };

// Hitbox — must span the same Z range
var hitboxBox = new BoxShape3D { Size = new Vector3(1.5f, 1.0f, 4.0f) };

// Sphere shapes are inherently Z-symmetric — use Radius >= 2.0 for full Z coverage
// Or prefer BoxShape3D for hitboxes where Z-depth control matters
```

---

## Anti-Patterns

### 1. Hitbox Always Active

Leaving attack Area3D `Monitoring = true` and `CollisionShape3D.Disabled = false` outside of attack animations. The player damages enemies by walking near them. Always disable both `Monitoring` and the shape when not attacking.

### 2. Layer/Mask Confusion

Setting the hitbox's **layer** to the enemy hurtbox layer instead of its **mask**. The hitbox should exist on the PlayerHitbox layer and **detect** the EnemyHurtbox layer. Layer = "I am." Mask = "I see."

### 3. Forgetting Z-Depth in 2.5D

Creating a hitbox with `BoxShape3D.Size = new Vector3(1.5, 1.0, 0.1)` in a 2.5D game. If the enemy is at Z=0.5 and the hitbox is at Z=0.0 with depth 0.1, they never overlap. Always use full Z-depth (4.0 in CrystalMagica).

### 4. Using Timer Instead of Async for Drop-Through

```csharp
// BAD — timer callback can fire after node is freed
GetTree().CreateTimer(0.25).Timeout += () => { SetCollisionMaskValue(11, true); };

// GOOD — async tied to node lifetime
await ToSignal(GetTree().CreateTimer(0.25), SceneTreeTimer.SignalName.Timeout);
SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, true);
```

### 5. Polling Overlaps Every Frame Instead of Using Signals

Calling `GetOverlappingBodies()` in `_PhysicsProcess` when a signal would suffice. Use signals for enter/exit events. Reserve polling for cases where you need the full overlap list every frame (rare).

### 6. Not Clearing Hit Tracking Between Attacks

Forgetting to clear the `HashSet<Node3D>` of hit enemies when starting a new attack. The second swing misses enemies that were hit by the first.

### 7. Disabling Platform Collision Shape Instead of Player Mask

Disabling the platform's `CollisionShape3D.Disabled = true` to let one player drop through. In multiplayer, this removes the platform for ALL players. Toggle the individual player's mask instead.

### 8. Magic Number Layers

```csharp
// BAD
SetCollisionMaskValue(11, false);

// GOOD
SetCollisionMaskValue(PhysicsLayers.OneWayPlatforms, false);
```

---

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-2d-platformer` | Movement physics, coyote time, input buffering, state machine, camera systems |
| `gamedev-godot` | Scene architecture, C# scripting fundamentals, MCP server workflow |
| `gamedev-2d-ai` | Enemy patrol patterns, pathfinding, behavior trees using RayCast for detection |
| `gamedev-multiplayer` | Netcode for hitbox/hurtbox replication, server-authoritative combat |
| `server-authoritative-combat` | Server-side hit validation, lag compensation for attack detection |
