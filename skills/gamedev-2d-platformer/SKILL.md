---
name: gamedev-2d-platformer
description: >
  2D sidescroller mechanics in Godot 4 — movement physics, character state machines,
  combat systems, camera, TileMaps, animation, and save/checkpoint patterns. Load when
  building 2D platformers, sidescrollers, or Metroidvanias, or when the user mentions
  "platformer", "sidescroller", "coyote time", "wall jump", "hitbox", "hurtbox",
  "TileMap", "parallax", "Camera2D", "CharacterBody2D", "2D combat", "i-frames",
  "input buffering", or "one-way platform".
---

# 2D Platformer Mechanics (Godot 4)

## Movement Physics

### Core Parameters

Movement feel is defined by a small set of tunable values. Get these right before building anything else.

| Parameter | Description | Recommended Range | Notes |
|-----------|-------------|-------------------|-------|
| `gravity` | Downward acceleration (px/s^2) | 800–1400 | Higher = snappier falls |
| `max_fall_speed` | Terminal velocity cap (px/s) | 400–800 | Prevents absurd fall speeds |
| `run_speed` | Max horizontal speed (px/s) | 150–300 | Ground movement cap |
| `acceleration` | Ground accel (px/s^2) | 800–2000 | Higher = more responsive |
| `deceleration` | Ground friction (px/s^2) | 1000–3000 | Higher = less ice-skating |
| `air_acceleration` | In-air horizontal accel (px/s^2) | 400–1200 | Usually 50-70% of ground |
| `air_deceleration` | In-air horizontal friction (px/s^2) | 200–600 | Lower = floatier air control |
| `jump_velocity` | Initial upward speed (px/s) | -300 to -500 | Negative in Godot (Y-up is negative) |
| `jump_cut_factor` | Velocity multiplier on early release | 0.3–0.5 | Enables variable-height jumps |
| `coyote_frames` | Grace frames after leaving edge | 3–8 | 5 is a common sweet spot |
| `input_buffer_frames` | Pre-land jump buffer | 6–10 | 8 feels generous but fair |

### Gravity and Jump Curves

Use asymmetric gravity — heavier on the way down than up. This produces the snappy, responsive feel players expect from good platformers.

```
# In _physics_process:
if velocity.y > 0:
    # Falling — apply higher gravity for snappier descent
    velocity.y += gravity * fall_gravity_multiplier * delta
else:
    # Rising — normal gravity
    velocity.y += gravity * delta

velocity.y = min(velocity.y, max_fall_speed)
```

Fall gravity multiplier of 1.5–2.0 makes jumps feel weighty without slowing ascent.

### Variable-Height Jumps

Players expect short taps to produce short hops and held presses to produce full jumps. Implement by cutting upward velocity on button release.

```
# On jump button release while still rising:
if Input.is_action_just_released("jump") and velocity.y < 0:
    velocity.y *= jump_cut_factor  # 0.3–0.5
```

### Coyote Time

Allow jumping for a few frames after walking off a ledge. Without this, players perceive the controls as unresponsive because they press jump slightly late.

```
var coyote_timer: int = 0

# In _physics_process:
if is_on_floor():
    coyote_timer = coyote_frames
else:
    coyote_timer = max(coyote_timer - 1, 0)

# Jump condition becomes:
if Input.is_action_just_pressed("jump") and (is_on_floor() or coyote_timer > 0):
    velocity.y = jump_velocity
    coyote_timer = 0  # Consume it
```

### Input Buffering

Buffer jump presses so that if the player presses jump slightly before landing, the jump still fires on contact.

```
var jump_buffer_timer: int = 0

# In _physics_process:
if Input.is_action_just_pressed("jump"):
    jump_buffer_timer = input_buffer_frames

if jump_buffer_timer > 0:
    jump_buffer_timer -= 1

# On landing:
if is_on_floor() and jump_buffer_timer > 0:
    velocity.y = jump_velocity
    jump_buffer_timer = 0
```

### Acceleration and Deceleration Curves

Avoid setting velocity directly. Use acceleration/deceleration for natural-feeling movement.

```
# Horizontal movement with acceleration
var input_dir = Input.get_axis("move_left", "move_right")
var accel = acceleration if is_on_floor() else air_acceleration
var decel = deceleration if is_on_floor() else air_deceleration

if input_dir != 0:
    velocity.x = move_toward(velocity.x, input_dir * run_speed, accel * delta)
else:
    velocity.x = move_toward(velocity.x, 0, decel * delta)
```

