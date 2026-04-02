---
name: gamedev-2d-ai
description: >
  Enemy AI patterns for 2D platformers — patrol, chase, platformer pathfinding,
  attack patterns, boss fight design, and MMO aggro systems. Load when designing
  enemy behavior, boss fights, or NPC AI for 2D games, or when the user mentions
  "enemy AI", "patrol", "boss fight", "aggro", "attack pattern", "state machine AI",
  "platformer pathfinding", "enemy archetype", "leashing", or "telegraphing".
---

# 2D Enemy AI

Design and implement enemy AI for 2D platformers, action games, and MMO-style encounters. Covers state machines, platform-aware pathfinding, enemy archetypes, attack telegraphing, boss fight design, difficulty tuning, and server-authoritative AI for multiplayer.

## State Machine AI

Every enemy runs a finite state machine. The canonical states and their transitions:

```
         ┌──────────────────────────────┐
         │                              ▼
     PATROL ──(sight/sound)──► ALERT ──► CHASE ──► ATTACK ──► RETREAT
       ▲                                  │          │           │
       │                                  │          │           │
       └──────────(leash range)───────────┘          │           │
       └──────────(target lost)──────────────────────┘           │
       └──────────(HP recovered)─────────────────────────────────┘
```

### State Definitions

| State | Behavior | Entry Trigger | Exit Trigger |
|-------|----------|---------------|--------------|
| Patrol | Walk between waypoints, idle at endpoints | Default / target lost timeout | Sight or sound detection |
| Alert | Stop movement, play alert animation, turn toward stimulus | Sight range entered or sound area triggered | Stimulus confirmed (enter Chase) or timeout (return Patrol) |
| Chase | Move toward target, navigate platforms | Alert confirmed target | Target in attack range, target lost, or leash distance exceeded |
| Attack | Execute attack pattern, face target | Target within attack range | Attack animation complete or target exits range |
| Retreat | Move away from target, seek safe position | HP below retreat threshold | HP recovered above threshold or safe position reached |

### Transition Triggers

**Sight detection** — RayCast2D from enemy to player. Configure `target_position` each physics frame. Check `is_colliding()` and verify the collider is the player (not terrain). Typical sight range: 150-300px. Add a sight cone by checking the angle between the enemy's facing direction and the vector to the player.

**Sound detection** — Area2D "hearing zone" as a child of the enemy. When the player enters the area (footsteps, attacks, landing from a jump), trigger Alert. Typical hearing radius: 100-200px. Sound detection ignores line-of-sight, making it useful for enemies that react around corners.

**Damage taken** — Any hit transitions to Alert (if in Patrol) or immediately to Chase/Attack (if already aware). Taking damage while below the retreat threshold triggers Retreat.

**Target lost** — The player has been out of sight and hearing for a configurable duration (2-5 seconds). Return to Patrol.

**Leash distance** — The enemy has chased beyond its maximum allowed range from its spawn point. Return to Patrol (or the spawn point directly). Prevents enemies from being kited indefinitely.

### Implementation Pattern

Use an enum for states and a match/switch in `_PhysicsProcess`. Keep state logic in separate methods. Store the current state, state timer, and last known target position as instance variables.

```
State machine structure:
- _PhysicsProcess calls current state handler
- Each handler returns the next state (or current to stay)
- On state change: call exit_state() then enter_state()
- enter_state() resets timers, plays animations, sets movement
- exit_state() cleans up state-specific resources
```

Avoid deep `if/else` chains. If an enemy has more than 6 states, consider a hierarchical state machine (e.g., Combat superstate containing Attack and Retreat substates) or a behavior tree.

## Platformer Pathfinding

2D platformer pathfinding is fundamentally different from top-down grid pathfinding. Enemies move on disconnected platforms connected by jumps, drops, and ladders. Standard A* on a grid does not work.

### Approach Comparison

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| Waypoint graph | Simple, designer-controlled, predictable | Manual placement, brittle to level changes | Linear levels, few platforms |
| NavigationAgent2D + regions | Engine-supported, handles slopes, auto-updates | Requires contiguous navigation regions, poor jump support | Ground-connected terrain |
| Jump-point graph | Handles disconnected platforms, models jump arcs | Complex setup, needs jump capability data | Multi-platform levels |
| Tile-based pathfinding | Works with TileMap data, automatable | Coarse resolution, complex jump arc modeling | Procedural levels using TileMaps |

