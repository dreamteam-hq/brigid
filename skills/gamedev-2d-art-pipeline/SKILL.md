---
name: gamedev-2d-art-pipeline
description: "2D asset pipeline for Godot — pixel art, sprite sheets, tilesets, parallax, lighting, particles, Blender+Godot MCP workflows" Triggers: pixel art, sprite sheet, tileset, parallax, 2D lighting, particle effects, 2D art pipeline, normal maps 2D, GPUParticles2D, asset pipeline godot.
---

# 2D Art Pipeline (Godot 4)

## Pixel Art Workflow

### Aseprite / LibreSprite Export

Aseprite is the standard for pixel art. LibreSprite is the free fork. Both produce identical output formats.

**Recommended export settings:**

| Setting | Value | Why |
|---------|-------|-----|
| Format | PNG | Lossless, alpha support, universally supported |
| Sheet type | By Rows | Predictable frame layout for SpriteFrames import |
| Border padding | 0–1 px | Prevents bleeding at edges; 1px for atlas packing |
| Inner padding | 0 px | Avoids gaps in tightly-packed animations |
| Trim | Off | Keep consistent frame sizes for uniform SpriteFrames |
| JSON data | Enabled | Frame metadata for automated import scripts |

**Export command (Aseprite CLI):**

```bash
aseprite -b player_run.aseprite --sheet player_run.png --sheet-type rows --data player_run.json --format json-array
```

**Naming convention:**

```
res://assets/sprites/<character>/<action>.png
res://assets/sprites/<character>/<action>.json
```

### Palette Management

Lock palettes early — changing palettes mid-project causes cascading rework.

**Workflow:**
1. Define a master palette (16–32 colors retro, 48–64 modern pixel art)
2. Save as `.pal` or `.gpl` in `res://assets/palettes/`
3. Load in Aseprite: Sprite → Color Mode → Indexed, assign palette
4. All artists share the same palette file — enforce via version control

**Color ramp structure:**

| Ramp | Colors | Purpose |
|------|--------|---------|
| Skin tones | 3–4 | Base, shadow, highlight, subsurface |
| Environment greens | 4–5 | Dark foliage to bright grass |
| Stone/ground | 3–4 | Dark to light earth tones |
| Sky gradient | 3–4 | Horizon to zenith |
| Accent/magic | 2–3 | Effects, UI highlights |
| Outline | 1–2 | Black or dark color for outlines |

For runtime palette swaps via shader, see [references/gdscript-implementations.md](references/gdscript-implementations.md).

### Integer Scaling and Viewport Stretch

Pixel art must render at exact integer multiples of the native resolution. Non-integer scaling produces uneven pixel sizes that destroy the art style.

**Project Settings:**

| Setting | Path | Value |
|---------|------|-------|
| Base resolution | `display/window/size/viewport_width/height` | Native pixel art resolution |
| Window override | `display/window/size/window_width/height_override` | Integer multiple of base |
| Stretch mode | `display/window/stretch/mode` | `viewport` |
| Stretch aspect | `display/window/stretch/aspect` | `keep` |
| Default filter | `rendering/textures/canvas_textures/default_texture_filter` | `Nearest` |

**Common native resolutions:**

| Resolution | Aspect | Scale to 1080p | Best for |
|------------|--------|---------------|----------|
| 320x180 | 16:9 | 6x | Small sprites (8–16px characters) |
| 384x216 | 16:9 | 5x | Medium sprites (16–24px) |
| 480x270 | 16:9 | 4x | Larger sprites (24–32px) |
| 640x360 | 16:9 | 3x | Detailed sprites (32–48px) |

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for the integer scaling enforcer script.

## Sprite Sheet Conventions

### Frame Layout

One animation per row. Each frame occupies the same cell size.

```
Row 0: idle       [frame0][frame1][frame2][frame3]
Row 1: run        [frame0][frame1][frame2][frame3][frame4][frame5]
Row 2: jump_up    [frame0][frame1][frame2]
Row 3: jump_fall  [frame0][frame1]
Row 4: attack     [frame0][frame1][frame2][frame3][frame4]
```

**Cell size rules:**
- All cells in a sheet share the same width and height
- Size to the largest frame (pad smaller frames with transparency)
- Common sizes: 16x16, 24x24, 32x32, 48x48, 64x64
- Power-of-two texture dimensions preferred (256x256, 512x512, 1024x1024)

**Naming convention:**
```
<entity>_<animation>_<variant>.png
# Examples: player_idle_default.png, enemy_slime_bounce.png
```

### SpriteFrames Setup

**Manual setup in editor:**
1. Create `AnimatedSprite2D` node
2. In Inspector, create New SpriteFrames resource
3. For each animation: Add Frames from Sprite Sheet
4. Set grid size matching your cell dimensions; set FPS per animation (8–12 for pixel art)
5. Save SpriteFrames as `.tres` for reuse

