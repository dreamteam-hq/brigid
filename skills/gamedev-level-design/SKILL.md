---
name: gamedev-level-design
description: "2D level design patterns — Metroidvania structure, difficulty curves, tutorial design, data-driven content, Godot MCP workflows"
triggers:
  - level design
  - Metroidvania
  - difficulty curve
  - tutorial design
  - secret areas
  - ability gating
  - map connectivity
  - checkpoint placement
  - data-driven content
version: "1.0.0"
---

# 2D Level Design Patterns

Design and implement hand-crafted 2D levels with Metroidvania structure, intentional difficulty curves, embedded tutorials, data-driven content pipelines, and hidden areas. Covers map connectivity graphs, ability-gated progression, checkpoint strategy, and Godot MCP workflows for TileMap painting and room composition.

## Metroidvania Structure

### Ability-Gated Progression

The core Metroidvania loop: the player sees inaccessible areas early, acquires an ability later, and returns to unlock them. Every gate must be visually distinct so the player mentally catalogs "I need to come back here."

| Gate Type | Required Ability | Visual Tell | Example |
|-----------|-----------------|-------------|---------|
| High ledge | Double jump | Platform visible but out of reach | Ledge 3 tiles above max single-jump height |
| Destructible wall | Wall break / bomb | Cracked texture, dust particles | Cracked stone blocks in otherwise solid wall |
| Narrow passage | Dash / slide | Low gap with shimmer or wind particles | 1-tile-high tunnel with air current effect |
| Dark room | Lantern / light | Darkness visible at doorway threshold | Room fades to black past the entrance |
| Water barrier | Swim ability | Water surface blocking corridor | Submerged passage with bubble particles |
| Grapple point | Grapple hook | Anchor point with subtle glow | Ceiling hook with chain fragment visual |

**Design rule**: Every gate the player encounters before obtaining the ability should be memorable. Place gates at dead ends or beside reward teasers (visible collectible behind the barrier) so the player has motivation to return.

### Map Connectivity Graph

Model the world as a directed graph before building any rooms. Nodes are rooms/zones; edges are connections with optional gate labels.

```
# Map connectivity as adjacency list with gate annotations
map_graph = {
    "entrance_hall": [
        {"to": "east_corridor", "gate": null},
        {"to": "upper_balcony", "gate": "double_jump"},
        {"to": "basement", "gate": "wall_break"}
    ],
    "east_corridor": [
        {"to": "entrance_hall", "gate": null},
        {"to": "crystal_caves", "gate": null},
        {"to": "hidden_armory", "gate": "dash"}
    ],
    "crystal_caves": [
        {"to": "east_corridor", "gate": null},
        {"to": "boss_arena_1", "gate": null},
        {"to": "deep_caves", "gate": "swim"}
    ]
}
```

Validate the graph before building rooms:
- **Reachability**: Every room must be reachable with some subset of abilities. No room should require an ability only obtainable inside that room.
- **Ability ordering**: Define a strict acquisition order. Verify that each ability's location is reachable using only previously acquired abilities.
- **Cycle check**: The graph should contain cycles (backtracking paths) but no deadlocks where the player gets permanently stuck.

### Backtracking Incentives

Backtracking is only fun if the player gains something on the return trip. Without incentives, retreading old ground feels like padding.

| Incentive Type | Implementation | Effect |
|---------------|----------------|--------|
| New ability reveals secrets | Gate unlocks in previously visited rooms | Exploration reward |
| Enemy remixes | Harder enemy variants spawn in old rooms after boss defeat | Combat stays fresh |
| Shortcut unlocks | One-way doors, elevators, or teleporters open from the far side | Reduces future traversal time |
| Map completion rewards | Percentage tracker with milestone rewards (25%, 50%, 75%, 100%) | Completionist motivation |
| Environmental storytelling | New details appear in old rooms after story beats | Narrative reward |
| NPC relocation | NPCs move to previously empty rooms as the story progresses | World feels alive |

### Shortcut Networks

Shortcuts collapse the effective diameter of the map. A well-placed shortcut turns a 5-minute backtrack into a 30-second loop.

**One-way door pattern**: The player approaches a locked door from the far side and opens it. The door stays open permanently. The player now has a fast path between two previously distant areas.