### Waypoint Graph (Recommended Starting Point)

Place Marker2D nodes at patrol endpoints, platform edges, and landing zones. Connect them with metadata describing the traversal type:

```
Waypoint connections:
  A ──(walk)──► B ──(jump_right)──► C ──(drop)──► D ──(ladder_up)──► E
```

Each connection stores: traversal type (walk, jump, drop, ladder, fly), direction, and required capability. An enemy that cannot jump skips jump connections. An enemy that can fly ignores platform constraints entirely.

At runtime, the enemy pathfinds through the waypoint graph (simple BFS or A* on the graph, not the tile grid) and executes each traversal type with the appropriate movement logic.

### NavigationAgent2D with Regions

Use NavigationRegion2D to define walkable surfaces. Place separate regions per platform. For connected terrain (slopes, ramps), a single region works well. For disconnected platforms, you need NavigationLink2D to model jumps and drops between regions.

```
Setup:
1. NavigationRegion2D per platform (or one large region for connected ground)
2. NavigationLink2D between platforms (bidirectional=false for drops)
3. NavigationAgent2D on the enemy
4. Set navigation_layers to separate flying enemies from ground enemies
```

NavigationAgent2D handles pathfinding and velocity calculation automatically. Override movement when traversing a NavigationLink (the link tells you "jump here" but you must implement the jump arc yourself).

### Jump Capability Modeling

Each enemy type defines its jump parameters: max jump height (pixels), max jump distance (pixels), can double-jump (bool), can wall-jump (bool). When building or querying the pathfinding graph, filter connections the enemy cannot traverse.

```
Jump feasibility check:
  gap_width <= max_jump_distance AND
  height_difference <= max_jump_height AND
  (not wall_required OR can_wall_jump)
```

Pre-compute reachability per enemy type at level load rather than per-frame.

## Enemy Archetypes

### Decision Table

| Archetype | Movement | Detection | Attack | Difficulty | Node Hierarchy |
|-----------|----------|-----------|--------|------------|----------------|
| Ground Walker | Patrol between waypoints, reverse at edges | RayCast2D sight + Area2D hearing | Melee on contact or short-range projectile | Low | CharacterBody2D > Sprite2D, CollisionShape2D, RayCast2D (edge), RayCast2D (sight), Area2D (hearing) |
| Flyer | Sine wave vertical oscillation + horizontal drift, chase in direct line | Large Area2D detection radius | Dive bomb or ranged projectile | Medium | CharacterBody2D > Sprite2D, CollisionShape2D, Area2D (detection), Area2D (hitbox) |
| Turret | Fixed position, no movement | 360-degree RayCast2D sweep or Area2D | Rotating fire, burst patterns, aimed shots | Medium | StaticBody2D > Sprite2D (base), Sprite2D (barrel, rotates), CollisionShape2D, RayCast2D (aim), Timer (fire rate) |
| Jumper | Stationary between jumps, timed arc jumps toward player | Area2D trigger zone | Stomp damage on landing via Area2D | Medium | CharacterBody2D > Sprite2D, CollisionShape2D, Area2D (stomp zone), Timer (jump interval) |
| Charger | Stationary until triggered, wind-up pause, high-speed dash | RayCast2D long-range sight line | Dash deals heavy contact damage | High | CharacterBody2D > Sprite2D, CollisionShape2D, RayCast2D (sight), Area2D (damage hitbox), AnimationPlayer |
| Shield Bearer | Slow patrol, blocks frontal attacks | RayCast2D sight | Melee, vulnerable from behind or during attack wind-up | High | CharacterBody2D > Sprite2D, CollisionShape2D, Area2D (shield zone, front), RayCast2D (sight), AnimationPlayer |

### Ground Walker Detail

The most common enemy. Patrols a platform edge-to-edge using a downward RayCast2D at the front edge to detect drop-offs and a forward RayCast2D to detect walls.