## Wall Interactions

### Wall Slide

Reduce effective gravity when pressing against a wall while falling. This signals to the player that wall mechanics are active.

```
var wall_slide_gravity: float = 200.0  # Much lower than normal gravity

if is_on_wall() and velocity.y > 0 and input_dir_toward_wall:
    velocity.y = min(velocity.y, wall_slide_gravity)
    # Trigger wall slide animation
```

### Wall Jump

Apply horizontal force away from the wall plus vertical jump velocity. Briefly lock out horizontal input to prevent the player from immediately returning to the wall.

```
var wall_jump_force: Vector2 = Vector2(250, -350)  # Away + up
var wall_jump_lockout_frames: int = 8

if can_wall_jump and Input.is_action_just_pressed("jump"):
    var wall_normal = get_wall_normal()
    velocity.x = wall_normal.x * wall_jump_force.x
    velocity.y = wall_jump_force.y
    input_lockout_timer = wall_jump_lockout_frames
```

During lockout, ignore horizontal input so the player arcs away from the wall naturally. After lockout expires, full air control resumes.

### Wall Cling

Optional mechanic: the player holds position on a wall for a limited time before sliding.

```
var wall_cling_max_frames: int = 30  # ~0.5 seconds at 60fps
var wall_cling_timer: int = 0

if is_on_wall() and Input.is_action_pressed("grab"):
    wall_cling_timer += 1
    if wall_cling_timer < wall_cling_max_frames:
        velocity.y = 0  # Freeze vertical movement
    else:
        # Timer expired — start sliding
        velocity.y = min(velocity.y + wall_slide_gravity * delta, wall_slide_gravity)
```

### One-Way Platforms

Two approaches in Godot 4:

**Approach 1 — Collision layer toggling**: Temporarily disable the platform's collision layer when the player presses down + jump.

```
# On the platform's CollisionShape2D, set one_way_collision = true in the inspector.
# For drop-through:
if Input.is_action_just_pressed("move_down") and Input.is_action_just_pressed("jump"):
    platform_collision.disabled = true
    await get_tree().create_timer(0.2).timeout
    platform_collision.disabled = false
```

**Approach 2 — Platform layer trick**: Put one-way platforms on a separate collision layer. Disable that layer on the player's mask when dropping through.

```
# Player normally has platform layer in collision mask.
# To drop through:
set_collision_mask_value(PLATFORM_LAYER, false)
await get_tree().create_timer(0.3).timeout
set_collision_mask_value(PLATFORM_LAYER, true)
```

Approach 2 is cleaner for many platforms — one mask toggle affects all of them.

## Character State Machine

### State Enum

```
enum State {
    IDLE,
    RUN,
    JUMP,
    FALL,
    WALL_SLIDE,
    WALL_JUMP,
    DASH,
    ATTACK,
    HURT,
    DEATH,
}
```

### Transition Matrix

| From \ To | Idle | Run | Jump | Fall | WallSlide | WallJump | Dash | Attack | Hurt | Death |
|-----------|------|-----|------|------|-----------|----------|------|--------|------|-------|
| **Idle** | — | input | jump | !floor | — | — | dash | attack | hit | hp<=0 |
| **Run** | !input | — | jump | !floor | — | — | dash | attack | hit | hp<=0 |
| **Jump** | — | — | — | vy>0 | wall | wall+jump | dash | air_atk | hit | hp<=0 |
| **Fall** | floor | floor+input | buffer | — | wall | wall+jump | dash | air_atk | hit | hp<=0 |
| **WallSlide** | floor | floor | wall_jump | !wall | — | jump | — | — | hit | hp<=0 |
| **WallJump** | floor | floor | — | timer | wall | — | dash | — | hit | hp<=0 |
| **Dash** | end | end+input | end+!floor | end+!floor | — | — | — | — | — | hp<=0 |
| **Attack** | end | end | — | !floor | — | — | — | combo | hit | hp<=0 |
| **Hurt** | end | — | — | !floor | — | — | — | — | — | hp<=0 |
| **Death** | — | — | — | — | — | — | — | — | — | — |

Key: `!floor` = not on floor, `vy>0` = falling, `wall` = touching wall, `buffer` = input buffer active, `end` = state animation/timer finished, `combo` = within combo window.

