---
name: gamedev-ecs
description: >
  Entity Component System architecture — fundamentals, storage strategies,
  system scheduling, component queries, events, hierarchies, and framework
  comparisons. Load when designing game architecture, implementing ECS in
  Godot/Bevy/Flecs, discussing entity management, or when the user mentions
  "ECS", "entity component system", "archetype", "sparse set", "system
  scheduling", "component query", "Bevy ECS", or "Flecs".
triggers:
  - ECS
  - entity component system
  - archetype
  - sparse set
  - system scheduling
  - component query
  - Bevy ECS
  - Flecs
  - entity management
version: "1.0.0"
---

# Entity Component System Patterns

## ECS Fundamentals

### Core Concepts

| Concept | Definition | Analogy |
|---------|-----------|---------|
| Entity | A unique identifier (typically a u64 or integer) with no data or behavior | A row ID in a database |
| Component | A plain data struct attached to an entity — no methods, no behavior | A column value in that row |
| System | A function that queries entities by their component composition and operates on them | A SQL query + update |
| World | The container that owns all entities, components, and system state | The database |

### Why ECS Over OOP Hierarchies

| Problem with deep inheritance | How ECS solves it |
|------------------------------|-------------------|
| Diamond inheritance (`FlyingAquaticEnemy`) | Compose: entity has `Flying` + `Aquatic` + `Enemy` components |
| Fragile base class — changing `Enemy` breaks all subtypes | Components are independent; changing `Health` affects nothing else |
| Cache misses — objects scattered in heap memory | Archetype storage packs same-component entities contiguously |
| Unclear ownership — does `Enemy.Update()` handle physics or AI? | Systems are explicit: `physics_system`, `ai_system` |
| Hard to add behavior at runtime | Add/remove components freely: add `Poisoned` component, poison system picks it up |

### Minimal ECS Example

```
World:
  Entity 0: [Position(10, 20), Velocity(1, 0), Sprite("player.png")]
  Entity 1: [Position(50, 30), Velocity(-1, 0), Sprite("enemy.png"), Health(100)]
  Entity 2: [Position(100, 50), Sprite("tree.png")]  # no Velocity — static

System: movement_system
  Query: all entities with (Position, Velocity)
  Logic: position.x += velocity.x; position.y += velocity.y
  Result: Entities 0 and 1 move. Entity 2 is untouched — no Velocity component.
```

## Storage Strategies

### Archetype-Based Storage

Used by Bevy, Flecs, Unity DOTS.

```
Archetype A: [Position, Velocity, Sprite]
  Table:
  | Entity | Position  | Velocity | Sprite       |
  |--------|-----------|----------|-------------- |
  | 0      | (10, 20)  | (1, 0)  | "player.png" |

Archetype B: [Position, Velocity, Sprite, Health]
  Table:
  | Entity | Position  | Velocity | Sprite       | Health |
  |--------|-----------|----------|-------------- |--------|
  | 1      | (50, 30)  | (-1, 0) | "enemy.png"  | 100    |

Archetype C: [Position, Sprite]
  Table:
  | Entity | Position   | Sprite      |
  |--------|------------|-------------|
  | 2      | (100, 50)  | "tree.png"  |
```

**How it works**: Entities with the exact same set of component types are stored together in a contiguous table. Each column is a tightly-packed array of one component type.

| Advantage | Detail |
|-----------|--------|
| Cache-friendly iteration | Systems iterate contiguous arrays — minimal cache misses |
| Fast queries | Matching archetypes is an O(1) bitset operation |
| No wasted memory | Every slot in the table is occupied |

| Disadvantage | Detail |
|-------------|--------|
| Component add/remove moves entities | Adding `Health` to Entity 0 moves it from Archetype A to B — memcpy of all components |
| Archetype explosion | Many unique component combinations create many small tables |
| Fragmentation | Rare component combinations create archetypes with few entities |

