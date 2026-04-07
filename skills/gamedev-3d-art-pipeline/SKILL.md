---
name: gamedev-3d-art-pipeline
description: 3D asset pipeline for Godot 4.6 — Blender to Godot workflow, glTF import, PBR materials, LOD, mesh optimization, MeshInstance3D, and procedural mesh generation
triggers:
  - 3D art pipeline
  - glTF
  - PBR materials
  - LOD
  - mesh optimization
  - MeshInstance3D
  - Blender to Godot
  - asset import
  - procedural mesh
version: "1.0.0"
---

# 3D Art Pipeline — Godot 4.6

## Blender to Godot Pipeline

glTF 2.0 is the primary interchange format between Blender and Godot.

- Export as `.glb` (binary) for production builds — smaller files, faster loading.
- Export as `.gltf` (text + separate .bin) for debugging — human-readable JSON, diffable in version control.
- Blender's built-in glTF exporter preserves transforms, PBR materials, skeletal animations, shape keys, and custom properties.
- Apply all transforms in Blender before export (`Ctrl+A` > All Transforms) to avoid scale/rotation issues in Godot.
- Import in Godot via drag-drop into the FileSystem dock, or load at runtime with `ResourceLoader.Load<PackedScene>("res://models/asset.glb")`.
- Re-exported assets auto-reimport when Godot detects file changes.

## Import Settings

Configure in the Godot Import dock after selecting the asset in FileSystem.

- **Root Type** — set the root node type (Node3D, RigidBody3D, StaticBody3D, etc.).
- **Scale** — adjust if Blender and Godot unit scales differ (Blender default: 1 unit = 1m, matches Godot).
- **Mesh Compression** — enable to reduce VRAM usage at the cost of slight precision loss.
- **Generate Lightmap UV2** — required for baked lighting (LightmapGI). Adds a second UV channel.
- **Generate Tangents** — required for normal maps to work correctly. Enable when using PBR materials.
- **Generate LODs** — auto-generates mesh LOD levels on import (see LOD section).
- After changing any setting, click **Reimport** to apply.
- `.import` files are auto-generated metadata — commit them to version control but never edit manually.

## PBR Materials

Godot uses `StandardMaterial3D` for physically-based rendering.

- **Albedo** — base color via `AlbedoColor` or `AlbedoTexture`.
- **Metallic** — 0.0 (dielectric) to 1.0 (metal). Use `MetallicTexture` for per-pixel variation.
- **Roughness** — 0.0 (mirror) to 1.0 (diffuse). Use `RoughnessTexture` for detail.
- **Normal Map** — `NormalEnabled = true`, assign `NormalTexture`. Adds surface detail without geometry.
- **Emission** — `EmissionEnabled = true`, set `Emission` color and `EmissionTexture` for glow effects.
- **ORM Textures** — pack Occlusion (R), Roughness (G), Metallic (B) into one texture for fewer texture samples and better GPU cache performance.
- Override materials per-instance on MeshInstance3D: `meshInstance.SetSurfaceOverrideMaterial(surfaceIdx, material)`.
- Materials imported from glTF are auto-converted to StandardMaterial3D.

## MeshInstance3D

The primary node for displaying 3D geometry in the scene tree.

- `Mesh` property holds the mesh resource (geometry + surface definitions).
- Each surface maps to one material slot — multi-material meshes have multiple surfaces.
- Built-in primitive meshes for prototyping: `BoxMesh`, `SphereMesh`, `CapsuleMesh`, `CylinderMesh`, `PlaneMesh`.
- `ArrayMesh` for procedural/runtime-generated geometry (see Procedural Mesh section).
- Access AABB via `GetAabb()` for bounds queries and culling logic.
- Supports `CastShadow` modes: Off, On, DoubleSided, ShadowsOnly.

## LOD (Level of Detail)

Critical for MMO performance with many visible entities.

- Godot auto-generates LOD levels on import when **Generate LODs** is enabled. Configure the number of levels and reduction ratio in import settings.
- `MeshInstance3D.LodBias` — per-instance multiplier. Values < 1.0 use lower LODs sooner (better perf), > 1.0 keeps higher LODs longer (better quality).
- **VisibilityRange** — manual LOD switching based on camera distance:
  - `VisibilityRangeBegin` / `VisibilityRangeEnd` — distance thresholds.
  - `VisibilityRangeFadeMode` — `Disabled`, `Self`, or `Dependencies` for smooth transitions.
- Combine auto-LOD with VisibilityRange: high-detail mesh at close range, simplified mesh at mid range, billboard or hidden at far range.
- For MMO: aggressive LOD on other players, NPCs, and distant props. Keep hero character at high LOD.

## Procedural Mesh

Runtime mesh generation for terrain, VFX, and dynamic geometry.

- **ImmediateMesh** — draw-call-style API for debug visualization. Call `SurfaceBegin()`, add vertices, `SurfaceEnd()`. Rebuilt each frame, not for production geometry.
- **SurfaceTool** — higher-level builder. Generates normals, tangents, and indices automatically. Feed into `ArrayMesh` via `Commit()`.
- **ArrayMesh** — low-level: supply raw vertex arrays (positions, normals, UVs, indices) via `AddSurfaceFromArrays()`. Best performance for large procedural meshes.
- **MeshDataTool** — read/modify existing mesh data vertex-by-vertex. Use for mesh deformation, painting, or analysis. Slower than direct array manipulation.
- Typical workflow: `SurfaceTool` builds geometry, commits to `ArrayMesh`, assigned to `MeshInstance3D.Mesh`.
- For terrain: generate heightmap-based mesh, split into chunks, apply LOD per chunk.

