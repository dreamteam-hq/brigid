---
name: godot-physics-3d
description: Godot 4.6 3D physics — CharacterBody3D, RigidBody3D, collision layers/masks, MoveAndSlide, raycasting, Areas, and multiplayer physics isolation
---

# Godot 4.6 3D Physics

## Body Type Selection

| Type | Use Case | Movement Model |
|---|---|---|
| **CharacterBody3D** | Player characters, NPCs | Code-driven via `MoveAndSlide()` |
| **RigidBody3D** | Crates, barrels, projectiles | Engine-driven via forces/impulses |
| **StaticBody3D** | Floors, walls, platforms | Immovable; no physics step cost |
| **Area3D** | Triggers, detection zones, damage areas | No collision response; emits signals |

**Rule of thumb**: if you control movement each frame, use CharacterBody3D. If physics should drive it, use RigidBody3D. If it never moves, StaticBody3D.

## Collision Layer Strategy

CrystalMagica layer assignments:

| Layer | Name | Purpose |
|---|---|---|
| 1 | Environment | Floors, walls, platforms |
| 2 | Player | Player CharacterBody3D |
| 3 | PlayerHurtbox | Receives damage |
| 4 | PlayerHitbox | Deals damage |

**Layer** = "what I am." **Mask** = "what I collide with."

- Player body: Layer 2, Mask 1 (collides with environment).
- PlayerHurtbox: Layer 3, Mask 4 (receives hits from hitboxes).
- Remote players use isolated layers to prevent local collision interference.

## CharacterBody3D + MoveAndSlide

CrystalMagica's `PlayerNode` extends `CharacterBody3D`. The physics loop:

```csharp
public override void _PhysicsProcess(double delta)
{
    var velocityBeforePhysics = Velocity;
    velocityBeforePhysics.Y -= gravity * (float)delta;  // apply gravity
    Velocity = velocityBeforePhysics;
    _ = MoveAndSlide();
}
```

Key rules:
- Set `Velocity` BEFORE calling `MoveAndSlide()`. The engine reads it, resolves collisions, and writes the corrected value back.
- `IsOnFloor()`, `IsOnWall()`, `IsOnCeiling()` are only valid AFTER `MoveAndSlide()` runs.
- Do NOT multiply `delta` on the `MoveAndSlide()` call itself — it handles time internally. Apply `delta` only when modifying velocity (e.g., gravity).
- Discard the `MoveAndSlide()` return value (`_ =`) — query `IsOnFloor()` etc. instead.

## Gravity and Jump

CrystalMagica pattern — gravity applied every frame, jump adds upward velocity:

```csharp
// Gravity (in _PhysicsProcess)
velocityBeforePhysics.Y -= gravity * (float)delta;

// Jump (only when grounded)
if (Input.IsActionJustPressed("jump") && IsOnFloor())
    Velocity = Velocity with { Y = Velocity.Y + jumpVelocity };

// Horizontal movement via pattern matching
Velocity = Velocity with { X = speed };

// Stop horizontal
Velocity = Velocity with { X = 0 };
```

Default values: `gravity = 22f`, `jumpVelocity = 9f`, `walkSpeed = 5f`.

For sidescroller, clamp Z drift: `Position = Position with { Z = 0f }`.

C# `with` expressions on Vector3 are clean for modifying single axes without touching others.

## RigidBody3D

For server-spawned physics objects (crates, barrels, destructibles):

- **Freeze**: set `Freeze = true` to disable physics until needed (e.g., spawn frozen, unfreeze on interaction).
- **Tuning**: `Mass`, `PhysicsMaterialOverride.Friction`, `PhysicsMaterialOverride.Bounce`.
- **Forces**: `ApplyForce(vector)` for sustained push, `ApplyImpulse(vector)` for one-shot hit.
- **Axis locks**: `AxisLockLinearZ = true` for sidescroller constraint. Also `AxisLockAngularX/Y` to prevent unwanted tumbling.
- **Server authority**: server spawns and owns RigidBody3D nodes; clients receive state updates.

## Raycasting and Shape Queries

**RayCast3D node** — persistent ray, updated each physics frame. Enable in `_Ready()`, query `IsColliding()` / `GetCollider()`.

**One-shot ray query** — no node needed:

```csharp
var spaceState = GetWorld3D().DirectSpaceState;
var query = PhysicsRayQueryParameters3D.Create(origin, target);
query.CollisionMask = 0b0001; // only Layer 1 (environment)
var result = spaceState.IntersectRay(query);
if (result.Count > 0)
{
    var hitPosition = (Vector3)result["position"];
    var hitNormal = (Vector3)result["normal"];
}
```

**ShapeCast3D** — swept collision test (wider than a ray). Use for ground detection, area scanning, or hitbox validation before applying damage.

Set `CollisionMask` on queries to filter what they detect — same layer/mask logic as bodies.

## Multiplayer Physics

CrystalMagica's approach:

1. **Local player** runs full input + physics (`LocalPlayerNode._PhysicsProcess` reads input, calls `Jump()`/`MoveBegin()`, then `base._PhysicsProcess()` which calls `MoveAndSlide()`).
2. **Remote players** receive action messages (Jump, MoveBegin, Stop) and replay them through the same `PlayerNode` methods — same `MoveAndSlide()` path yields approximately deterministic results.
3. **Server snapshots** periodically correct drift with authoritative position.
4. **Physics isolation**: remote players on separate collision layers so their `MoveAndSlide()` does not interfere with local player collisions.
5. **Deferred activation**: `SetPhysicsProcess(false)` in `_Ready()`, enable only after `Bind()` connects a ViewModel — prevents physics running on uninitialized nodes.