For automated SpriteFrames from Aseprite JSON metadata, see [references/gdscript-implementations.md](references/gdscript-implementations.md).

## Tileset Creation

### Godot TileSet Editor Workflow

1. Create `TileMapLayer` node (Godot 4.3+ replaces `TileMap` layers)
2. In Inspector, create New TileSet resource
3. Add tile source: Atlas (sprite sheets) or Scene (complex tiles)
4. Set tile size (match your pixel grid: 16x16, 32x32, etc.)
5. Configure physics, navigation, and custom data layers as needed

**TileSet layer types:**

| Layer Type | Purpose | Example |
|------------|---------|---------|
| Physics | Collision shapes | Ground, walls, one-way platforms |
| Navigation | Pathfinding mesh | Walkable surfaces for AI |
| Custom Data | Arbitrary per-tile data | Damage type, friction, material |
| Occlusion | Light blocking | Shadow-casting walls |

### Terrain Auto-Tile

| Terrain Mode | Bits | Best For |
|-------------|------|----------|
| Match Corners and Sides | 8 neighbors | Full terrain blending |
| Match Corners | 4 corners | Simpler tilesets, decorative overlays |
| Match Sides | 4 sides | Walls, paths, rivers |

A complete terrain set with corners+sides needs **47 unique tiles** (blob tileset). A **16-tile** subset (sides only) covers most cases.

**Terrain setup steps:**
1. In TileSet, add Terrain Set (type: Match Corners and Sides)
2. Name the terrain and assign a debug color
3. Paint terrain bits on each tile (the 3x3 grid overlay)
4. Center bit = "this tile IS this terrain"; edge/corner bits = "adjacent tile is also this terrain"

For the decorative tile scatter script, see [references/gdscript-implementations.md](references/gdscript-implementations.md).

## Parallax Backgrounds

### Layer Architecture

```
ParallaxBackground
├── ParallaxLayer (sky)           # scroll_scale = (0.0, 0.0)
├── ParallaxLayer (far_clouds)    # scroll_scale = (0.1, 0.05)
├── ParallaxLayer (mountains)     # scroll_scale = (0.2, 0.1)
├── ParallaxLayer (far_trees)     # scroll_scale = (0.4, 0.2)
└── ParallaxLayer (near_trees)    # scroll_scale = (0.7, 0.4)
TileMapLayer (gameplay)           # scroll_scale = (1.0, 1.0) implied
```

### Scroll Speed Ratios

| Layer | scroll_scale.x | scroll_scale.y |
|-------|----------------|----------------|
| Sky/gradient | 0.0 | 0.0 |
| Distant clouds | 0.05–0.1 | 0.0–0.05 |
| Mountains/horizon | 0.15–0.25 | 0.05–0.15 |
| Mid-ground foliage | 0.3–0.5 | 0.15–0.3 |
| Near foliage/props | 0.6–0.8 | 0.3–0.5 |
| Foreground overlay | 1.2–1.5 | 0.0 |

Each layer's x-scale should be roughly 50–70% of the next-closer layer.

**Seamless repeat:** Set `motion_mirroring.x` = texture width (exactly). Texture must be seamless.

## 2D Lighting

### Light2D Types

| Node | Mode | Best For |
|------|------|----------|
| `PointLight2D` | Radial / textured | Torches, campfires, character glow |
| `DirectionalLight2D` | Global direction | Sunlight, moonlight |

**PointLight2D key properties:**

| Property | Typical Value | Notes |
|----------|--------------|-------|
| `texture` | Soft radial gradient | 128x128 or 256x256 white gradient |
| `color` | `Color(1.0, 0.85, 0.6)` | Warm torch color |
| `energy` | 0.5–2.0 | Intensity multiplier |
| `texture_scale` | 1.0–4.0 | Radius of effect |
| `blend_mode` | Add | Additive blending for standard lights |
| `shadow_enabled` | true/false | Enable for dynamic shadows (expensive) |

**CanvasModulate** dims the entire canvas — pair with Light2D for torchlight/horror atmospheres. Without CanvasModulate, lights only add brightness to an already fully-lit scene.

### Normal Maps for 2D Sprites

Normal maps add illusion of 3D depth under dynamic lighting. RGB encodes surface direction.

**Creating normal maps:**
1. **Manual in Aseprite/GIMP**: Paint RGB image — R=left/right, G=up/down, B=depth. Neutral flat pixel = `(128, 128, 255)`.
2. **Automated with Laigter**: Free tool for auto-generating from 2D sprites.
3. **Baked from Blender**: See [references/blender-mcp-workflows.md](references/blender-mcp-workflows.md).

For normal map shader and CanvasTexture setup, see [references/gdscript-implementations.md](references/gdscript-implementations.md).

### LightOccluder2D

