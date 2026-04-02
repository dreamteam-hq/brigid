---
name: Godot Physics Patterns
description: Godot 4.6 physics system — collision layers/masks, physics bodies, raycasting, Areas, server-authoritative physics for multiplayer
triggers:
  - physics
  - collision
  - collision layer
  - collision mask
  - CharacterBody
  - RigidBody
  - StaticBody
  - MoveAndSlide
  - raycast
  - physics body
category: gamedev
---

# Godot 4.6 C# Physics Patterns

## 1. Body Type Selection

| Body Type | Use Case | Movement Model | Collision Response |
|---|---|---|---|
| `CharacterBody3D` | Player characters, NPCs | Code-driven via `MoveAndSlide()` | Slides along surfaces |
| `RigidBody3D` | Crates, projectiles, ragdolls | Physics engine (forces/impulses) | Bounce, friction, stacking |
| `StaticBody3D` | Floors, walls, platforms | Immovable (or `AnimatableBody3D`) | Infinite mass |
| `Area3D` | Triggers, pickups, detection zones | No collision response | Overlap signals only |

Use `CharacterBody3D` for precise control, `RigidBody3D` for engine-driven physics, `Area3D` for non-blocking detection (hurtboxes, aggro ranges).

## 2. Collision Layer Strategy

Godot provides 32 collision layers. **Layer** = "what this object IS." **Mask** = "what this object SCANS FOR / collides with."

**CrystalMagica layer assignments:**

| Layer | Name | Example Nodes |
|---|---|---|
| 1 | Environment | Floors, walls, platforms |
| 2 | Player | Local player CharacterBody3D |
| 3 | PlayerHurtbox | Area3D receiving damage |
| 4 | PlayerHitbox | Area3D for player attacks |

**Remote player isolation:** Remote players use their own layer (e.g., Layer 10) with NO mask against the local player. Prevents interpolation jitter from pushing the local player. Remote players only mask against Environment.

Set in code: `CollisionLayer = 1 << (layerNum - 1);` and `CollisionMask = (1 << 0) | (1 << 1);` for layers 1+2.

## 3. MoveAndSlide

**Pattern:**
```csharp
// In _PhysicsProcess(double delta):
Vector3 velocity = Velocity;
velocity.Y -= gravity * (float)delta;       // apply gravity
velocity.X = inputDir * speed;              // apply horizontal input
Velocity = velocity;
MoveAndSlide();                             // engine resolves collisions
```

**Key rules:**
- Set `Velocity` BEFORE calling `MoveAndSlide()`. Engine reads it, resolves collisions, writes corrected value back.
- `IsOnFloor()`, `IsOnWall()`, `IsOnCeiling()` are only valid AFTER `MoveAndSlide()`.
- Multiply velocity changes by `delta` (gravity, acceleration). Do NOT multiply `MoveAndSlide()` itself — it handles the timestep internally.
- `GetSlideCollisionCount()` and `GetSlideCollision(i)` give details from the last call.

## 4. Gravity and Jump Physics

```csharp
float gravity = 980f, jumpVelocity = -350f;
float jumpCutFactor = 0.5f, fallGravityMult = 1.5f, maxFallSpeed = 600f;

public override void _PhysicsProcess(double delta)
{
    Vector3 vel = Velocity;
    float grav = vel.Y > 0 ? gravity * fallGravityMult : gravity; // heavier falling
    vel.Y += grav * (float)delta;
    vel.Y = Mathf.Min(vel.Y, maxFallSpeed);

    if (Input.IsActionJustPressed("jump") && IsOnFloor())
        vel.Y = jumpVelocity;
    if (Input.IsActionJustReleased("jump") && vel.Y < 0)  // jump cut for short hop
        vel.Y *= jumpCutFactor;

    Velocity = vel;
    MoveAndSlide();
}
```

## 5. One-Way Platforms

Enable `one_way_collision` on the `CollisionShape3D` of a `StaticBody3D`. Passable from below, solid from above.

**Drop-through:** Temporarily disable collision with the platform:
```csharp
AddCollisionExceptionWith(platformBody);
await ToSignal(GetTree().CreateTimer(0.2), "timeout");
RemoveCollisionExceptionWith(platformBody);
```

## 6. PhysicsServer Direct API

Use `PhysicsServer3D` for shape queries, raycasts outside the scene tree, or custom collision detection:
```csharp
var spaceState = GetWorld3D().DirectSpaceState;
var query = PhysicsRayQueryParameters3D.Create(origin, target);
query.CollisionMask = 0b0001; // only layer 1
var result = spaceState.IntersectRay(query);
if (result.Count > 0)
{
    Vector3 hitPos = (Vector3)result["position"];
    GodotObject collider = (GodotObject)result["collider"];
}
```

**When to use:** line-of-sight, area-of-interest (`IntersectShape`), hitbox validation outside `_PhysicsProcess`, queries without scene tree nodes.

## 7. Multiplayer Physics

**CrystalMagica pattern:**
- **Local player:** Full physics via `MoveAndSlide()` with local input. Server snapshots provide authoritative position; blend toward it to correct drift.
- **Remote players:** Run `MoveAndSlide()` with replayed server input. Do NOT just lerp position — it skips collision and causes clipping.
- **Layer isolation:** Remote players on a separate collision layer with no mask against local player. Prevents desync from physically pushing the local character.
- **Server authority:** Server validates positions, sends corrections. Client blends correction over several frames (hard snap only if error exceeds ~2 tiles).