### Hitbox/Hurtbox Shape Changes by State

| State | Hurtbox (damageable area) | Hitbox (damage-dealing area) |
|-------|--------------------------|------------------------------|
| Idle / Run | Full standing capsule | None |
| Jump / Fall | Slightly compressed vertically | None (unless air attack) |
| Dash | Reduced height (crouch capsule) or disabled | None |
| Attack | Full standing capsule | Weapon-specific shape, active only during hit frames |
| WallSlide | Full capsule offset toward wall | None |
| Hurt | Full capsule (invincible via i-frames, not shape) | None |

Update collision shapes when entering each state. Use `CollisionShape2D.disabled` for hitboxes that only exist during attacks.

## Collision Layer Matrix

Assign dedicated layers for clean separation. Godot 4 supports 32 physics layers.

| Layer | Bit | Contains | Purpose |
|-------|-----|----------|---------|
| 1 — Environment | 1 | TileMap collision, static geometry | World collision |
| 2 — Player Body | 2 | Player CharacterBody2D | Physics movement |
| 3 — Enemy Body | 3 | Enemy CharacterBody2D | Enemy physics |
| 4 — Player Hurtbox | 4 | Player Area2D (damageable) | Receives damage |
| 5 — Player Hitbox | 5 | Player weapon Area2D | Deals damage to enemies |
| 6 — Enemy Hurtbox | 6 | Enemy Area2D (damageable) | Receives damage |
| 7 — Enemy Hitbox | 7 | Enemy attack Area2D | Deals damage to player |
| 8 — Projectiles | 8 | Bullet/spell Area2D | Separated for selective collision |
| 9 — Pickups | 9 | Collectible Area2D | Coins, health, powerups |
| 10 — Triggers | 10 | Checkpoint, zone transition, cutscene | Event triggers |
| 11 — Platforms | 11 | One-way platforms | Separate for drop-through toggling |

### Mask Configuration

| Node | Layer (I am) | Mask (I detect) |
|------|-------------|-----------------|
| Player CharacterBody2D | 2 | 1, 11 |
| Player Hurtbox (Area2D) | 4 | 7, 8 |
| Player Hitbox (Area2D) | 5 | 6 |
| Enemy CharacterBody2D | 3 | 1 |
| Enemy Hurtbox (Area2D) | 6 | 5, 8 |
| Enemy Hitbox (Area2D) | 7 | 4 |
| Projectile (player) | 8 | 1, 6 |
| Projectile (enemy) | 8 | 1, 4 |
| Pickup Area2D | 9 | 2 |
| Trigger Area2D | 10 | 2 |

Player hitbox detects enemy hurtbox, not enemy body. Enemy hitbox detects player hurtbox, not player body. This keeps combat detection independent of physics movement.

## Combat Fundamentals

### Melee Attack Chains

Implement combo windows — a brief period at the end of an attack animation where pressing attack again advances to the next hit in the chain.

```
var combo_step: int = 0
var combo_window_open: bool = false

# Animation callback at combo-window frame:
func _on_combo_window_start():
    combo_window_open = true

func _on_combo_window_end():
    combo_window_open = false
    combo_step = 0  # Reset if player didn't continue

func _on_attack_input():
    if combo_window_open and combo_step < max_combo:
        combo_step += 1
        play_attack_animation(combo_step)
        combo_window_open = false
```

Typical 3-hit chain: light slash (fast, short range) -> heavy slash (slower, wider arc) -> finisher (longest wind-up, knockback).

### Ranged Projectile Patterns

Spawn projectiles as separate scenes. Set their collision layer to Projectiles (8) and mask to the appropriate hurtbox layer.

```
func fire_projectile(direction: Vector2):
    var proj = projectile_scene.instantiate()
    proj.global_position = muzzle_marker.global_position
    proj.direction = direction
    proj.damage = ranged_damage
    get_tree().current_scene.add_child(proj)
```

Projectiles should self-destruct on contact or after a max lifetime to prevent leaks.

### Invincibility Frames (I-Frames)

On taking damage, grant a brief invincibility window. During i-frames, disable the hurtbox and flash the sprite.