| Occluder Shape | Vertices | When to Use |
|---------------|----------|-------------|
| Simple rectangle | 4 | Walls, crates, doors |
| Convex hull | 6–8 | Trees, characters (approximate) |
| Detailed polygon | 10–20 | Only for critical foreground objects |
| Per-tile occluder | 4 | TileSet occlusion layer (automatic) |

Shadow rendering cost scales with **occluder edges × number of lights**. Keep vertex count low.

For the day/night cycle script, see [references/gdscript-implementations.md](references/gdscript-implementations.md).

## 2D Particle Effects

### GPUParticles2D vs CPUParticles2D

| Factor | GPUParticles2D | CPUParticles2D |
|--------|---------------|----------------|
| Particle count | 100–10,000+ | 10–500 |
| Performance | GPU-accelerated | CPU-bound |
| Custom shaders | Yes | No |
| Platform support | Requires Vulkan/OpenGL 3.3+ | Works everywhere |
| Best for | Weather, magic, fire, explosions | Dust puffs, small sparks, deterministic playback |

Use `GPUParticles2D` for visual effects. Use `CPUParticles2D` only when you need deterministic playback or target the compatibility renderer.

### Performance Budgets

| Platform | Max Active Systems | Max Total Particles |
|----------|-------------------|---------------------|
| Desktop (Vulkan) | 15–20 | 5,000–10,000 |
| Desktop (Compatibility) | 8–12 | 1,000–3,000 |
| Mobile (high-end) | 5–8 | 500–1,500 |
| Mobile (low-end) | 2–4 | 200–500 |

**Key optimizations:** Pool particle systems (hide/show + `restart()` instead of creating/destroying). Reduce `amount` before reducing visual quality. Skip particles far off-screen.

For particle recipes (dust puff, sparks, trail, rain), see [references/gdscript-implementations.md](references/gdscript-implementations.md).

## Screen Effects

For all shader implementations (fade, dissolve, CRT, chromatic aberration, screen shake, shockwave), see [references/gdscript-implementations.md](references/gdscript-implementations.md).

**Post-processing scene setup:**
```
CanvasLayer (layer = 100)
└── ColorRect (full viewport)
    └── ShaderMaterial
```

## Blender MCP Integration

Use the Blender MCP server for 3D-to-2D workflows:
- Pre-rendered sprites from 3D models (orthographic camera batch render)
- Normal map baking from 3D geometry
- Tile sheet generation from 3D tiles
- Multi-direction rendering (8-directional top-down sprites)

See [references/blender-mcp-workflows.md](references/blender-mcp-workflows.md) for all Blender Python scripts.

## Godot MCP Integration

Use the Godot MCP server to automate scene setup. Always call `editor_status` first to verify connection.

**Typical workflow:** `scene_create → scene_node_add → scene_node_set → scene_save`

Save ParticleProcessMaterial and TileSet resources in the editor first — MCP assigns pre-configured `.tres` resources rather than configuring complex properties via node-set calls.

For full Godot MCP property configs (SpriteFrames, TileSet, PointLight2D, GPUParticles2D, CanvasModulate), see [references/blender-mcp-workflows.md](references/blender-mcp-workflows.md).

## Anti-Patterns

| Anti-Pattern | Problem | Correct Approach |
|-------------|---------|-----------------|
| Non-integer viewport scaling | Uneven pixel sizes | Set viewport to native resolution, `viewport` stretch mode, integer-multiple window size |
| Filtering on pixel art | Blurry sprites | Set `default_texture_filter` to `Nearest` in Project Settings |
| Oversized sprite sheets | GPU memory waste | Keep individual sheets under 2048x2048; split by character/entity |
| Animated tiles everywhere | TileMap redraw spikes | Limit to water edges, torches; use static tiles + particle overlays for ambient motion |
| CanvasModulate without Light2D | Scene just goes dark | Always pair CanvasModulate with at least one Light2D |
| Shadows on every light | Performance × lights × occluder edges | Enable shadows on only 1–3 key lights per screen |
| GPUParticles2D for ≤5 particles | GPU dispatch overhead | Use CPUParticles2D for effects under ~20 particles |
| Re-creating particle nodes | Allocation costs | Pool nodes: hide/show + `restart()` |
| Parallax without mirroring | Visible seam at edges | Set `motion_mirroring` = texture dimensions on every repeating layer |
| Normal maps with wrong filter | Smeared lighting | Use `filter_nearest` on normal map textures |
| Hardcoded palette colors | Can't palette swap | Indexed color mode + shader palette swap |

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-blender` | Full Blender MCP workflow: AI mesh generation, PBR materials, glTF export |
| `gamedev-godot` | Godot MCP details, scene architecture, C# scripting, node hierarchy |
| `gamedev-2d-platformer` | Movement physics, character state machines, combat, camera, animation |