```
Edge detection setup:
  RayCast2D "EdgeDetector" — target_position = (16, 32), relative to front of sprite
  If NOT colliding → platform edge ahead → reverse direction

Wall detection setup:
  RayCast2D "WallDetector" — target_position = (24, 0), horizontal from center
  If colliding → wall ahead → reverse direction
```

On detecting the player (sight RayCast2D hit), transition to Chase. During Chase, disable edge reversal if the enemy should pursue off platforms, or keep it enabled for cautious enemies that stop at edges.

### Flyer Detail

Movement combines a horizontal chase vector with a sine-wave vertical offset for organic-feeling flight. The sine wave amplitude and frequency define how "wobbly" the flight path is.

```
Flyer movement per frame:
  base_direction = (target.position - position).normalized()
  sine_offset = Vector2(0, sin(time * frequency) * amplitude)
  velocity = (base_direction * chase_speed) + sine_offset
```

Flyers ignore platform pathfinding entirely. They move in direct lines toward the target, making them effective at pressuring players who are safe from ground enemies.

### Charger Detail

The charger is a high-threat enemy defined by its wind-up telegraph. On detecting the player, it stops, plays a charge-up animation (0.8-1.2 seconds), then dashes at 3-5x normal movement speed in a straight line. The dash continues until hitting a wall or traveling a maximum distance.

```
Charger states:
  IDLE → (sight) → WINDUP → (timer) → DASH → (wall/distance) → RECOVERY → IDLE

  WINDUP: 0.8-1.2s, enemy shakes/flashes, cannot be interrupted
  DASH: 3-5x speed, straight line, damage on contact
  RECOVERY: 0.5-1.0s, vulnerable, cannot act
```

The recovery window after a missed charge is the intended counterplay.

## Attack Telegraphing

Every enemy attack must be readable. The player needs enough time to recognize the attack and respond. Telegraphing communicates what is coming, when it will land, and where the danger zone is.

### Timing Framework

| Phase | Duration (frames @60fps) | Purpose | Visual/Audio Cue |
|-------|--------------------------|---------|-------------------|
| Wind-up | 12-30 frames (0.2-0.5s) | Signal attack is coming | Sprite flash, pull-back animation, audio cue, particle charge-up |
| Active | 3-12 frames (0.05-0.2s) | Damage hitbox is live | Attack animation, hitbox visualization (debug), impact particles |
| Recovery | 10-24 frames (0.17-0.4s) | Vulnerability window | Return-to-idle animation, enemy is open to counterattack |

### Design Rules

**Wind-up must be longer than reaction time.** Average human visual reaction time is 200-250ms. Wind-up for standard attacks should be at minimum 12 frames (200ms). Boss attacks or high-damage attacks need 18-30 frames (300-500ms) or more.

**Active frames should be short.** The danger window should feel precise, not lingering. 3-6 active frames for melee swipes, 6-12 for area attacks.

**Recovery is the reward.** Players who dodge the attack get a counterattack window. Recovery duration should be generous enough to feel rewarding but not so long that the enemy feels helpless. Scale recovery with difficulty -- easier modes have longer recovery.

**Consistent visual language.** Red flash means damage incoming. White flash means invulnerable or parry window. Shaking means charging. Circle on ground means area attack landing zone. Establish these conventions early and never violate them.

### Telegraphing Methods

| Method | Implementation | Best For |
|--------|---------------|----------|
| Sprite flash / color shift | Modulate property animation, cycle to red | Universal, cheap, highly visible |
| Wind-up animation | Dedicated animation frames showing preparation | Melee attacks, physical moves |
| Ground marker | Sprite or particles on the target area | Area attacks, projectile landing zones |
| Audio cue | Distinct sound per attack type, plays at wind-up start | All attacks, essential for accessibility |
| Screen shake (light) | Camera shake during wind-up | Heavy attacks, boss telegraphs |
| Projectile trail | Line or particle trail showing trajectory | Aimed ranged attacks |

## Boss Fight Design

Bosses are multi-phase state machines with scripted attack patterns, arena mechanics, and cinematic transitions.

### Phase Structure