## CrystalMagica: Current Asset State and Pipeline Roadmap

CrystalMagica is a **3D MMO platformer** (CharacterBody3D, Node3D, Vector3, 3D physics) with a sidescroller camera angle (2.5D gameplay). All engine APIs are 3D — MeshInstance3D and LOD3D apply directly.

**Current placeholder meshes** — art is not yet in the game. All characters and enemies are represented by built-in primitive meshes:

- Players: `CapsuleMesh` assigned to a `MeshInstance3D` child of `CharacterBody3D`
- Enemies: `SphereMesh` or `BoxMesh` depending on enemy type
- Level geometry: `BoxMesh` platforms and walls

This is intentional scaffolding. The primitive meshes allow the gameplay, physics, and networking systems to be fully developed before art is integrated.

**Future pipeline** — when art production begins, the flow will be:

1. Model in Blender → export `.glb`
2. Import into Godot, configure import settings (see Import Settings section)
3. Replace the placeholder `MeshInstance3D.Mesh` with the imported mesh resource
4. Apply LOD (see LOD section) — critical for MMO entity counts
5. Cross-reference `gamedev-blender` skill for Blender-specific export settings, armatures, and animation retargeting — do not duplicate that content here

## Sprite3D for 2.5D Aesthetics

If CrystalMagica adopts sprite art rendered in 3D space (common in 2.5D platformers like Dead Cells, Hollow Knight with 3D backgrounds), `Sprite3D` is the relevant node:

- `Sprite3D` renders a `Texture2D` as a billboard or fixed-orientation quad in 3D space
- **Billboard mode** (`Billboard = Enabled`): sprite always faces the camera — good for VFX, hit numbers, health bars
- **Fixed orientation** (`Billboard = Disabled`): sprite is placed at a fixed angle in 3D space — good for characters viewed from a consistent camera angle in a sidescroller
- `Sprite3D.PixelSize` converts pixel units to 3D world units — calibrate so sprite scale matches `CharacterBody3D` collision shape
- `AnimatedSprite3D` extends `Sprite3D` with `SpriteFrames` — frame-based animation without a full skeletal rig
- `Sprite3D` participates in 3D rendering (shadow casting, lighting, LOD) unlike a 2D `Sprite2D` overlay
- For characters: parent `Sprite3D` (or `AnimatedSprite3D`) under `CharacterBody3D`, replacing the placeholder `MeshInstance3D` when art is ready

## Blender to Godot — Cross-Reference

This skill covers Godot-side import, materials, and optimization. For Blender-side workflow (export settings, armature prep, UV unwrapping, normal baking), see the `gamedev-blender` skill. Do not duplicate that content here — load both skills when the full pipeline is in scope.

## Optimization

Techniques for maintaining framerate with large 3D scenes.

- **Mesh Merging** — combine static meshes that share materials via manual `ArrayMesh` merging or `RenderingServer` APIs. Reduces draw calls at the cost of per-object culling.
- **MultiMeshInstance3D** — GPU-instanced rendering for repeated objects (grass, rocks, debris, particles). Set transforms per instance. Orders of magnitude faster than individual MeshInstance3D nodes.
- **OccluderInstance3D** — define occluder shapes for occlusion culling. Objects behind occluders skip rendering. Use simple box/quad occluders on large walls and buildings.
- **GPU Instancing** — enable on ShaderMaterial for custom instanced rendering. Use instance uniforms for per-instance variation (color, scale, animation offset).
- **Visibility Culling** — the engine frustum-culls automatically. Assist it with `VisibleOnScreenNotifier3D` to also pause logic on off-screen entities.
- For MMO entity counts: MultiMeshInstance3D for cosmetic props, aggressive LOD for player characters, server-driven interest management to limit visible entity count.

## Anti-Patterns

- **Swapping to 2D nodes for characters**: do not replace `CharacterBody3D` + `MeshInstance3D` with `CharacterBody2D` + `Sprite2D` to achieve a sidescroller look. CrystalMagica runs a 3D physics simulation — mixing 2D nodes breaks collision, physics layers, and the networking model.
- **Editing `.import` files manually**: these are generated metadata. Any manual edits are overwritten on reimport. Change settings only via the Godot Import dock.
- **Forgetting to apply transforms in Blender**: unapplied scale/rotation on meshes causes mismatched transforms in Godot. Always `Ctrl+A` > All Transforms before glTF export.
- **Skipping LOD on MMO entities**: without LOD, per-frame GPU cost scales linearly with visible entity count. In an MMO with dozens of players and enemies on screen, this is a guaranteed performance cliff.
- **Using ImmediateMesh for production geometry**: `ImmediateMesh` rebuilds every frame and is intended for debug visualization only. Use `SurfaceTool` → `ArrayMesh` for any geometry that persists.
