---
name: procedural-generation-3d
description: Procedural generation for 3D games — terrain, level layout, loot tables, WFC in 3D, chunk streaming, biome systems, and multiplayer seed synchronization
---

# Procedural Content Generation for 3D Games

## Terrain Generation

Heightmap-based terrain using the Terrain3D plugin or custom ArrayMesh geometry. Godot's built-in FastNoiseLite provides the core noise functions: Perlin, Simplex, and Cellular. Layer multiple octaves at different frequencies and amplitudes to build detail — low-frequency octaves define mountains and valleys, high-frequency octaves add surface roughness. For realism, run erosion simulation passes over the heightmap: hydraulic erosion carves river channels, thermal erosion smooths steep slopes. Store the final heightmap as an Image resource for deterministic regeneration from seed.

## Level Layout

Room-and-corridor generation is the standard for dungeon-style levels. Place rooms randomly within bounds, reject overlaps, then connect via L-shaped or A* corridors. BSP (binary space partitioning) recursively subdivides a rectangular area into smaller cells, then places rooms inside each leaf node — guarantees full coverage with no overlap. For richer layouts, use prefab placement with constraint solving: define snapping rules, required connections, and forbidden adjacencies, then fill the space iteratively. Graph-based connectivity works well for Metroidvania gating — build an abstract graph of areas and lock/key dependencies first, then instantiate geometry to match.

## Wave Function Collapse 3D

WFC generates content by propagating adjacency constraints from a tileset. In 3D, each cell has six neighbors (+X, -X, +Y, -Y, +Z, -Z) instead of four, so the adjacency ruleset and propagation cost grow significantly. Define tiles as small 3D scenes with tagged sockets on each face. The algorithm picks the lowest-entropy cell, collapses it to one tile, then propagates constraints to neighbors until all cells resolve or a contradiction triggers backtracking. 3D WFC is compute-heavy — pre-generate chunks at load time or run generation on a background thread. Keep tilesets small and well-constrained to reduce backtracking.

## Loot Tables

Use weighted random selection: each item has a weight, and the probability is weight/total_weight. Organize items into rarity tiers (Common, Uncommon, Rare, Epic, Legendary) with configurable drop-rate percentages per tier. Implement a pity timer — track consecutive rolls without a rare drop and guarantee one after N attempts. This prevents frustrating dry streaks while preserving randomness.

Loot generation must be server-authoritative. The client never rolls loot — it sends a request, the server rolls using its RNG seeded from the world seed plus a context hash (e.g., chest ID, enemy ID), and broadcasts the result. This prevents client-side manipulation and enables deterministic replay for debugging.

## Chunk Streaming

Divide the world into fixed-size chunks (e.g., 64x64x64 units). Track the player's current chunk and maintain a load radius. When the player moves into a new chunk, enqueue neighboring chunks for generation/loading and mark distant chunks for unloading. Use Godot's `ResourceLoader.LoadThreadedRequest` pattern to generate or load chunk data on a background thread without blocking the main thread. Handle seamless transitions by generating overlap regions — each chunk generates a border strip matching its neighbor's edge so terrain and objects connect without visible seams.

## Biome System

Assign biomes using Voronoi diagrams (scatter seed points, each cell = one biome) or noise-threshold mapping (different noise value ranges map to different biomes). Each biome defines its own generation parameters: terrain shape (mountainous, flat, rolling), vegetation density and types, enemy spawn tables, and ambient properties. Handle biome boundaries with blending — in the transition zone, interpolate terrain height, texture weights, and object density between the two biomes. Keep biome definitions in Resource files so designers can tune parameters without code changes.

## Multiplayer Seed Sync

The server generates and owns the world seed. On client connect, the server sends the seed so clients can generate identical base terrain locally — this avoids streaming massive terrain data over the network. All clients must use the same noise functions and parameters to guarantee deterministic output from the same seed. Dynamic content (enemy spawns, loot drops, destructible state) is never generated client-side — the server generates it and replicates via RPCs or state sync. Never trust client-generated procedural content; validate or ignore it. For mid-session joins, send the seed plus a delta of any modifications (destroyed terrain, opened chests) so the late joiner reconstructs the correct world state.