```
var iframes_duration: float = 0.8
var flash_interval: float = 0.08

func take_damage(amount: int, knockback_dir: Vector2):
    if is_invincible:
        return
    health -= amount
    apply_knockback(knockback_dir)
    start_iframes()

func start_iframes():
    is_invincible = true
    hurtbox_collision.disabled = true
    # Flash effect
    var tween = create_tween()
    for i in range(int(iframes_duration / flash_interval)):
        tween.tween_property(sprite, "modulate:a", 0.2, flash_interval / 2)
        tween.tween_property(sprite, "modulate:a", 1.0, flash_interval / 2)
    tween.tween_callback(end_iframes)

func end_iframes():
    is_invincible = false
    hurtbox_collision.disabled = false
    sprite.modulate.a = 1.0
```

For more polished visuals, use a shader that alternates between normal and a white flash instead of alpha toggling.

### Knockback

Apply a directional force plus a brief stun duration where the player cannot act.

```
var knockback_force: float = 300.0
var knockback_decay: float = 800.0
var stun_duration: float = 0.3

func apply_knockback(direction: Vector2):
    velocity = direction.normalized() * knockback_force
    velocity.y = -150  # Always pop up slightly
    state = State.HURT
    stun_timer = stun_duration
```

During stun, the character ignores input and decelerates via `knockback_decay`.

### Damage Types and Resistances

Use a dictionary or resource-based system for extensibility.

| Damage Type | Example Source | Resistance Stat |
|-------------|---------------|-----------------|
| Physical | Melee attacks, falling objects | armor |
| Fire | Lava, fire spells | fire_resist |
| Ice | Freeze traps, ice projectiles | ice_resist |
| Poison | Swamp tiles, poison enemies | poison_resist |
| True | Spikes, instant-kill zones | None (bypasses all) |

Formula: `effective_damage = base_damage * (1.0 - resistance_percent)`

## Camera Systems

### Camera2D Follow Modes

Godot's Camera2D with `position_smoothing_enabled` handles basic following. Tune `position_smoothing_speed` (3–8 typical).

```
# Camera2D as child of the player node — simplest setup.
# For more control, make Camera2D a sibling and update in _process:
camera.global_position = camera.global_position.lerp(
    player.global_position + look_ahead_offset,
    smoothing_speed * delta
)
```

### Look-Ahead

Offset the camera in the direction the player is moving so they can see more of what's ahead.

```
var look_ahead_distance: float = 60.0
var look_ahead_speed: float = 3.0
var look_ahead_offset: Vector2 = Vector2.ZERO

func update_look_ahead(player_facing: float, delta: float):
    var target_offset = Vector2(player_facing * look_ahead_distance, 0)
    look_ahead_offset = look_ahead_offset.lerp(target_offset, look_ahead_speed * delta)
```

### Screen Shake

Offset the camera randomly for a duration, decaying over time.

```
var shake_intensity: float = 0.0
var shake_decay: float = 5.0

func apply_shake(intensity: float):
    shake_intensity = intensity

func _process(delta):
    if shake_intensity > 0:
        camera.offset = Vector2(
            randf_range(-shake_intensity, shake_intensity),
            randf_range(-shake_intensity, shake_intensity)
        )
        shake_intensity = move_toward(shake_intensity, 0, shake_decay * delta)
    else:
        camera.offset = Vector2.ZERO
```

Trigger with `apply_shake(8.0)` on hit, `apply_shake(3.0)` on landing from a height.

### Camera Limits per Room

Set `Camera2D.limit_left/right/top/bottom` when transitioning between rooms or zones.

```
# On entering a room (via Area2D trigger):
func _on_room_entered(room: RoomData):
    camera.limit_left = room.bounds.position.x
    camera.limit_top = room.bounds.position.y
    camera.limit_right = room.bounds.end.x
    camera.limit_bottom = room.bounds.end.y
```

For Metroidvania-style connected rooms, update limits as the player enters new zones.

### Parallax Setup

Use CanvasLayer with different scroll speeds for depth illusion.

| Layer | Scroll Speed | Content |
|-------|-------------|---------|
| Background sky | 0.0–0.1 | Static sky, distant mountains |
| Far background | 0.2–0.3 | Mountain range, clouds |
| Mid background | 0.4–0.6 | Trees, buildings |
| Foreground (game layer) | 1.0 | TileMap, characters, objects |
| Near foreground | 1.2–1.5 | Fog, particles, vines |