```
# Shortcut door — one-way unlock
# Place a StaticBody2D door. On the "unlock side", add an Area2D interaction trigger.

func _on_interaction_area_body_entered(body):
    if body.is_in_group("player") and not is_unlocked:
        is_unlocked = true
        door_collision.disabled = true
        play_open_animation()
        # Persist unlock state
        GameManager.register_shortcut(shortcut_id)
```

**Elevator/teleporter pattern**: Bidirectional fast travel between two fixed points. Only activate after the player reaches both endpoints on foot.

**Design rule**: Place at least one shortcut unlock per major zone. The shortcut should connect the zone's far end back to a hub or save point.

### Zone Theming

Each zone needs a distinct visual identity, enemy set, and mechanical twist so the player always knows where they are.

| Zone Element | Purpose | Example |
|-------------|---------|---------|
| Color palette | Instant visual identification | Forest = green/brown, Caves = blue/purple |
| Tileset | Reinforces theme | Organic tiles for forest, angular for factory |
| Enemy types | Zone-specific behavior patterns | Forest: ranged archers; Caves: burrowing worms |
| Mechanical twist | Unique gameplay element per zone | Caves: darkness + lantern radius; Factory: conveyor belts |
| Music track | Audio identification | Each zone gets its own theme |
| Ambient sound | Environmental reinforcement | Dripping water in caves, birdsong in forest |

## Difficulty Curves

### Ramping Formulas

Difficulty should ramp nonlinearly. Linear difficulty feels flat in the middle and spikes too hard at the end. Use stepped or logarithmic curves.

**Stepped curve** (recommended for Metroidvanias): Difficulty plateaus within each zone and jumps at zone transitions. Players master the current zone's patterns before facing new challenges.

```
# Stepped difficulty: each zone has a base difficulty, rooms within are ±10%
zone_difficulty = {
    "forest": 1.0,
    "caves": 1.6,
    "factory": 2.2,
    "fortress": 3.0,
    "final": 4.0
}

func get_room_difficulty(zone: String, room_progress: float) -> float:
    var base = zone_difficulty[zone]
    var variance = base * 0.1 * (room_progress - 0.5)  # ±10% across zone
    return base + variance
```

**Logarithmic curve** (recommended for procedural/roguelike): Difficulty increases rapidly early, then decelerates. The player faces meaningful challenge quickly but the late game does not become impossible.

```
# Logarithmic: difficulty = base * (1 + k * ln(1 + room_index))
func get_difficulty(room_index: int, k: float = 0.5) -> float:
    return 1.0 + k * log(1.0 + room_index)
```

### Enemy Placement Strategy

Enemy placement is the primary lever for controlling moment-to-moment difficulty. Every enemy placement should have a reason.

| Placement Pattern | Purpose | Example |
|------------------|---------|---------|
| Gatekeeper | Block forward progress until defeated | Single tough enemy in a narrow corridor |
| Ambush | Punish carelessness, teach vigilance | Enemies spawn when player steps on trigger |
| Gauntlet | Test sustained combat ability | Long corridor with waves of enemies |
| Sniper perch | Force the player to use movement skills | Ranged enemy on elevated platform |
| Combo encounter | Test ability to handle multiple threat types | Melee + ranged enemies together |
| Tutorial enemy | Teach a mechanic safely | Single slow enemy near a new ability pickup |

**Density guidelines**: 2-4 enemies per screen in early zones, 4-6 in mid zones, 6-8 in late zones. Boss rooms have 1 boss + 0-3 adds. Never place more enemies than the player can track visually.

### Risk/Reward Spacing

Alternate high-risk and low-risk segments. Sustained high intensity causes fatigue; sustained low intensity causes boredom.

```
Tension graph for a well-paced zone:

Intensity
  █
  █     ██         ████
  █    ████   █   ██████    ████
  █   ██████ ███ ████████  ██████   BOSS
  █  ████████████████████████████████████
  █▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
  Entry  Combat  Rest  Combat  Rest  Arena
```

**Rest nodes**: Rooms with no enemies, a save point, and optionally an NPC or shop. Place one before every boss and one after every major combat gauntlet. Rest nodes also serve as orientation landmarks.

### Checkpoint Frequency

Checkpoint spacing directly controls frustration tolerance. Too sparse and the player quits after repeated deaths. Too frequent and death has no consequence.

