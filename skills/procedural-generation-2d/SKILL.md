---
name: procedural-generation-2d
description: >
  Procedural content generation for 2D games — level generation, terrain, loot tables,
  WFC, cellular automata, multiplayer PCG. Load when the user mentions "procedural generation",
  "PCG", "level generation", "wave function collapse", "cellular automata", "loot table",
  "drop table", "terrain generation", "procedural level", "random generation", "pity timer",
  "biome transition", "seed synchronization", or "chunk streaming".
  Triggers: procedural generation, PCG, level generation, wave function collapse, cellular automata, loot table, drop table, terrain generation, procedural level, random generation.
---

# Procedural Content Generation for 2D Games

## Level Generation Algorithm Selection

Pick the right algorithm for the content type. Wrong choice means fighting the algorithm instead of tuning content.

### Decision Table

| Content Type | Best Algorithm | Runner-Up | Avoid | Why |
|---|---|---|---|---|
| Dungeon rooms + corridors | BSP tree / grammar-based | Cellular automata | Pure noise | Need guaranteed connectivity |
| Cave systems | Cellular automata | Marching squares on noise | BSP | Organic shapes, no right angles |
| Platformer levels | Grammar-based / rhythm | WFC with custom tiles | Cellular automata | Jumpability constraints dominate |
| Overworld / terrain | Multi-octave noise | Diamond-square | WFC | Continuous, non-tiling output needed |
| Tile-based town/village | Wave Function Collapse | Template stitching | Noise | Local adjacency rules match tile sets |
| Maze / labyrinth | Recursive backtracking | Kruskal's on grid | Noise | Perfect mazes need spanning-tree algos |
| Branching paths (roguelike map) | Graph-first, render second | L-systems | BSP | Topology matters more than geometry |
| Vegetation / foliage placement | Poisson disk sampling | Noise threshold | Grid | Natural spacing, no clumping |
| Interior / room furnishing | Constraint satisfaction | Template + random swap | Noise | Furniture has placement rules |

### Algorithm Deep Dives

#### Wave Function Collapse (WFC)

WFC propagates adjacency constraints from a small exemplar tileset. It excels when local rules produce global coherence.

**When to use**: Tile-based maps where adjacency matters (towns, interiors, road networks).

**When NOT to use**: Continuous terrain, platformer levels with physics constraints, anything needing guaranteed long-range connectivity.

**Practical tips**:
- Extract adjacency rules automatically by scanning an exemplar image tile-by-tile
- Add symmetry variants (rotate/reflect) to reduce tileset authoring
- Weighted collapse biases output toward common tiles — use tile frequency from exemplar
- On contradiction: restart with different seed is simpler and often faster than backtracking
- For large maps: generate in overlapping chunks, fix border tiles before generating next chunk

#### Cellular Automata

Iterative local rules that produce emergent global structure. The classic choice for organic cave systems.

**Tuning parameters:**

| Parameter | Range | Effect |
|---|---|---|
| `fill_chance` | 0.40–0.55 | Higher = more walls, smaller caves |
| `iterations` | 3–6 | More = smoother, fewer small features |
| `neighbor threshold` | 4–5 | 5 = more open; 4 = more walls |
| `border forced wall` | on/off | On = contained; off = caves can touch edges |

**Variants**: Multiple passes with different rules, directional bias for elongated caves, multi-layer for ground/ceiling/decoration.

#### L-Systems

String-rewriting systems for branching, self-similar structures. Best for vegetation, river networks, branching path layouts.

**When NOT to use**: Grid-based rooms, anything needing precise tile alignment.

#### Grammar-Based / Rule Systems

Production rules that operate on higher-level structures (rooms, corridors, encounters). Best for platformer level rhythm.

#### Noise-Based Generation

Use layered noise for continuous terrain, height maps, and natural-looking distributions.

See [references/algorithm-implementations.md](references/algorithm-implementations.md) for WFC pseudocode, cellular automata cave generator, L-system grammar, grammar-based level rules, and multi-octave noise.

---

## Platformer-Specific Generation

Platformer PCG is harder than dungeon PCG because every generated segment must be physically traversable.

### Jumpability Constraints

Define the player's physical capabilities as hard constraints before generating anything.

**Hard rules for platform placement:**