```
# ParallaxBackground node with ParallaxLayer children.
# Each ParallaxLayer has motion_scale set to scroll speed.
# Example: far mountains layer
parallax_layer.motion_scale = Vector2(0.2, 0.1)  # Slow horizontal, minimal vertical
parallax_layer.motion_mirroring = Vector2(1920, 0)  # Seamless horizontal tiling
```

## TileMap Mastery

### TileSet and TileMap Workflow

1. **Create TileSet resource** — import your tileset texture, define tile size (16x16 or 32x32 typical).
2. **Define physics layers** in the TileSet — at minimum: solid collision and one-way collision.
3. **Paint tiles** in the TileMap editor.
4. **Use terrain auto-tiling** for ground surfaces — Godot 4's terrain system handles edge/corner matching.

### Terrain Auto-Tiling Rules

Godot 4 terrain system uses peering bits. Define terrain sets:

- **Match Corners and Sides** — full 47-tile auto-tiling for natural ground
- **Match Sides** — simpler 16-tile auto-tiling for platforms and walls

Label terrain types: ground, platform, slope. The editor auto-selects correct tile variants when painting.

### Physics Layers on Tiles

| TileSet Physics Layer | Purpose | Player Mask |
|----------------------|---------|-------------|
| 0 — Solid | Full collision walls and floors | Yes |
| 1 — One-Way | Platforms the player can jump through from below | Yes (layer 11) |
| 2 — Hazard | Damage zones (spikes, lava) — trigger via Area2D overlap | No (use Area2D) |

Set collision polygons per-tile in the TileSet editor. For slopes, draw angled collision polygons matching the visual slope.

### Animated Tiles

In the TileSet editor, select a tile and add animation frames. Set duration per frame (typically 0.1–0.3s). Use for water surfaces, lava, torches, conveyor belts.

### Multi-Layer Structure

| TileMap Layer | Z-Index | Content |
|---------------|---------|---------|
| 0 — Background | -2 | Decorative background tiles (no collision) |
| 1 — Midground | -1 | Behind-character decoration |
| 2 — Collision | 0 | Main gameplay tiles with physics |
| 3 — Foreground | 2 | Tiles that render in front of characters |

Use a single TileMap node with multiple layers, not multiple TileMap nodes. This is more efficient and keeps terrain rules consistent.

## 2D Animation

### SpriteFrames vs AnimationPlayer

| Criteria | SpriteFrames (AnimatedSprite2D) | AnimationPlayer |
|----------|-------------------------------|-----------------|
| Simple frame loops | Best choice — drag frames, set FPS, done | Overkill |
| Synced hitbox timing | Awkward — no method call tracks | Best choice — method tracks fire at exact frames |
| Property animation | Cannot animate arbitrary properties | Full property, method, and audio tracks |
| Blend transitions | None | CrossFade, BlendSpace via AnimationTree |
| Complex characters | Gets unwieldy with many states | Scales well with AnimationTree |
| Prototyping speed | Faster for simple sprites | More setup, more power |

**Recommendation**: Use AnimatedSprite2D for simple NPCs and effects. Use AnimationPlayer + AnimationTree for the player character and bosses.

### Animation Callbacks for Hitbox Timing

In AnimationPlayer, add a method call track that activates the hitbox at the exact frame where the weapon connects visually.

```
# AnimationPlayer calls these via method tracks:
func _on_hitbox_activate():
    attack_hitbox.monitoring = true
    attack_hitbox_collision.disabled = false

func _on_hitbox_deactivate():
    attack_hitbox.monitoring = false
    attack_hitbox_collision.disabled = true
```

This ensures hitbox active frames match the animation perfectly. Never leave hitboxes active for the full attack duration.

### AnimationTree for Complex Characters

Use AnimationTree with a state machine for characters with many states. Each state maps to an animation. Transitions define blend times.

```
# AnimationTree setup:
# - Root: AnimationNodeStateMachine
# - States: idle, run, jump, fall, attack_1, attack_2, attack_3, wall_slide, hurt, death
# - Transitions: auto-advance on some, code-driven on others

func update_animation(state: State):
    var state_machine = anim_tree.get("parameters/playback")
    match state:
        State.IDLE: state_machine.travel("idle")
        State.RUN: state_machine.travel("run")
        State.JUMP: state_machine.travel("jump")
        State.FALL: state_machine.travel("fall")
        State.ATTACK: state_machine.travel("attack_" + str(combo_step))
        State.WALL_SLIDE: state_machine.travel("wall_slide")
        State.HURT: state_machine.travel("hurt")
        State.DEATH: state_machine.travel("death")
```