| Game Style | Checkpoint Spacing | Rationale |
|-----------|-------------------|-----------|
| Exploration-focused | Every 2-3 rooms | Minimize traversal repetition |
| Combat-focused | Before and after gauntlets | Respect player's combat investment |
| Hardcore / Soulslike | Sparse (every 5-8 rooms) | Death is a meaningful setback |
| Boss encounters | Always before boss door | Never make the player repeat a corridor to retry a boss |

**Placement rules**:
- Always place a checkpoint before a boss fight
- Always place a checkpoint after acquiring a new ability
- Place checkpoints at zone transitions
- Place checkpoints before and after long vertical or hazard traversal sections
- Never place a checkpoint mid-combat-encounter

### Boss Difficulty Calibration

Bosses are difficulty spikes by design, but the spike should be proportional to the zone's base difficulty.

| Boss Phase | Health % | Pattern Complexity | Attack Speed | Adds |
|-----------|---------|-------------------|-------------|------|
| Phase 1 | 100-66% | 2-3 attacks, long telegraphs | Slow | None |
| Phase 2 | 66-33% | 4-5 attacks, shorter telegraphs | Medium | 0-2 weak adds |
| Phase 3 | 33-0% | All attacks + new desperation move | Fast | 0-3 adds or environmental hazards |

**Test rule**: If an average player cannot reach phase 2 within 3 attempts, phase 1 is too hard. If they beat the boss in under 3 attempts, the boss is too easy. Target 5-8 attempts for a satisfying challenge.

## Tutorial Through Design

### Teaching Mechanics Without Text

The best tutorials never use text boxes. Instead, they use level geometry and enemy placement to force the player to discover mechanics naturally.

**The four-step teaching pattern**:

1. **Introduce** — Present the mechanic in a zero-risk environment. The player cannot fail.
2. **Demonstrate** — Show the mechanic's utility against a trivial obstacle.
3. **Test** — Require the mechanic to progress, with moderate consequence for failure.
4. **Master** — Combine the mechanic with others in a high-stakes scenario.

### Gated Introductions

When the player acquires a new ability, the next room should be a dedicated teaching space for that ability.

| Ability | Introduction Room Design |
|---------|------------------------|
| Double jump | Pit too wide for single jump, platform at mid-height, safe landing on both sides |
| Wall jump | Vertical shaft with alternating walls, coins tracing the intended path |
| Dash | Narrow horizontal gap with spikes above and below, timed obstacle after |
| Bomb/wall break | Cracked wall with collectible visible behind it, no enemies |
| Grapple | Grapple point over a pit, short swing to safe platform |

### Safe Practice Spaces

After introducing a mechanic, provide a sequence of 3-5 rooms that use it with escalating complexity before mixing it with combat.

```
Room sequence after acquiring double jump:

Room 1: [TEACH]   Flat ground → gap → platform at double-jump height
                   No enemies, no hazards. Pure mechanics.

Room 2: [APPLY]   Two gaps in sequence, second requires mid-air direction change
                   Still no enemies. Building muscle memory.

Room 3: [COMBINE] Gap with moving platform that requires double jump timing
                   One slow enemy on the far side. First taste of
                   double-jump-while-threatened.

Room 4: [TEST]    Vertical shaft requiring chained double jumps + wall jumps
                   Two ranged enemies on platforms. Real challenge begins.
```

### Environmental Cues

Guide the player without explicit markers by exploiting visual hierarchy and level geometry.

| Cue Type | Implementation | Purpose |
|----------|---------------|---------|
| Light sources | Torch, glowing crystal, sunbeam | Draw attention to paths and items |
| Coin/collectible trails | Line of pickups tracing intended path | Breadcrumb navigation |
| Contrasting tile | Different-colored floor tile near interactable | "Something is different here" |
| Parallax depth | Background detail visible through gap | Hint at connected space |
| NPC placement | Friendly NPC standing near mechanic | Implicit "try this here" |
| Enemy positioning | Single enemy demonstrating a mechanic | Player sees enemy using wall jump, learns walls are jumpable |

### What Not to Do

- Never pause gameplay for a text tutorial when level design can teach the mechanic
- Never introduce two new mechanics simultaneously
- Never test a mechanic before teaching it
- Never place a fail state in the introduction room
- Never assume the player read a tooltip — they did not

## Data-Driven Content