| Constraint | Rule | Why |
|---|---|---|
| Horizontal gap | `gap_width <= max_gap_clearable` | Player must be able to cross |
| Vertical reach | `platform_height_diff <= max_jump_height` | Player must be able to reach |
| Landing width | `platform_width >= 2 * tile_size` | Minimum viable landing zone |
| Fall distance | `fall_height <= max_fall_survivable` or has catch platform | No inescapable death pits |
| Backtrack | At least one path back to start per section | No softlocks |
| Running start | Gaps near max range need `>= 3 tiles` run-up | Full-speed jumps need acceleration space |

### Rhythm-Based Generation

Model platformer levels as rhythmic sequences of actions.

**Rhythm patterns that work:**
- **Call and response**: Introduce a mechanic simply, then challenge with it
- **Escalate-then-rest**: 3 increasingly hard challenges, then a safe zone with a reward
- **Introduce, repeat, combine**: Wall jump alone, then dash alone, then wall-jump-into-dash
- **Parallel paths**: Easy low road vs hard high road with better rewards

### Difficulty Curves

| Curve Type | Behavior | Best For |
|---|---|---|
| Linear | Steady ramp | Generic levels |
| Logarithmic | Fast initial ramp, gentle later | Tutorials |
| Sawtooth | Periodic peaks and valleys | Long levels |
| S-curve | Gentle start, steep middle, gentle end | Story levels |

**Difficulty factors to vary:**

| Factor | Easy | Medium | Hard |
|---|---|---|---|
| Gap width | 50-70% of max | 70-85% | 85-95% |
| Platform size | 4+ tiles | 2-3 tiles | 1-2 tiles |
| Enemy density | 1 per 3 sections | 1 per section | 2+ per section |
| Hazard coverage | 10% of floor | 25% | 40%+ |
| Safe zones | Every 3 challenges | Every 5 | Every 8 |
| Time pressure | None | Soft (score) | Hard (rising lava) |

See [references/algorithm-implementations.md](references/algorithm-implementations.md) for jumpability calculation, rhythm section generator, difficulty curve functions, and platform placement with validation.

---

## Terrain Generation for Sidescrollers

Layer multiple noise octaves for terrain with large-scale features and small-scale detail. Use a separate noise function for biome assignment and blend at boundaries.

**Biome parameters:**

| Biome | Amplitude | Frequency | Fill Tile | Decoration |
|---|---|---|---|---|
| Desert | Low | Low | Sand | Cacti, bones |
| Plains | Medium | Medium | Grass | Flowers, bushes |
| Forest | Medium | Medium-High | Dirt/moss | Trees, mushrooms |
| Mountains | High | High | Stone | Snow caps, crystals |
| Swamp | Low | High | Mud | Lily pads, fog |

**Cave tuning:**

| Parameter | Small Caves | Medium Networks | Large Caverns |
|---|---|---|---|
| `cave_frequency` | 0.08 | 0.05 | 0.03 |
| `cave_threshold` | 0.45 | 0.35 | 0.25 |
| Smoothing passes | 3 | 2 | 1 |
| Min depth below surface | 8 tiles | 5 tiles | 10 tiles |

See [references/algorithm-implementations.md](references/algorithm-implementations.md) for terrain column generation, biome blending, vertical layering with ores, and noise-based cave generation.

---

## Loot and Drop Tables

### Rarity Tiers

| Tier | Base Weight | Color Convention | Typical Drop Rate |
|---|---|---|---|
| Common | 100 | White/Gray | ~60% |
| Uncommon | 30 | Green | ~25% |
| Rare | 8 | Blue | ~10% |
| Epic | 2 | Purple | ~4% |
| Legendary | 0.5 | Orange/Gold | ~1% |

### Pity Timers

Guarantee that players eventually get rare drops. Pity config: legendary = 90 rolls, epic = 30, rare = 10.

**Soft pity** (increasing chance via weight multiplier) vs **hard pity** (guaranteed at threshold). Use soft pity from 70% of threshold to guarantee, hard pity at threshold.

### Contextual Drops

Modify loot tables based on: enemy type bonuses, biome bonuses, player level (suppress outdated loot at level_diff > 10), and luck stat multiplier.

See [references/algorithm-implementations.md](references/algorithm-implementations.md) for weighted random selection, pity timer implementation, contextual drop modifier, and seed-based deterministic rolls.

---

## Multiplayer PCG

Multiplayer adds hard requirements: all clients must see the same generated world, generation must be fast enough for real-time play.

### Rules for Deterministic Multiplayer PCG

1. Server generates and distributes the master seed
2. Derive sub-seeds deterministically (hash master + purpose string)
3. Never use `randf()` / `randi()` for world generation — always use a seeded RNG instance
4. Each system gets its own RNG to avoid call-order dependencies
5. Generation order must be deterministic (sort by chunk coord, not by request arrival)