## Save and Checkpoint System

### State Serialization

Define what needs saving and serialize to a dictionary.

```
func serialize_save_data() -> Dictionary:
    return {
        "position": {"x": global_position.x, "y": global_position.y},
        "health": current_health,
        "max_health": max_health,
        "inventory": inventory.serialize(),
        "abilities_unlocked": abilities_unlocked.duplicate(),
        "map_revealed": map_revealed.duplicate(),
        "bosses_defeated": bosses_defeated.duplicate(),
        "current_room": current_room_id,
        "play_time_seconds": play_time,
        "save_timestamp": Time.get_unix_time_from_system(),
    }

func deserialize_save_data(data: Dictionary):
    global_position = Vector2(data.position.x, data.position.y)
    current_health = data.health
    # ... restore all fields
```

Write to `user://` directory as JSON. Godot's `user://` maps to platform-appropriate persistent storage.

### Checkpoint Node Pattern

```
# Checkpoint.tscn — Area2D with a CollisionShape2D trigger
# On body_entered, register as the active checkpoint.

func _on_body_entered(body):
    if body.is_in_group("player"):
        GameManager.set_checkpoint(self)
        activate_visual()  # Light up, particle effect, etc.
```

Store checkpoint ID and position. On death, respawn at the last activated checkpoint.

### Death and Respawn Flow

1. Player HP reaches 0 -> enter DEATH state
2. Play death animation (non-interruptible)
3. Fade to black (screen transition)
4. Reset player HP, clear temporary buffs, reload room if needed
5. Place player at checkpoint position
6. Fade in
7. Grant brief i-frames on respawn

### Persistent vs Session State

| Data | Persistence | Storage |
|------|-------------|---------|
| Position, health, inventory | Save file | `user://save_N.json` |
| Checkpoint activated | Save file | Included in save data |
| Bosses defeated, abilities unlocked | Save file | Included in save data |
| Enemy positions (current room) | Session only | Reset on room re-entry |
| Breakable objects (current room) | Session only | Reset on room re-entry |
| Collectibles already picked up | Save file | Track by ID |
| Play timer | Save file | Accumulates across sessions |
| Screen shake, particles | Ephemeral | Never saved |

## Godot MCP Integration

### 2D Scene Scaffolding Workflows

Use the Godot MCP server to build platformer scenes programmatically.

**Player character scene**:
1. `scene_create` — root: CharacterBody2D
2. `scene_node_add` — CollisionShape2D (standing capsule for physics body)
3. `scene_node_add` — AnimatedSprite2D or Sprite2D + AnimationPlayer
4. `scene_node_add` — Area2D (hurtbox) with child CollisionShape2D
5. `scene_node_add` — Area2D (hitbox) with child CollisionShape2D (disabled by default)
6. `scene_node_add` — Camera2D (if camera follows player)
7. `scene_node_properties` — set collision layers/masks per the layer matrix
8. `scene_save`

**TileMap level scene**:
1. `scene_create` — root: Node2D
2. `scene_node_add` — TileMap (assign TileSet resource)
3. `scene_node_add` — ParallaxBackground with ParallaxLayer children
4. `scene_node_add` — Camera2D with limits set for the room
5. `scene_node_add` — Area2D nodes for triggers (checkpoints, zone transitions)
6. `scene_save`

**Enemy scene**:
1. `scene_create` — root: CharacterBody2D
2. `scene_node_add` — CollisionShape2D (physics body)
3. `scene_node_add` — AnimatedSprite2D
4. `scene_node_add` — Area2D (hurtbox) on enemy hurtbox layer
5. `scene_node_add` — Area2D (hitbox) on enemy hitbox layer
6. `scene_node_add` — RayCast2D (ledge detection, wall detection for patrol AI)
7. `scene_node_properties` — configure layers/masks
8. `scene_save`

### Physics Parameter Tuning via MCP

Use `scene_node_properties` to adjust movement values at runtime during playtesting:

```
# Adjust gravity, speed, jump velocity without editing code:
scene_node_properties(node_path="Player", property="gravity", value=1200)
scene_node_properties(node_path="Player", property="run_speed", value=220)
```

Export these variables in the player script so they appear in the Godot inspector and are accessible via MCP.

### Rapid Iteration with `editor_run`