```
PHASE 1 (100%-70% HP)     PHASE 2 (70%-35% HP)      PHASE 3 (35%-0% HP)
┌─────────────────┐       ┌─────────────────┐        ┌─────────────────┐
│ 2-3 basic       │       │ Phase 1 attacks  │        │ All previous    │
│ attack patterns  │ ───►  │ + 1-2 new attacks│ ───►   │ + enrage attack  │
│ Long wind-ups   │       │ Shorter wind-ups │        │ Faster tempo    │
│ Simple movement  │       │ Arena hazards    │        │ More hazards    │
└─────────────────┘       └─────────────────┘        └─────────────────┘
         │                          │                          │
    TRANSITION              TRANSITION                   DEATH
    (cutscene,              (cutscene,                  (final anim,
     invulnerable)           invulnerable)               rewards)
```

### Phase Transition Implementation

Health thresholds trigger phase changes. When HP crosses a threshold:

1. Boss becomes invulnerable (set a flag, not collision layer changes)
2. Current attack is interrupted and cleaned up
3. Transition animation plays (roar, transformation, arena change)
4. New phase state machine activates with its own attack pattern list
5. Invulnerability ends after transition animation completes

Store thresholds as an array: `[0.7, 0.35]` for a 3-phase boss. Check after applying damage, not during -- avoid edge cases where a single hit skips a phase.

### Attack Pattern Sequences

Each phase has an ordered or weighted attack pool. Use one of these selection strategies:

| Strategy | Description | Best For |
|----------|-------------|----------|
| Sequential loop | Cycle through attacks in fixed order | Predictable bosses, pattern-memorization games |
| Weighted random | Random selection with weights per attack | Variety with bias toward signature moves |
| Cooldown-based | Any attack available, but each has a cooldown | Reactive bosses, prevents repeat spam |
| Conditional | Attack selected based on player position/state | Intelligent bosses, positional counterplay |

For learnable bosses (Mega Man, Cuphead style), use sequential loops. Players memorize the pattern and master it through repetition. For chaotic bosses (roguelikes), use weighted random with cooldowns to prevent the same attack three times in a row.

### Arena Design Patterns

| Pattern | Description | Phase Usage |
|---------|-------------|-------------|
| Flat arena | Open floor, no obstacles | Phase 1 — learn attacks without distractions |
| Platforms | Elevated positions for dodging ground attacks | Phase 2 — vertical dodge requirements |
| Hazard zones | Lava, spikes, or pits that activate per phase | Phase 2-3 — shrinking safe area |
| Destructible cover | Pillars or walls the boss destroys over time | Phase 1-2 — diminishing safety |
| Moving platforms | Platforms that shift, rotate, or disappear on timers | Phase 3 — mastery challenge |

Design the arena to support the boss's attacks. If the boss has a ground slam, provide platforms to jump to. If the boss has aerial bombardment, provide cover. The arena teaches the player the counterplay.

### Cinematic Triggers

Use AnimationPlayer for phase transitions, not code-driven timers. An animation track can coordinate: camera zoom, screen shake, boss animation, particle effects, lighting changes, and audio stingers in a single timeline. Pause gameplay input during cinematics but keep the physics simulation frozen (set `Engine.time_scale = 0` or use a process mode flag), not running.

## Difficulty Tuning

### Multiplier Tables

| Parameter | Easy | Normal | Hard | Nightmare |
|-----------|------|--------|------|-----------|
| Enemy HP | 0.7x | 1.0x | 1.4x | 1.8x |
| Enemy damage | 0.6x | 1.0x | 1.3x | 1.6x |
| Enemy speed | 0.85x | 1.0x | 1.15x | 1.3x |
| Wind-up duration | 1.4x | 1.0x | 0.8x | 0.65x |
| Recovery duration | 1.3x | 1.0x | 0.8x | 0.6x |
| Sight range | 0.8x | 1.0x | 1.2x | 1.5x |
| Aggro timeout | 0.7x | 1.0x | 1.5x | 2.0x |

Apply multipliers at enemy instantiation, not per-frame. Store the base values in the enemy resource/scene and multiply once during `_Ready`.

### Pattern Complexity Scaling

Beyond numeric tuning, harder difficulties can change enemy behavior:

- **Easy**: Enemies attack one at a time (implicit queue). Simpler attack patterns only (no combo attacks).
- **Normal**: Full attack repertoire. Multiple enemies can attack simultaneously.
- **Hard**: Enemies use advanced patterns (feints, combos). Reduced tells on some attacks.
- **Nightmare**: Enemies coordinate (one pins, another flanks). Minimal recovery windows.

### Adaptive Difficulty

Track player deaths per room/encounter. If deaths exceed a threshold (e.g., 5 deaths on the same boss), offer optional assists:

- Increase player damage by 10% per attempt (cap at 50%)
- Reduce boss HP by 5% per attempt (cap at 25%)
- Add extra health pickups to the arena

Never force adaptive difficulty. Present it as an opt-in after repeated failures. Players who want the challenge should keep it. Communicate clearly: "Would you like to enable assist mode for this encounter?"

## MMO Enemy Considerations

For multiplayer environments with persistent or semi-persistent enemies, additional systems are required beyond single-player state machines.

### Server-Authoritative AI Execution

All AI state transitions and attack decisions run on the server. Clients receive state snapshots and interpolate enemy positions and animations. Never let the client run enemy AI logic -- it enables trivial cheating (disable enemy attacks, freeze AI, reveal enemy state).

```
Server tick:
  1. Process all enemy state machines
  2. Evaluate aggro tables
  3. Execute movement and attacks
  4. Broadcast: [enemy_id, state, position, target_id, animation]

Client receives:
  1. Interpolate enemy position between snapshots
  2. Play animation matching received state
  3. Show telegraphs based on attack state + timing
```

### Aggro Table Design

Each enemy maintains a threat table -- a sorted list of players and their threat values. The highest-threat player is the current target.

| Action | Threat Generated | Notes |
|--------|-----------------|-------|
| Damage dealt | 1 threat per 1 damage | Linear scaling |
| Healing done | 0.5 threat per 1 HP healed | Half of damage threat |
| Taunt ability | Fixed large value (e.g., 5000) | Overrides table temporarily |
| Proximity | Passive +10/sec in melee range | Prevents kiting by ranged |
| First hit | Bonus +100 flat | Ensures initial aggro lock |

**Threat decay**: Reduce all threat by 5% per second when not in combat. Full reset after leashing or de-aggro timer expiry.

**Target switching**: The enemy switches targets only when another player exceeds the current target's threat by 10% or more (hysteresis). This prevents rapid target flipping.

### Leashing

Enemies must return to their spawn point when kited too far. Without leashing, players exploit enemy AI by dragging enemies to favorable terrain or out of bounds.

```
Leash check (every 0.5s, not every frame):
  distance_from_spawn = position.distance_to(spawn_point)
  if distance_from_spawn > max_leash_distance:
      clear_aggro_table()
      set_state(RETURN_TO_SPAWN)
      set_invulnerable(true)  // prevent griefing during return
      // On reaching spawn: full HP heal, invulnerability off, resume Patrol
```

Typical leash distances: 500-1500px depending on encounter design. Boss arenas use invisible walls instead of leashing.

### De-Aggro Timers

When all players in the threat table are dead, out of range, or have dropped combat, start a de-aggro timer (typically 8-15 seconds). If no new threat is generated before the timer expires, the enemy:

1. Clears the aggro table
2. Heals to full HP (or a configurable reset percentage)
3. Returns to spawn
4. Resumes Patrol state

This prevents partially-damaged enemies from remaining in a broken state indefinitely.

### Respawn Systems

| Pattern | Behavior | Use Case |
|---------|----------|----------|
| Fixed timer | Respawn at spawn point after N seconds | Standard MMO field mobs |
| Wave-based | Group respawns together on a shared timer | Dungeon rooms, defense encounters |
| Triggered | Respawn only when an event occurs (player enters area, quest flag) | Scripted encounters, boss rooms |
| Dynamic density | Maintain N enemies in a zone, respawn to fill gaps | Open-world zones with target population |

Server tracks respawn timers. Clients are not informed of pending respawns -- the enemy simply appears (with a spawn animation) when the server adds it to the world state broadcast.

## Godot MCP Integration

Use the Godot MCP server to scaffold enemy scenes programmatically.

### Enemy Scene Scaffolding