### Enemy Stats in Resource Files

Define enemy stats externally so designers can tune without touching code. Use Godot Resource files or JSON.

**JSON approach** (recommended for large projects with many enemy types):

```json
{
  "enemies": {
    "slime": {
      "hp": 20,
      "damage": 5,
      "speed": 60.0,
      "detection_range": 120.0,
      "attack_cooldown": 1.5,
      "xp_reward": 10,
      "drops": [
        {"item": "slime_gel", "chance": 0.3},
        {"item": "health_orb", "chance": 0.1}
      ]
    },
    "skeleton_archer": {
      "hp": 35,
      "damage": 12,
      "speed": 45.0,
      "detection_range": 200.0,
      "attack_cooldown": 2.0,
      "projectile_speed": 180.0,
      "xp_reward": 25,
      "drops": [
        {"item": "bone_fragment", "chance": 0.25},
        {"item": "arrow_bundle", "chance": 0.15}
      ]
    }
  }
}
```

**Godot Resource approach** (recommended for smaller projects, better editor integration):

```
# enemy_data.gd — custom Resource class
class_name EnemyData extends Resource

@export var display_name: String
@export var hp: int
@export var damage: int
@export var speed: float
@export var detection_range: float
@export var attack_cooldown: float
@export var xp_reward: int
@export var drop_table: Array[DropEntry]
```

Create `.tres` files per enemy type. Designers edit them in the Godot inspector without opening scripts.

### Loot Tables

Loot tables define what items drop, with what probability, and under what conditions. Separate the loot logic from the enemy logic.

```json
{
  "loot_tables": {
    "forest_common": {
      "rolls": 1,
      "entries": [
        {"item": "health_orb", "weight": 40},
        {"item": "mana_orb", "weight": 30},
        {"item": "coin_small", "weight": 25},
        {"item": "herb", "weight": 5}
      ]
    },
    "boss_crystal_golem": {
      "guaranteed": ["crystal_heart_fragment"],
      "rolls": 2,
      "entries": [
        {"item": "crystal_shard", "weight": 50},
        {"item": "rare_gem", "weight": 30},
        {"item": "golem_core", "weight": 15},
        {"item": "legendary_crystal", "weight": 5}
      ]
    }
  }
}
```

**Weighted selection algorithm**:
```
func roll_loot(table_id: String) -> Array[String]:
    var table = loot_data.loot_tables[table_id]
    var results = []
    # Add guaranteed drops
    if table.has("guaranteed"):
        results.append_array(table.guaranteed)
    # Roll random drops
    for i in range(table.rolls):
        var total_weight = 0
        for entry in table.entries:
            total_weight += entry.weight
        var roll = randi() % total_weight
        var cumulative = 0
        for entry in table.entries:
            cumulative += entry.weight
            if roll < cumulative:
                results.append(entry.item)
                break
    return results
```

For pity timers, pseudo-random distribution, and multiplayer loot fairness, load `procedural-generation-2d`.

### Dialog Trees

Store dialog as structured data so writers can author conversations without modifying scripts.

```json
{
  "dialogs": {
    "npc_blacksmith_intro": {
      "nodes": {
        "start": {
          "speaker": "Blacksmith",
          "text": "Haven't seen your face before. You here about the caves?",
          "choices": [
            {"text": "What's in the caves?", "next": "caves_info"},
            {"text": "Can you upgrade my gear?", "next": "shop_intro"},
            {"text": "Just passing through.", "next": "end_neutral"}
          ]
        },
        "caves_info": {
          "speaker": "Blacksmith",
          "text": "Crystals. Dangerous ones. But the ore down there...",
          "condition_set": "knows_about_caves",
          "next": "caves_warning"
        },
        "caves_warning": {
          "speaker": "Blacksmith",
          "text": "Take a lantern. You won't last ten seconds in the dark.",
          "next": "end_helpful"
        },
        "shop_intro": {
          "speaker": "Blacksmith",
          "text": "Bring me materials and I'll see what I can do.",
          "action": "open_shop",
          "next": "end_shop"
        }
      }
    }
  }
}
```

**Dialog runner pattern**: A DialogManager node loads the JSON, walks the node graph, and emits signals for the UI to display text and choices. The dialog data never references scene paths or node names — it only references action IDs that the game logic maps to functions.

