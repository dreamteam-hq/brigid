---
name: gamedev-3d-platformer
description: 3D sidescroller platformer mechanics in Godot 4.6 C# — CharacterBody3D movement, gravity, jump physics, state machines, camera, collision layers, and multiplayer replay
---

# 3D Sidescroller Platformer Mechanics (Godot 4.6 C#)

## CharacterBody3D Movement

- All movement through `Velocity` property + `MoveAndSlide()` in `_PhysicsProcess(double delta)`.
- `IsOnFloor()`, `IsOnWall()`, `IsOnCeiling()` reflect the result of the most recent `MoveAndSlide()` — typically read at the start of the next `_PhysicsProcess` frame, before the current frame's `MoveAndSlide()`.
- Apply gravity each frame: `velocityBeforePhysics.Y -= gravity * (float)delta` where `gravity` is a positive value (CrystalMagica default: `22f`).
- Horizontal movement: set `Velocity.X` from input direction * speed.
- **Sidescroller constraint**: if Z drift occurs, clamp with `Position = Position with { Z = 0f }` and `Velocity = Velocity with { Z = 0f }` each physics frame.
- `UpDirection = Vector3.Up` (default) — required for `IsOnFloor()` to work.

## Jump Physics

- On jump press while `IsOnFloor()`: `Velocity = Velocity with { Y = Velocity.Y + jumpVelocity }` (adds to current Y).
- **Jump cut**: on jump release while `Velocity.Y > 0`, multiply `Velocity.Y` by `jumpCutFactor` (0.3-0.5) for variable height.
- **Fall gravity multiplier**: when `Velocity.Y < 0`, apply `gravity * fallMultiplier` instead of base gravity for snappier descent.
- **Max fall speed**: clamp `Velocity.Y` to `maxFallSpeed` (negative) to prevent terminal-velocity feel.
- **Coyote time**: track `coyoteTimer` — set to `coyoteWindow` (0.08-0.12s) when leaving floor, count down in `_PhysicsProcess`. Allow jump while `coyoteTimer > 0`.
- **Input buffer**: on jump press while airborne, set `jumpBufferTimer` to `jumpBufferWindow` (0.1s). If player lands while `jumpBufferTimer > 0`, execute jump immediately.

## Run/Walk System

- Track `RunHeld` bool from `Input.IsActionPressed("run")`.
- Target speed = `RunHeld ? runSpeed : walkSpeed`.
- Apply speed transitions only when `IsOnFloor()` — preserve air momentum otherwise.
- Smooth starts/stops: `Velocity.X = Mathf.MoveToward(Velocity.X, targetSpeed * direction, acceleration * (float)delta)`.
- Deceleration curve (separate `deceleration` constant) when input direction is zero or opposing velocity.

## Character State Machine

- `enum CharacterState { Idle, Walking, Running, Jumping, Falling }`
- Derive state **after** `MoveAndSlide()` from physics truth:

```csharp
CurrentState = (IsOnFloor(), moveInput != 0, Velocity.Y) switch
{
    (true, false, _)        => CharacterState.Idle,
    (true, true, _) when !RunHeld => CharacterState.Walking,
    (true, true, _)         => CharacterState.Running,
    (false, _, > 0)         => CharacterState.Jumping,
    (false, _, _)           => CharacterState.Falling,
};
```

- State drives animation selection, sound, and particle effects — never drives physics directly.
- CrystalMagica pattern: physics is authoritative, state is derived, animation follows state.

## Camera

- Use `Camera3D` with **orthographic** projection (`Projection = ProjectionType.Orthogonal`) for sidescroller feel in 3D.
- Set `Size` to control visible world units (e.g., 20 for a 20m vertical view).
- Follow player with configurable `Vector3 offset` — typically `(0, 2, 10)` to view the XY plane.
- Smooth follow: `Position = Position.Lerp(target.Position + offset, (float)delta * followSpeed)`.
- **Delta clamping**: cap `delta` to `maxDelta` (e.g., 0.1) before camera lerp to prevent teleport after debugger pause or frame hitch.

## Collision Layers

- Godot uses 32 physics layers (1-indexed in editor, 0-indexed in code).
- CrystalMagica layer assignment:
  - **Layer 1 — Environment**: static world geometry, tilemap colliders.
  - **Layer 2 — Player**: local player's `CharacterBody3D`.
  - **Layer 3 — PlayerHurtbox**: `Area3D` receiving damage.
  - **Layer 4 — PlayerHitbox**: `Area3D` dealing damage.
- **Remote players**: place on isolated layer (e.g., Layer 5). Clear mask bits against Layer 2 — remote players never collide with local player.
- `MoveAndSlide()` resolves only against layers in the body's `CollisionMask`. Local player masks Layer 1 (Environment) only.
- Set via code: `CollisionLayer = 1 << 1; CollisionMask = 1 << 0;` (player on layer 2, masks environment).

## Multiplayer Replay

- **Local player**: capture input each `_PhysicsProcess`, apply to `Velocity`, call `MoveAndSlide()`, send action payload (input vector, jump pressed, timestamp) to server.
- **Remote players**: receive action payloads, apply identical input to their `CharacterBody3D`, call `MoveAndSlide()`. Same physics = deterministic within floating-point tolerance.
- **Server snapshots**: server periodically sends authoritative `(Position, Velocity)`. Remote players lerp toward snapshot to correct drift.
- **Local prediction**: local player moves immediately, server confirms. On mismatch beyond threshold, snap-correct with brief interpolation.
- Both local and remote run `MoveAndSlide()` — never teleport remote players directly (causes missed collisions).

## One-Way Platforms

- Enable `one_way_collision` on the platform's `CollisionShape3D`.
- Player passes through from below, lands on top — `IsOnFloor()` returns true when standing on it.
- **Down-jump**: on down+jump input, temporarily clear the collision mask bit for the platform layer (or set `CollisionShape3D.Disabled = true` on a timer). Re-enable after ~0.2s or when player Y is below platform Y.
- Use `GetSlideCollision()` after `MoveAndSlide()` to identify which body the player is standing on for targeted disable.
