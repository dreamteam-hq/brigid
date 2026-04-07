---
name: gamedev-3d-ai
description: Enemy AI for 3D MMO platformers — patrol loops, server-controlled entities, BackgroundService AI, state machines, aggro, boss patterns, and multiplayer authority
triggers:
  - enemy AI
  - patrol loop
  - state machine
  - aggro
  - boss pattern
  - EnemyControllerService
  - AI behavior
  - NPC movement
  - server-controlled AI
version: "1.0.0"
---

# Enemy AI Patterns for 3D MMO Platformers

## Server-Controlled Entities

CrystalMagica pattern: `EnemyControllerService` inherits from `BackgroundService` and runs all patrol/combat logic server-side. The service broadcasts `CharacterAction` messages to every connected client via the existing action relay. Clients never run AI logic — they only render what the server tells them. The server is the single source of truth for enemy position, state, and behavior.

Key points:
- One `BackgroundService` per enemy type or zone manages a pool of entities
- Each tick evaluates the FSM, emits actions, and updates authoritative position
- Enemy spawn/despawn is server-driven; clients react to relay messages

## Patrol Loop

Simplest behavior pattern — a repeating movement cycle:

1. `MoveBegin(Right)` — enemy starts moving right
2. Delay (configurable, e.g. 3 seconds)
3. `Stop` — enemy halts
4. Delay (short pause)
5. `MoveBegin(Left)` — enemy reverses
6. Repeat from step 2

Position is tracked server-side and updated with each action broadcast. This flat loop is extensible to waypoint systems by replacing left/right with a waypoint queue and direction vectors.

## State Machines

Server-side finite state machine governs all enemy behavior:

```
Idle → Patrol → Chase → Attack → Return → Idle
```

Transition triggers:
- **Idle → Patrol**: spawn timer or zone activation
- **Patrol → Chase**: player enters aggro radius
- **Chase → Attack**: target within attack range
- **Attack → Chase**: target moves out of melee range
- **Chase → Return**: target exceeds leash radius or de-aggro timer expires
- **Return → Idle**: enemy reaches spawn point
- **Any → Idle**: enemy health reset on full de-aggro

The current state is broadcast to clients so they can play the correct animation. State transitions are logged for debugging.

## Aggro and Threat

The server maintains a threat table per enemy instance:

- **Threat generation**: damage dealt to the enemy = threat added to that player
- **Healing threat**: healers generate threat equal to a fraction of effective healing
- **Target selection**: highest threat player is the current target
- **Aggro radius**: players entering this radius generate a base amount of initial threat
- **Leash radius**: if the current target moves beyond leash distance, the enemy begins returning to spawn
- **De-aggro timer**: if no threat-generating event occurs within N seconds, threat decays; full decay resets the enemy
- **Threat drop**: on player death, their threat entry is removed

## Boss Fight Patterns

Bosses use a phase-based FSM layered on top of the standard state machine:

- **Phase transitions**: triggered by health thresholds (e.g. 75%, 50%, 25%)
- **Per-phase behavior**: each phase defines its own attack pattern set, movement style, and spawn mechanics
- **Server broadcast**: phase change events are sent to all clients, which trigger visual transitions (new VFX, arena changes, music shifts)
- **Enrage timer**: optional hard enrage after N minutes increases damage output

Example structure:
- Phase 1 (100-75%): basic melee attacks, simple patrol
- Phase 2 (75-50%): adds ranged attacks, spawns minions
- Phase 3 (50-25%): area denial mechanics, faster attack speed
- Phase 4 (25-0%): enraged — all abilities available, reduced cooldowns

## Multiplayer Authority

All AI decisions are made server-side. Clients are pure renderers for enemy entities:

- **No client-side prediction** for enemies (unlike player movement, which uses client-side prediction with server reconciliation)
- **Position snaps**: server broadcasts authoritative positions; clients interpolate between snapshots for smooth rendering
- **Action relay**: enemies use the same `CharacterAction` relay as players — no separate system needed
- **Latency tolerance**: enemy movements are less latency-sensitive than player inputs, so server-authoritative with interpolation is sufficient

## NavigationServer3D

CrystalMagica uses **3D physics and 3D navigation** — CharacterBody3D, Vector3, 3D collision layers. The sidescroller feel (2.5D) is a gameplay constraint, not an engine constraint. NavigationServer3D is the correct pathfinding system.

Godot's built-in server-side pathfinding for 3D environments:

- **NavigationRegion3D**: bakes a navigation mesh from level geometry at edit time or runtime
- **NavigationAgent3D**: queries the navmesh for paths between points, handles avoidance
- **Current approach**: waypoint-based approximation — enemies follow predefined points, no runtime pathfinding cost
- **Future approach**: headless Godot instance on the server runs `NavigationServer3D` for real pathfinding without rendering overhead
- **Considerations**: navmesh must account for enemy size (agent radius), jumping gaps (navigation links), and dynamic obstacles

Godot 4.6 API (not deprecated 4.0 patterns):
- `NavigationServer3D.map_create()` / `NavigationServer3D.map_set_active()` for runtime nav map management
- `NavigationServer3D.agent_create()` with `NavigationAgent3D` for avoidance
- Avoid the removed Godot 3.x `Navigation` node — use `NavigationRegion3D` exclusively

## 2.5D AI Considerations

CrystalMagica is a sidescroller rendered in 3D space. Enemy AI must respect this constraint:

- **Constrain Z axis movement**: patrol waypoints and chase targets should stay on the level's Z plane. Clamp or project enemy Z position to the lane's Z coordinate each tick.
- **Aggro radius as 2D circle**: compute aggro/leash checks using only X and Y distance (`Vector3` with Z ignored, or project to `Vector2`). A full 3D sphere check would incorrectly include enemies/players on different Z layers (e.g., background lanes).
- **Jump AI**: vertical (Y-axis) movement for jumping enemies uses 3D physics (`CharacterBody3D.Velocity.Y`), not 2D. Apply gravity as a negative Y force each tick.
- **NavMesh baking**: bake nav meshes as thin slabs on the lane Z plane. This prevents the 3D navmesh from routing enemies through Z depth when it shouldn't.
- **Lane-switching enemies**: if future design adds Z-depth lane changes, those transitions are explicit state machine transitions (`ChangeLane` action), not free 3D movement.

## CrystalMagica: EnemyControllerService Integration

The `EnemyControllerService` (inherits `BackgroundService`) is the concrete implementation of all patterns above:

- **Patrol cycles**: each enemy instance in the service has a waypoint list in 3D space (X varies, Y at platform height, Z fixed to lane). The service cycles through waypoints and emits `MoveBegin` / `Stop` `CharacterAction` messages.
- **Spawn/despawn**: server-driven. The service creates enemy state entries on zone load, removes them on zone unload or death. Clients receive `EntitySpawn` / `EntityDespawn` relay messages and instantiate/free scene nodes accordingly.
- **Server-authoritative positions**: the service owns `Vector3 AuthoritativePosition` per enemy. Clients never write to this — they interpolate their rendering position toward the broadcast value.
- **Action relay**: enemies share the same `CharacterAction` relay pipeline as players. No enemy-specific protocol needed.
- **MMO context**: in a multi-zone MMO, one `EnemyControllerService` per zone. The zone service lifecycle matches zone load/unload, keeping memory bounded.