1. Make changes via MCP or code edits
2. `editor_run` to launch the game
3. Observe behavior in `editor_debug_output`
4. `editor_stop`, adjust, repeat

## Multiplayer Platformer Sync

### Jump State Authority

The server must own jump state to prevent fly hacks. Client predicts locally but the server validates.

- Client sends: `{action: "jump", tick: N, position: (x, y)}`
- Server checks: was the client on the floor (or within coyote time) at tick N?
- Server confirms or rejects — client reconciles if rejected

### Gravity Prediction Challenges

Gravity is deterministic, but floating-point drift accumulates over long air times. Sync strategies:

- Send position snapshots every N ticks during air time (not just on state change)
- Server and client must use identical gravity values and delta time
- On landing, hard-snap to server-confirmed ground position

### Platform Snap Reconciliation

Moving platforms create reconciliation issues. If the server says the player is on platform P at position X, but the client predicted the platform at position X+5:

- Client must snap to server state: player position relative to platform, then recompute
- Send platform IDs with player state so the server knows which platform the player claims to be on

### Animation State Replication

Replicate the state machine state, not individual animation frames. Receiving clients play the appropriate animation locally.

```
# Sent over network: { state: "ATTACK", combo_step: 2, facing: -1 }
# Receiving client starts attack_2 animation facing left.
```

For detailed netcode patterns (tick synchronization, rollback, interest management), load `gamedev-multiplayer`.

## Anti-Patterns

### 1. Hardcoded Movement Values

Embedding magic numbers in `_physics_process` instead of exported variables. Makes tuning require code edits, recompilation, and restarting. Export every tunable parameter so it appears in the inspector and is adjustable at runtime.

### 2. State Machine via Booleans

Using `is_jumping`, `is_attacking`, `is_dashing` flags instead of an explicit state enum. Boolean soup leads to impossible states (jumping AND dashing AND attacking simultaneously) and unmaintainable transition logic. Use a single `current_state` variable.

### 3. Frame-Rate Dependent Physics

Using `_process` instead of `_physics_process` for movement, or forgetting to multiply by `delta`. Movement speed varies with frame rate. Always use `_physics_process` and always multiply acceleration/velocity changes by `delta`.

### 4. Hitbox Always Active

Leaving attack hitboxes enabled outside of attack animations. The player damages enemies by walking near them. Enable hitboxes only during the active frames of the attack animation via method call tracks.

### 5. Symmetric Gravity

Using the same gravity for rising and falling. Jumps feel floaty and unresponsive. Use a fall gravity multiplier (1.5–2.0x) so descent is snappier than ascent.

### 6. Missing Coyote Time and Input Buffering

Requiring the player to be exactly on the floor when pressing jump. Players perceive this as broken controls because human reaction time means they often press slightly early or late. Both mechanics cost 5 lines of code and dramatically improve feel.

### 7. Camera Without Limits

Letting Camera2D follow the player beyond room boundaries, revealing empty space or adjacent rooms. Always set camera limits per room/zone. For Metroidvania maps, update limits dynamically on room transitions.

### 8. Saving Ephemeral State

Serializing runtime-only data (particle positions, tween progress, screen shake intensity) into save files. Bloats save data and causes bugs on load. Only save gameplay-critical persistent state.

### 9. Collision Layer Free-For-All

Putting everything on layer 1 and sorting out interactions in code. Leads to phantom collisions, performance waste, and debugging nightmares. Use the layer matrix above — dedicated layers for bodies, hitboxes, hurtboxes, triggers, and projectiles.

### 10. Animating Movement in AnimationPlayer

Using AnimationPlayer property tracks to move the character (animating `position` directly) instead of driving movement through the physics system. Breaks collision detection, ignores walls, and fights with CharacterBody2D. Animation drives visuals; physics drives position.

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-multiplayer` | Full netcode patterns: tick sync, rollback, interest management, lobby systems |
| `gamedev-ecs` | Data-oriented architecture for entity-heavy platformers (hundreds of enemies, bullets) |
| `gamedev-2d-ai` | Enemy behavior trees, patrol patterns, chase/flee logic, pathfinding |
| `gamedev-godot` | Godot engine fundamentals, scene architecture, C# scripting, MCP server workflow |
| `gamedev-2d-art-pipeline` | Sprite creation, tileset workflows, animation export, parallax asset preparation |