**When to choose**: Iteration-heavy games (thousands of entities in the same system), stable component compositions (entities don't change components frequently).

### Sparse Set Storage

Used by EnTT, some custom ECS implementations.

```
Component storage for Position:
  Dense array:  [(10,20), (50,30), (100,50)]
  Sparse array: [0, 1, 2, _, _, ...]  # entity ID -> dense index

Component storage for Velocity:
  Dense array:  [(1,0), (-1,0)]
  Sparse array: [0, 1, _, _, _, ...]

Component storage for Health:
  Dense array:  [100]
  Sparse array: [_, 0, _, _, _, ...]
```

**How it works**: Each component type has its own dense array (contiguous data) plus a sparse array that maps entity IDs to dense indices. No concept of archetypes.

| Advantage | Detail |
|-----------|--------|
| Fast add/remove | O(1) — no entity movement, just update the sparse array |
| No archetype explosion | Each component stored independently |
| Simple implementation | Easier to build and debug |

| Disadvantage | Detail |
|-------------|--------|
| Multi-component queries require intersection | Iterating `(Position, Velocity)` requires checking both sparse sets |
| Worse cache locality for multi-component queries | Position and Velocity arrays are separate allocations |

**When to choose**: Dynamic compositions (entities frequently gain/lose components), fewer entities, simpler implementation needs.

### Decision Table

| Factor | Archetype | Sparse Set |
|--------|-----------|-----------|
| Entity count | 10K+ | <10K |
| Component add/remove frequency | Rare | Frequent |
| System iteration speed | Superior | Good |
| Multi-component query speed | Superior | Adequate |
| Implementation complexity | Higher | Lower |
| Memory fragmentation | Can fragment with many archetypes | Dense per-component |

## System Scheduling and Ordering

### System Phases

```
Frame Loop:
  1. Input Phase
     - input_system: reads keyboard/mouse/gamepad state
     - ui_input_system: processes UI events

  2. Update Phase
     - ai_system: runs behavior trees, state machines
     - movement_system: applies velocity to position
     - collision_system: detects overlaps, generates collision events
     - damage_system: processes damage events, updates Health

  3. Late Update Phase
     - camera_follow_system: tracks player position
     - animation_system: advances animation frames

  4. Render Phase
     - render_system: draws sprites/meshes at current positions
     - ui_render_system: draws UI overlay
```

### Ordering Constraints

```
Systems that MUST run in order (data dependencies):
  movement_system → collision_system → damage_system
  (position updated → collisions detected → damage applied)

Systems that CAN run in parallel (independent data):
  ai_system ∥ animation_system
  (AI reads/writes AI components; animation reads/writes Sprite components)
```

### Scheduling Patterns

| Pattern | When to use | Example |
|---------|-------------|---------|
| Sequential | System B reads what System A writes | Movement → Collision |
| Parallel | Systems touch disjoint component sets | AI || Animation |
| Fixed timestep | Physics must be deterministic | Physics at 60Hz regardless of frame rate |
| Event-driven | Infrequent triggers, avoid polling | `OnCollision` event triggers damage system |
| Conditional | System only runs when relevant | Pathfinding only runs when navigation requests exist |

### Fixed Timestep Implementation

```
accumulator = 0.0
FIXED_DT = 1.0 / 60.0  # 60 Hz physics

while game_running:
    frame_dt = time_since_last_frame()
    accumulator += frame_dt

    # Process input once per frame
    input_system()

    # Run physics at fixed rate
    while accumulator >= FIXED_DT:
        physics_system(FIXED_DT)
        collision_system()
        accumulator -= FIXED_DT

    # Render with interpolation
    alpha = accumulator / FIXED_DT
    render_system(alpha)  # interpolate between previous and current state
```

## Component Queries and Filters

### Query Types

```
Basic query — all entities with Position AND Velocity:
  Query<Position, Velocity>

With filter — has Position AND Velocity, but NOT Dead:
  Query<Position, Velocity, Without<Dead>>

Optional components — Position required, Velocity optional:
  Query<Position, Option<Velocity>>

Changed detection — only entities whose Position changed this frame:
  Query<Position, Changed<Position>>

Added detection — only entities that just received Health:
  Query<Health, Added<Health>>
```

### Query Design Patterns

| Pattern | Query | Use case |
|---------|-------|----------|
| Required components | `Query<A, B>` | Systems that need all listed components |
| Optional access | `Query<A, Option<B>>` | Handle entities with or without a component |
| Exclusion filter | `Query<A, Without<B>>` | Living entities (has Health, no Dead marker) |
| Change detection | `Query<A, Changed<A>>` | Dirty flag — only process what changed |
| Component access | `Query<&A, &mut B>` | Read A, write B — enables parallel scheduling |
| Resource access | `Res<GameConfig>` | Singleton data shared across systems |

## Event Systems and Observers

### Event Pattern

```
Events decouple systems that produce effects from systems that consume them:

collision_system:
  detects overlap between Entity A and Entity B
  emits CollisionEvent { a: EntityA, b: EntityB, normal: Vec2 }

damage_system:
  reads CollisionEvent queue
  if A has DamageOnContact and B has Health:
    B.health -= A.damage

sound_system:
  reads CollisionEvent queue
  plays impact sound at collision point

particle_system:
  reads CollisionEvent queue
  spawns spark particles at collision point
```

### Event Implementation Patterns

| Pattern | Behavior | Trade-off |
|---------|----------|-----------|
| Ring buffer | Fixed-size, events expire after N frames | Bounded memory, events can be lost |
| Drain queue | Events consumed once, cleared each frame | Simple, no duplicates, single consumer per event |
| Broadcast | All listeners receive all events, cleared after all consumed | Multiple consumers, slight complexity |
| Observer/hook | Callback fired immediately when component added/removed | Instant response, harder to debug |

### Observer Pattern (Component Lifecycle)

```
on_add(Health):
  # Fires when Health component is added to any entity
  initialize health bar UI for this entity

on_remove(Health):
  # Fires when Health component is removed
  entity is dead — spawn death particles, drop loot

on_change(Position):
  # Fires when Position component value changes
  update spatial index, recalculate visibility
```

## Hierarchical Entities

### Parent-Child Relationships

```
Scene tree as ECS hierarchy:

Entity 0 (Player):
  Components: [Position(100, 200), Velocity(1, 0), Player]
  Children: [Entity 1, Entity 2]

  Entity 1 (Weapon — child of Player):
    Components: [LocalPosition(10, -5), Sprite("sword.png"), Weapon]
    # World position = parent.Position + self.LocalPosition = (110, 195)

  Entity 2 (Particle Emitter — child of Player):
    Components: [LocalPosition(0, 0), ParticleEmitter]
```

### Transform Propagation

```
transform_propagation_system:
  for each entity with (Parent, LocalPosition):
    parent_pos = world.get<Position>(entity.parent)
    world_pos = parent_pos + entity.local_position
    entity.set<WorldPosition>(world_pos)

  # Must run top-down — parents before children
  # Typical approach: sort by hierarchy depth, or iterate in tree order
```

### Hierarchy Operations

| Operation | Implementation | Cost |
|-----------|---------------|------|
| Add child | Set Parent component on child, add to parent's Children list | O(1) |
| Remove child | Remove Parent component, remove from Children list | O(1) |
| Destroy with children | Recursively despawn children, then parent | O(depth * children) |
| Reparent | Update Parent component, move between Children lists | O(1) |
| Find root | Walk Parent chain until no parent | O(depth) |

## MMO-Scale Considerations

### Entity Limits

| Scale | Entity count | Storage strategy | Key challenge |
|-------|-------------|-----------------|---------------|
| Single-player | 100–10K | Archetype or sparse set | Not a concern |
| Co-op (4-8 players) | 1K–50K | Archetype preferred | Network sync |
| MMO zone | 10K–100K | Archetype with chunking | Spatial partitioning, interest management |
| MMO world | 100K–1M+ | Sharded worlds, zone streaming | Cross-shard entity migration |

### Spatial Partitioning

```
Grid-based partitioning:
  World divided into cells (e.g., 64x64 units)
  Each cell tracks which entities are inside it
  Queries only check relevant cells

  spatial_index_system:
    for each entity with (Position, SpatialCell):
      new_cell = position_to_cell(entity.position)
      if new_cell != entity.current_cell:
        remove entity from old cell
        add entity to new cell
        update entity.current_cell
```

| Partitioning method | Best for | Update cost |
|-------------------|----------|-------------|
| Uniform grid | Even distribution, fixed world size | O(1) per entity move |
| Quadtree/Octree | Uneven distribution, clustered entities | O(log N) per move |
| Spatial hashing | Infinite worlds, uniform density | O(1) per move |
| BSP tree | Static geometry, raycast-heavy | O(log N) query, expensive rebuild |

### Interest Management

```
Only send updates about entities the player can perceive:

interest_management_system:
  for each Player:
    relevant_cells = cells_within_radius(player.position, view_distance)
    relevant_entities = entities_in_cells(relevant_cells)

    for entity in relevant_entities:
      if entity not in player.known_entities:
        send_spawn(player, entity)     # entity enters area of interest
        player.known_entities.add(entity)

    for entity in player.known_entities:
      if entity not in relevant_entities:
        send_despawn(player, entity)    # entity leaves area of interest
        player.known_entities.remove(entity)
      else:
        send_update(player, entity)    # position/state sync
```

## Framework Comparison

### Godot's Node System vs Pure ECS

Godot uses an object-oriented scene tree, not a pure ECS. Understanding the trade-offs:

| Aspect | Godot Nodes | Pure ECS |
|--------|------------|----------|
| Entity | Node instance | Integer ID |
| Component | Node properties + attached scripts | Plain data struct |
| System | `_process()` / `_physics_process()` per node | Free function over component queries |
| Hierarchy | Built-in scene tree | Manual Parent/Children components |
| Editor integration | Visual scene editor, inspector | Requires custom tooling |
| Cache performance | Objects scattered in heap | Contiguous component arrays |
| Learning curve | Intuitive for small projects | Steeper, pays off at scale |
| Best for | Prototyping, small-mid games, UI | Large entity counts, data-heavy simulations |

**Hybrid approach in Godot**: Use nodes for the scene tree (cameras, UI, level structure) and a custom ECS or data-oriented approach for game entities (bullets, particles, NPCs). Godot 4's `MultiMeshInstance3D` and `PhysicsServer3D` direct API enable data-oriented patterns without a full ECS.

### Bevy ECS (Rust)

```rust
use bevy::prelude::*;

#[derive(Component)]
struct Position { x: f32, y: f32 }

#[derive(Component)]
struct Velocity { x: f32, y: f32 }

fn movement_system(mut query: Query<(&mut Position, &Velocity)>) {
    for (mut pos, vel) in &mut query {
        pos.x += vel.x;
        pos.y += vel.y;
    }
}

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_systems(Update, movement_system)
        .run();
}
```

Key Bevy ECS features:
- Archetype-based storage with automatic parallel scheduling
- `Changed<T>` and `Added<T>` filters for reactive systems
- `Commands` for deferred entity spawn/despawn (avoids iterator invalidation)
- `Resource` for singleton world data
- `Events<T>` with automatic double-buffering

### Flecs (C/C++)

```c
// Flecs — high-performance C ECS with query caching
ecs_world_t *world = ecs_init();

// Define components
ECS_COMPONENT(world, Position);
ECS_COMPONENT(world, Velocity);

// Create entity
ecs_entity_t e = ecs_new(world);
ecs_set(world, e, Position, {10, 20});
ecs_set(world, e, Velocity, {1, 0});

// Define system
ECS_SYSTEM(world, MoveSystem, EcsOnUpdate, Position, Velocity);

void MoveSystem(ecs_iter_t *it) {
    Position *p = ecs_field(it, Position, 0);
    Velocity *v = ecs_field(it, Velocity, 1);

    for (int i = 0; i < it->count; i++) {
        p[i].x += v[i].x;
        p[i].y += v[i].y;
    }
}
```

Key Flecs features:
- Query caching — queries are evaluated once and cached until archetypes change
- Relationships — first-class support for entity relationships (parent/child, likes, etc.)
- Reflection — runtime component inspection for editors and serialization
- Multithreading — automatic system parallelization based on component access
- REST API — built-in web explorer for debugging entity state

## Anti-patterns

### God Components

```
# BAD — one component that holds everything
struct GameEntity {
    position: Vec2,
    velocity: Vec2,
    health: f32,
    damage: f32,
    sprite: Texture,
    ai_state: AIState,
    inventory: Vec<Item>,
    dialog: Vec<String>,
}

# GOOD — decompose into focused components
Position { x, y }
Velocity { dx, dy }
Health { current, max }
DamageDealer { amount }
Sprite { texture }
AIBehavior { state }
Inventory { items }
DialogSource { lines }
```

**Why it matters**: God components defeat the purpose of ECS. Systems that only need position must load the entire struct. Adding a new field to the god component invalidates every system's cache line.

### System Coupling

```
# BAD — damage system directly modifies score
fn damage_system(query: Query<&mut Health, &DamageEvent>, score: &mut Score) {
    // This system now depends on Score — can't run without it
    // Testing requires Score even though damage logic doesn't need it
}

# GOOD — damage system emits events, score system consumes them
fn damage_system(query: Query<&mut Health>, events: &DamageEvents, mut kill_events: EventWriter<KillEvent>) {
    // Process damage, emit KillEvent when health reaches zero
}

fn score_system(kill_events: EventReader<KillEvent>, mut score: ResMut<Score>) {
    // Score system listens for kills independently
}
```

### Over-Querying

```
# BAD — system queries everything, filters in code
fn render_system(query: Query<&Position, &Sprite, Option<&Velocity>, Option<&Health>,
                              Option<&AIBehavior>, Option<&Inventory>>) {
    for (pos, sprite, vel, health, ai, inv) in &query {
        // Only uses pos and sprite — the rest are wasted memory loads
    }
}

# GOOD — query only what the system needs
fn render_system(query: Query<&Position, &Sprite>) {
    for (pos, sprite) in &query {
        draw(sprite, pos);
    }
}
```

### Archetype Thrashing

```
# BAD — adding and removing components every frame
fn flash_system(query: Query<Entity, &FlashTimer>) {
    for (entity, timer) in &query {
        if timer.visible {
            commands.insert(entity, Visible);    // moves entity to new archetype
        } else {
            commands.remove::<Visible>(entity);  // moves entity back
        }
    }
}

# GOOD — use a flag inside the component
fn flash_system(query: Query<&mut Sprite, &FlashTimer>) {
    for (mut sprite, timer) in &query {
        sprite.visible = timer.should_show();  // no archetype change
    }
}
```

## Cross-References

- **gamedev-multiplayer** — networking patterns that layer on top of ECS (state sync, input prediction, entity authority)
- **gamedev-godot** — Godot-specific implementation of node-based and hybrid data-oriented patterns
- **data-systems-reference** — general systems design theory applicable to ECS scheduling and data flow