### Server-Authoritative Generation Patterns

| Pattern | Latency | Bandwidth | Cheat Resistance | Best For |
|---|---|---|---|---|
| Server generates all | High | High | Perfect | Competitive, small worlds |
| Shared seed + validation | Low | Low | Good | Co-op, large worlds |
| Shared seed, no validation | Lowest | Lowest | None | Trusted / casual |

### Cross-Client Consistency

| Desync Source | Cause | Prevention |
|---|---|---|
| Float precision | Different CPUs round differently | Use fixed-point or integer math for generation |
| RNG call order | Different update order across clients | Dedicated RNG per system, deterministic iteration order |
| Async loading | Chunks load in different order | Sort generation queue by coord, not by request time |
| Time-based seeds | Clients have different clocks | Server distributes all seeds, never use local time |
| Platform differences | Different noise implementations | Ship your own noise function, don't rely on engine |

See [references/algorithm-implementations.md](references/algorithm-implementations.md) for seed sync, server-authoritative generation, and chunk streaming implementations.

---

## Content Blending: Hand-Crafted + Procedural

### Blending Strategies

| Strategy | Description | Best For |
|---|---|---|
| Anchor + infill | Fixed set pieces, procedural between them | Story-driven games |
| Template variation | Authored layouts with randomized contents | Roguelites |
| Macro authored / micro procedural | Hand-drawn world map, generated interiors | Open-world 2D |
| Procedural with authored overrides | Generate everything, designer marks spots for hand-tuning | Early prototyping |
| Layer blending | Hand-authored foreground, procedural background | Visual variety |

See [references/algorithm-implementations.md](references/algorithm-implementations.md) for anchor + infill generation and template instantiation code.

---

## Testing Procedural Content

PCG bugs are statistical — they may only appear in 1 out of 1000 seeds. Testing requires both automated verification and visual inspection.

### Automated Tests to Run

1. **Path exists** from start to end (pathfinding)
2. **All platforms reachable** from start (flood fill)
3. **No softlocks** — path from every checkpoint to end
4. **Difficulty within bounds** — measured difficulty vs constraints
5. **No degenerate geometry** — empty ratio between 10% and 95%
6. **Distribution validation** — loot tier rates within 2% of expected
7. **Pity guarantee** — max streak without legendary <= guarantee_at

### Visual Inspection Tools to Build

1. **Seed gallery**: Render 20-50 seeds as thumbnails in a grid — scan for outliers
2. **Heat maps**: Color tiles by difficulty, enemy density, or loot probability
3. **Path overlay**: Draw the critical path over generated levels
4. **Animation mode**: Watch generation happen step-by-step
5. **Seed replay**: Enter a specific seed to reproduce a reported bad generation

See [references/algorithm-implementations.md](references/algorithm-implementations.md) for playability verification and distribution validation test code.

---

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Global RNG for everything** | Generation order changes = different world | One seeded RNG per system |
| **Generate-then-validate** | Discard and retry wastes time, may loop forever | Constrain during generation, not after |
| **No connectivity guarantee** | Islands, unreachable areas, softlocks | Flood-fill check post-generation, tunnel to connect |
| **Uniform random placement** | Clumpy, unnatural, boring | Poisson disk sampling, minimum distance constraints |
| **Difficulty spikes from RNG** | 3 hard sections in a row by chance | Difficulty envelope with local variance caps |
| **Determinism assumption without tests** | "Same seed = same world" until it doesn't | Automated hash comparison across runs and platforms |
| **Noise for everything** | Square peg, round hole | Match algorithm to content type (see decision table) |
| **No seed logging** | Player reports bad level, can't reproduce | Log seed in save file, crash reports, screenshots |
| **Over-tuned exemplars for WFC** | Tiny exemplar = repetitive; large = slow + contradictions | 16x16 to 32x32 exemplars with clear tile patterns |
| **Loot without pity** | 0.5% legendary means some players never see one | Pity timer or increasing probability (soft pity) |
| **Mixing authored + procedural without seams** | Visible boundary at junction | Constrain procedural output to match anchor entry/exit shapes |

---

## Cross-References

- **gamedev-2d-platformer**: Movement physics, jump parameters, CharacterBody2D — use these to derive jumpability constraints for PCG
- **gamedev-level-design**: Level design principles, pacing, flow theory — procedural generators should produce levels that follow these principles