### Quest Definitions

Define quests as data with objectives, conditions, and rewards.

```json
{
  "quests": {
    "blacksmith_ore": {
      "title": "Crystal Ore Delivery",
      "description": "Bring 5 crystal ore from the caves to the blacksmith.",
      "giver": "npc_blacksmith",
      "prerequisites": ["knows_about_caves"],
      "objectives": [
        {
          "type": "collect",
          "item": "crystal_ore",
          "count": 5,
          "description": "Collect crystal ore (0/5)"
        },
        {
          "type": "deliver",
          "target": "npc_blacksmith",
          "item": "crystal_ore",
          "count": 5,
          "description": "Deliver ore to the blacksmith"
        }
      ],
      "rewards": {
        "xp": 100,
        "items": ["reinforced_sword"],
        "unlocks": ["blacksmith_tier_2"]
      }
    }
  }
}
```

**Quest state machine**: `unavailable` → `available` → `active` → `complete` → `turned_in`. Track objective progress in the save file. Never hardcode quest logic — the quest runner reads definitions and fires signals.

### Room Layout Data

Define room metadata externally so the map system can display room info without loading every scene.

```json
{
  "rooms": {
    "forest_01": {
      "scene": "res://scenes/rooms/forest/forest_01.tscn",
      "zone": "forest",
      "bounds": {"x": 0, "y": 0, "w": 1920, "h": 1080},
      "connections": {
        "east": "forest_02",
        "up": "forest_01_upper"
      },
      "has_save_point": true,
      "has_shop": false,
      "enemies": ["slime", "slime", "bat"],
      "items": ["health_upgrade_03"],
      "secrets": 1
    }
  }
}
```

## Secret Areas

### Breakable Walls

The classic hidden passage. A wall segment that looks slightly different and crumbles when attacked or bombed.

**Visual tells** (the player should be able to spot them on careful observation):
- Slightly different tile texture or shade
- Hairline cracks in the wall surface
- Dust particles falling from the ceiling near the wall
- Sound difference when the player walks near (subtle echo)
- Enemy projectile hits the wall and causes a small dust puff

**Implementation**:
```
# BreakableWall.tscn — StaticBody2D with AnimatedSprite2D
@export var required_ability: String = ""  # Empty = any attack works
@export var hp: int = 1  # Hits needed to break

func take_hit(ability: String):
    if required_ability != "" and ability != required_ability:
        # Wrong ability — play "thud" feedback so player knows it's special
        play_reject_feedback()
        return
    hp -= 1
    if hp <= 0:
        break_wall()

func break_wall():
    play_crumble_animation()
    play_crumble_sound()
    spawn_debris_particles()
    collision_shape.disabled = true
    # Persist so wall stays broken after revisit
    GameManager.register_secret(secret_id)
    await crumble_animation_finished
    queue_free()
```

### Hidden Paths

Passages concealed by foreground tiles that the player walks behind. The foreground fades to transparent when the player enters the hidden area.

```
# ForegroundMask.tscn — Area2D covering the hidden path
# Child: Sprite2D or TileMap layer with Z-index above the player

func _on_body_entered(body):
    if body.is_in_group("player"):
        var tween = create_tween()
        tween.tween_property(foreground_sprite, "modulate:a", 0.2, 0.3)

func _on_body_exited(body):
    if body.is_in_group("player"):
        var tween = create_tween()
        tween.tween_property(foreground_sprite, "modulate:a", 1.0, 0.3)
```

Place a subtle visual cue at the entrance — a single pixel gap, a slightly misaligned tile, or a draft particle effect.

### Reward Calibration

Secrets must feel worth finding. Scale rewards based on how hidden the secret is.

| Secret Difficulty | Discovery Method | Appropriate Reward |
|------------------|-----------------|-------------------|
| Easy (visible crack) | Attack obvious cracked wall | Small health/mana pickup, coins |
| Medium (environmental cue) | Notice subtle tile difference, explore dead end | Equipment upgrade, ability enhancement |
| Hard (requires deduction) | Bomb unmarked wall, sequence of hidden inputs | Major health upgrade, unique ability, lore item |
| Extreme (community-discovery) | Obscure trigger, requires backtracking with late-game ability | Cosmetic, achievement, developer room |