```
Workflow: scene_create → scene_node_add (hierarchy) → signal_connect → scene_save

1. scene_create
   - name: "GroundWalker"
   - root_type: "CharacterBody2D"

2. scene_node_add (build hierarchy):
   - Sprite2D "Sprite" (child of root)
   - CollisionShape2D "Collision" (child of root, RectangleShape2D)
   - RayCast2D "EdgeDetector" (target_position: Vector2(16, 32))
   - RayCast2D "WallDetector" (target_position: Vector2(24, 0))
   - RayCast2D "SightLine" (target_position: Vector2(200, 0))
   - Area2D "HearingZone" (child of root)
     - CollisionShape2D "HearingShape" (CircleShape2D, radius: 150)
   - Area2D "Hitbox" (child of root)
     - CollisionShape2D "HitboxShape" (RectangleShape2D)
   - AnimationPlayer "AnimPlayer"
   - Timer "StateTimer" (one_shot: true)

3. signal_connect:
   - HearingZone.body_entered → root._on_hearing_zone_body_entered
   - StateTimer.timeout → root._on_state_timer_timeout
   - Hitbox.body_entered → root._on_hitbox_body_entered

4. scene_save
```

### Boss Scene Scaffolding

Boss scenes extend the basic enemy hierarchy with phase management nodes:

```
CharacterBody2D "Boss"
├── Sprite2D "Sprite"
├── CollisionShape2D "Collision"
├── AnimationPlayer "AnimPlayer"
├── AnimationPlayer "PhaseTransitionPlayer"   # separate player for cinematics
├── Area2D "AttackZone"
│   └── CollisionShape2D "AttackShape"
├── Area2D "DetectionZone"
│   └── CollisionShape2D "DetectionShape"    # large radius
├── Node2D "HazardSpawner"                    # spawns arena hazards per phase
├── Timer "AttackCooldown"
├── Timer "PatternTimer"
└── Marker2D "ArenaCenter"                    # reference point for positioning
```

Use `scene_node_set` to configure collision layers: enemy body on layer 3, hitboxes on layer 4, detection zones on layer 5. Keep collision layers consistent across all enemy types.

## Anti-Patterns

| Anti-Pattern | Problem | Correct Approach |
|-------------|---------|------------------|
| AI every frame | Running pathfinding, sight checks, and decision logic every `_PhysicsProcess` call wastes CPU | Stagger expensive checks: pathfinding every 0.5s, sight every 0.1s, state decisions every 0.2s. Use timers or frame-count modulo. |
| No telegraph before damage | Player takes damage with no warning, feels unfair | Every attack needs wind-up frames proportional to its damage. Minimum 200ms for any damaging move. |
| Pixel-perfect dodge requirements | Hitboxes match sprite exactly, leaving no dodge margin | Make hitboxes slightly smaller than sprites. Add 2-4px of forgiveness on all sides. Generous hitboxes feel fair; pixel-perfect hitboxes feel cheap. |
| Enemies that never stop chasing | Enemy pursues infinitely across the entire level | Implement leash distance. Enemies return to patrol after exceeding max chase range from spawn. |
| Identical AI for all enemies | Every enemy patrols and chases the same way, making encounters monotonous | Each archetype should have distinct movement, detection, and attack behavior. Variety creates interesting encounter design. |
| Client-authoritative enemy AI in multiplayer | Running AI on the client enables cheating and causes desync between players | All enemy AI must execute server-side. Clients only render and interpolate. |
| Hardcoded state transitions | State machine transitions buried in nested if/else with magic numbers | Use exported/configurable values for sight range, chase speed, attack range, leash distance. Designers should tune without editing code. |
| Boss with no vulnerability windows | Boss attacks continuously with no recovery phase, player cannot counterattack | Every attack sequence must end with a recovery window. The loop is: dodge → punish → repeat. |

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-2d-platformer` | Player-side platformer mechanics — movement, collision, camera. Pairs directly with enemy AI design. |
| `gamedev-multiplayer` | Client-side networking, state sync, lag compensation for multiplayer enemy AI. |
| `gamedev-ecs` | Entity Component System architecture — alternative to inheritance-based enemy hierarchies. |
| `gamedev-server-architecture` | C# headless server design for running server-authoritative AI at scale. |
