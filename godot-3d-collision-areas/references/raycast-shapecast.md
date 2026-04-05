# RayCast3D & ShapeCast3D Detection Patterns

Reference material for `godot-3d-collision-areas`. See SKILL.md for core collision concepts.

## RayCast3D -- Point Detection

RayCast3D casts a single ray from its position to `TargetPosition` (relative), detecting the first intersection. Cheap, runs every physics frame when `Enabled = true`.

### Key Properties

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `Enabled` | bool | true | Active when true |
| `TargetPosition` | Vector3 | (0, -1, 0) | Ray endpoint relative to node |
| `CollisionMask` | uint | 1 | Which layers to detect |
| `CollideWithAreas` | bool | false | Detect Area3D nodes |
| `CollideWithBodies` | bool | true | Detect PhysicsBody3D nodes |
| `HitFromInside` | bool | false | Detect if ray starts inside a shape |
| `HitBackFaces` | bool | true | Detect back faces of collision shapes |

### Key Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `IsColliding()` | bool | Whether the ray hit anything |
| `GetCollider()` | GodotObject | The colliding object |
| `GetCollisionPoint()` | Vector3 | Global position of hit |
| `GetCollisionNormal()` | Vector3 | Surface normal at hit point |
| `GetColliderRid()` | Rid | Physics body RID |
| `ForceRaycastUpdate()` | void | Immediate update (skip frame wait) |

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

// If the ray ahead of movement is NOT colliding, there is a ledge
if (movingRight && !rightRay.IsColliding())
{
    movingRight = false;  // reverse -- platform edge ahead
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
    // Wall ahead -- reverse patrol direction
}
```

### ForceRaycastUpdate()

RayCast3D updates once per physics frame. If you move or reconfigure a raycast and need immediate results:

```csharp
groundRay.TargetPosition = new Vector3(0, -2.0f, 0);
groundRay.ForceRaycastUpdate();
if (groundRay.IsColliding())
{
    // Result is now current
}
```

---

## ShapeCast3D -- Sweep Detection

ShapeCast3D sweeps a shape from its position to `TargetPosition`, detecting **all** intersections along the path. More expensive than RayCast3D but detects area, not just a line.

### Key Properties

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `Shape` | Shape3D | null | The shape to sweep (BoxShape3D, SphereShape3D, etc.) |
| `TargetPosition` | Vector3 | (0, -1, 0) | Sweep endpoint relative to node |
| `Margin` | float | 0.0 | Collision buffer -- larger = more reliable, less precise |
| `MaxResults` | int | 32 | Maximum intersections to report |
| `CollisionMask` | uint | 1 | Which layers to detect |
| `CollideWithAreas` | bool | false | Detect Area3D nodes |
| `CollideWithBodies` | bool | true | Detect PhysicsBody3D nodes |

### Key Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `IsColliding()` | bool | Whether anything was hit |
| `GetCollisionCount()` | int | Number of intersections |
| `GetCollider(index)` | GodotObject | Collider at index |
| `GetCollisionPoint(index)` | Vector3 | Global hit point at index |
| `GetCollisionNormal(index)` | Vector3 | Surface normal at index |
| `GetClosestCollisionSafeFraction()` | float | 0-1 fraction where shape first collides |
| `GetClosestCollisionUnsafeFraction()` | float | 0-1 fraction just before collision |
| `ForceShapecastUpdate()` | void | Immediate update (skip frame wait) |

### Attack Sweep Pattern

```csharp
// ShapeCast3D with a BoxShape3D, sweeping in front of the player
// Shape = BoxShape3D(Size: 1.0, 1.0, 4.0)
// TargetPosition = new Vector3(2.0f, 0, 0) -- sweep 2 units forward
// CollisionMask = EnemyHurtbox layer
// CollideWithAreas = true (to detect Area3D hurtboxes)
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

### Instant Area Query (No Sweep)

Set `TargetPosition = Vector3.Zero` to test overlap at the current position without sweeping:

```csharp
attackSweep.TargetPosition = Vector3.Zero;
attackSweep.ForceShapecastUpdate();
// Now checking "what is overlapping right here, right now"
```

---

## ShapeCast3D vs Area3D for Hitboxes

| Criteria | ShapeCast3D | Area3D |
|----------|-------------|--------|
| Detection type | Instantaneous sweep (one frame) | Continuous overlap (enter/exit signals) |
| Best for | Fast attacks, dashes, ground pounds | Lingering hitboxes, damage zones, traps |
| Multiple hits | Returns all colliders in one call | Fires signal per body |
| Performance | More expensive per query | Cheaper per frame (physics engine tracks) |
| Frame timing | Explicit -- call `ForceShapecastUpdate()` | Implicit -- fires on physics frame |

**Use Area3D** for standard melee attacks (active for several frames).
**Use ShapeCast3D** for instant-hit attacks, ground slams, or "did I hit anything in this arc" queries.

---

## 2.5D Constraints for Raycasts

In CrystalMagica (2.5D), all raycasts and shapecasts should have Z = 0 in their `TargetPosition`:

```csharp
// GOOD -- stays in X/Y plane
groundRay.TargetPosition = new Vector3(0, -1.5f, 0);
wallRay.TargetPosition = new Vector3(1.0f, 0, 0);

// BAD -- casting along Z axis in a 2.5D game
wallRay.TargetPosition = new Vector3(0, 0, 1.0f);
```

ShapeCast3D shapes should use Z-depth = 4.0 (matching all other collision shapes) to ensure reliable detection across the gameplay plane.