**Design rules**:
- Every secret should contain a reward. An empty hidden room is worse than no secret at all.
- Place at least one easy secret per zone so players learn to look for them.
- Track secrets found per zone in the map screen (e.g., "Secrets: 2/4").
- Hard secrets should reward exploration skill, not trial-and-error wall-bombing.

### Sound Design for Secrets

Audio cues are powerful hints that don't break immersion.

| Audio Cue | Trigger | Purpose |
|-----------|---------|---------|
| Hollow footstep | Walking over breakable floor | "Something is different here" |
| Wind whistle | Near hidden passage entrance | "There's an opening nearby" |
| Chime | Entering secret area | Confirmation reward |
| Distant music box | Near well-hidden secret | "Keep searching this area" |

## Godot MCP Integration

### TileMap Painting Workflows

Use the Godot MCP server to programmatically paint TileMap layers for level construction.

**Room floor and walls**:
```
# 1. Create or open the room scene
scene_create(root_type="Node2D", scene_name="forest_01")

# 2. Add TileMap node
scene_node_add(parent="/root", type="TileMap", name="TileMap")

# 3. Set the TileSet resource
scene_node_properties(node_path="TileMap",
    property="tile_set",
    value="res://resources/tilesets/forest_tileset.tres")

# 4. Paint ground tiles (layer 0 = collision layer)
# Paint a flat floor from (0,10) to (30,10)
for x in range(31):
    tilemap_paint(node_path="TileMap", layer=0,
        coords={"x": x, "y": 10},
        source_id=0, atlas_coords={"x": 1, "y": 0})

# 5. Paint walls
for y in range(11):
    tilemap_paint(node_path="TileMap", layer=0,
        coords={"x": 0, "y": y},
        source_id=0, atlas_coords={"x": 0, "y": 0})
    tilemap_paint(node_path="TileMap", layer=0,
        coords={"x": 30, "y": y},
        source_id=0, atlas_coords={"x": 0, "y": 0})
```

**Decorative background layer**:
```
# Paint background decoration tiles on layer 1 (no collision)
# Scatter moss, vines, and stone detail tiles
tilemap_paint(node_path="TileMap", layer=1,
    coords={"x": 5, "y": 9},
    source_id=0, atlas_coords={"x": 3, "y": 2})  # Moss tile
```

### Room Scene Composition

Build complete room scenes by combining TileMap, triggers, enemies, and environmental objects via MCP.

```
# 1. Create room scene
scene_create(root_type="Node2D", scene_name="caves_03")

# 2. Add TileMap for terrain
scene_node_add(parent="/root", type="TileMap", name="Terrain")

# 3. Add spawn points for enemies (Position2D markers)
scene_node_add(parent="/root", type="Marker2D", name="EnemySpawn_1")
scene_node_properties(node_path="EnemySpawn_1",
    property="position", value={"x": 320, "y": 480})

scene_node_add(parent="/root", type="Marker2D", name="EnemySpawn_2")
scene_node_properties(node_path="EnemySpawn_2",
    property="position", value={"x": 640, "y": 480})

# 4. Add checkpoint save point
scene_node_add(parent="/root", type="Area2D", name="Checkpoint")
scene_node_properties(node_path="Checkpoint",
    property="position", value={"x": 160, "y": 480})
scene_node_add(parent="Checkpoint", type="CollisionShape2D",
    name="CheckpointShape")

# 5. Add room transition trigger
scene_node_add(parent="/root", type="Area2D", name="ExitEast")
scene_node_properties(node_path="ExitEast",
    property="position", value={"x": 960, "y": 300})
```

### Level Inspection with scene_nodes

Use `scene_nodes` to audit existing room scenes for completeness and correctness.

```
# Inspect a room scene to verify it has all required components
scene_nodes(scene_path="res://scenes/rooms/forest/forest_01.tscn")

# Expected structure for a well-formed room:
# /root (Node2D)
#   /Terrain (TileMap) — must have collision layer
#   /Background (TileMap or ParallaxBackground) — visual backdrop
#   /Enemies (Node2D) — container for enemy spawn points
#     /EnemySpawn_1 (Marker2D)
#     /EnemySpawn_2 (Marker2D)
#   /Triggers (Node2D) — container for area triggers
#     /Checkpoint (Area2D)
#     /ExitEast (Area2D)
#     /ExitWest (Area2D)
#   /Secrets (Node2D) — container for secret areas
#     /BreakableWall_1 (StaticBody2D)
#   /Camera (Camera2D) — with limits set to room bounds

# Validation checklist:
# - TileMap has at least one physics layer with collision shapes
# - Every exit has a matching connection in room_data.json
# - Camera limits match room bounds
# - At least one checkpoint per room (or room is < 2 screens wide)
```

### Door and Portal Trigger Wiring via signal_connect

Wire room transitions by connecting Area2D signals to transition logic through the MCP.

```
# 1. Add door trigger areas at room boundaries
scene_node_add(parent="/root", type="Area2D", name="DoorEast")
scene_node_properties(node_path="DoorEast",
    property="position", value={"x": 952, "y": 300})
scene_node_add(parent="DoorEast", type="CollisionShape2D",
    name="DoorEastShape")

# 2. Connect the body_entered signal to the room transition handler
signal_connect(
    node_path="DoorEast",
    signal_name="body_entered",
    target_path="/root",
    method_name="_on_door_east_entered"
)

# 3. For bidirectional portals, wire both endpoints
scene_node_add(parent="/root", type="Area2D", name="PortalA")
signal_connect(
    node_path="PortalA",
    signal_name="body_entered",
    target_path="/root",
    method_name="_on_portal_entered"
)
```

**Room transition script pattern** (attach to the room root):
```
# The signal handler triggered by MCP-wired door signals
func _on_door_east_entered(body):
    if body.is_in_group("player"):
        RoomManager.transition_to(
            target_room="forest_02",
            spawn_point="entry_west"
        )
```

### Rapid Level Iteration

Combine MCP workflows for fast level building cycles:

1. `scene_create` — scaffold the room with terrain and triggers
2. `scene_node_add` + `scene_node_properties` — place enemies, checkpoints, secrets
3. `signal_connect` — wire door transitions
4. `scene_save` — persist the scene
5. `editor_run` — playtest immediately
6. `scene_nodes` — inspect and verify structure
7. Adjust and repeat

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Ability before gate | Player gets ability but has no locked doors to use it on yet — no "aha" moment | Show gates first, grant ability second |
| Invisible walls | Blocking the player with invisible collision instead of visible geometry | Always use visible barriers; if passage is closed, show a door or rubble |
| Unmarked points of no return | Player passes a threshold and cannot backtrack without warning | Either allow backtracking or display a clear "this path is one-way" signal |
| Difficulty cliff | Sudden massive difficulty spike between two adjacent rooms | Ramp difficulty within zones; save spikes for boss encounters |
| Checkpoint deserts | Long stretches with no save point, especially before boss corridors | Place checkpoint before every boss and every 2-3 rooms minimum |
| Empty backtracking | Forcing the player to retread old ground with nothing new to find | Add shortcuts, new enemy variants, or ability-gated secrets along backtrack routes |
| Pixel-hunt secrets | Secrets that require bombing every single wall tile to find | Provide at least a subtle visual or audio cue for every secret |
| Text-wall tutorials | Pausing the game to explain a mechanic in a dialog box | Teach through level design using the four-step pattern |
| Static world | The game world never changes regardless of player progress | NPCs relocate, new enemies appear, shortcuts unlock, environment reacts to story |
| Monolithic room scenes | Entire zones as single massive scenes instead of modular rooms | Each room is its own scene; a RoomManager handles loading and transitions |
| Hardcoded enemy stats | Enemy HP, damage, and speed defined in script `_ready()` functions | Use Resource files or JSON so designers can tune without code changes |
| Door-without-destination | Door triggers that reference hardcoded room paths instead of data | Room connections defined in JSON; door scripts read connection data |

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-2d-platformer` | Movement physics, combat systems, character state machines, TileMap collision setup |
| `gamedev-2d-ai` | Enemy behavior trees, patrol patterns, boss AI state machines, aggro ranges |
| `procedural-generation-2d` | Algorithmic level generation, loot table math, WFC for room layouts, pity timers |
| `gamedev-2d-art-pipeline` | Tileset creation, sprite sheets, parallax asset preparation, lighting setup |
| `gamedev-godot` | Godot engine fundamentals, scene architecture, MCP server workflow reference |
| `game-economy-design` | Reward scaling, currency balance, shop pricing, sink/faucet analysis |
