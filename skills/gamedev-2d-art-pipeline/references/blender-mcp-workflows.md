# Blender MCP Workflows for 2D Art

## Overview

Use the Blender MCP server (`execute_blender_code` tool) for 3D-to-2D asset workflows: pre-rendered sprites from 3D models, normal map baking, and tile sheet generation.

**Workflow summary:**
1. Model/import 3D asset in Blender
2. Set up orthographic camera at desired angle
3. Configure render settings for pixel-perfect output
4. Batch render all frames
5. Composite into sprite sheet (ImageMagick)

## Orthographic Camera Setup

```python
import bpy
import math

cam = bpy.data.cameras["Camera"]
cam.type = 'ORTHO'
cam.ortho_scale = 2.0  # Adjust to frame your character

# 3/4 top-down view (common for 2D games)
camera_obj = bpy.data.objects["Camera"]
camera_obj.location = (3, -3, 4)
camera_obj.rotation_euler = (math.radians(55), 0, math.radians(45))

# Render settings for pixel art
scene = bpy.context.scene
scene.render.resolution_x = 64
scene.render.resolution_y = 64
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
```

## Batch Frame Render

```python
import bpy
import os

output_dir = "/tmp/sprite_render/"
os.makedirs(output_dir, exist_ok=True)

scene = bpy.context.scene
for frame in range(scene.frame_start, scene.frame_end + 1):
    scene.frame_set(frame)
    scene.render.filepath = os.path.join(output_dir, f"frame_{frame:04d}")
    bpy.ops.render.render(write_still=True)
```

## 8-Direction Render (Top-Down Games)

```python
import bpy, math, os

directions = {
    "S": 0, "SW": 45, "W": 90, "NW": 135,
    "N": 180, "NE": 225, "E": 270, "SE": 315
}
output_dir = "/tmp/sprite_render_8dir/"
os.makedirs(output_dir, exist_ok=True)
camera_obj = bpy.data.objects["Camera"]

for dir_name, angle_deg in directions.items():
    angle_rad = math.radians(angle_deg)
    camera_obj.location = (
        math.sin(angle_rad) * 5.0,
        -math.cos(angle_rad) * 5.0,
        4.0
    )
    direction = camera_obj.location.copy()
    direction.negate()
    camera_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()

    for frame in range(bpy.context.scene.frame_start, bpy.context.scene.frame_end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.scene.render.filepath = os.path.join(output_dir, f"{dir_name}_frame_{frame:04d}")
        bpy.ops.render.render(write_still=True)
```

Post-process with ImageMagick:
```bash
for dir in S SW W NW N NE E SE; do
    montage ${dir}_frame_*.png -tile x1 -geometry +0+0 -background none ${dir}_strip.png
done
montage *_strip.png -tile 1x -geometry +0+0 -background none character_sheet.png
```

## Normal Map Baking

```python
import bpy

mat = bpy.data.materials.new("NormalCapture")
mat.use_nodes = True
nodes = mat.node_tree.nodes
links = mat.node_tree.links
nodes.clear()

geom = nodes.new("ShaderNodeNewGeometry")
separate = nodes.new("ShaderNodeSeparateXYZ")
combine = nodes.new("ShaderNodeCombineXYZ")
emission = nodes.new("ShaderNodeEmission")
output = nodes.new("ShaderNodeOutputMaterial")

links.new(geom.outputs["Normal"], separate.inputs[0])

map_x = nodes.new("ShaderNodeMapRange")
map_y = nodes.new("ShaderNodeMapRange")
map_z = nodes.new("ShaderNodeMapRange")

for node in [map_x, map_y, map_z]:
    node.inputs["From Min"].default_value = -1.0
    node.inputs["From Max"].default_value = 1.0
    node.inputs["To Min"].default_value = 0.0
    node.inputs["To Max"].default_value = 1.0

links.new(separate.outputs["X"], map_x.inputs["Value"])
links.new(separate.outputs["Y"], map_y.inputs["Value"])
links.new(separate.outputs["Z"], map_z.inputs["Value"])
links.new(map_x.outputs["Result"], combine.inputs["X"])
links.new(map_y.outputs["Result"], combine.inputs["Y"])
links.new(map_z.outputs["Result"], combine.inputs["Z"])
links.new(combine.outputs[0], emission.inputs["Color"])
links.new(emission.outputs[0], output.inputs["Surface"])

for obj in bpy.data.objects:
    if obj.type == 'MESH':
        obj.data.materials.clear()
        obj.data.materials.append(mat)

bpy.context.scene.render.filepath = "/tmp/normal_map"
bpy.ops.render.render(write_still=True)
```

**Important:** Use identical camera position, angle, and ortho_scale for both diffuse and normal renders — otherwise the maps won't align pixel-for-pixel.

## Tile Sheet Generation from 3D

```python
import bpy, os

tile_objects = ["ground_center", "ground_edge_n", "ground_edge_e",
                "ground_corner_ne", "wall_straight", "wall_corner"]
tile_size = 32
output_dir = "/tmp/tile_render/"
os.makedirs(output_dir, exist_ok=True)

scene = bpy.context.scene
scene.render.resolution_x = tile_size
scene.render.resolution_y = tile_size
scene.render.film_transparent = True

cam = bpy.data.cameras["Camera"]
cam.type = 'ORTHO'
cam.ortho_scale = 1.0

camera_obj = bpy.data.objects["Camera"]
camera_obj.rotation_euler = (0, 0, 0)

for tile_name in tile_objects:
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            obj.hide_render = True
    bpy.data.objects[tile_name].hide_render = False

    tile_loc = bpy.data.objects[tile_name].location
    camera_obj.location = (tile_loc.x, tile_loc.y, 5.0)
    scene.render.filepath = os.path.join(output_dir, tile_name)
    bpy.ops.render.render(write_still=True)
```

## Godot MCP Node Setup for Art Assets

### SpriteFrames

```
scene_node_add: AnimatedSprite2D
scene_node_set:
  node_path: "Player/AnimatedSprite2D"
  properties:
    sprite_frames: "res://assets/sprites/player/player_frames.tres"
    animation: "idle"
    autoplay: "idle"
    texture_filter: 0  # TEXTURE_FILTER_NEAREST for pixel art
```

### TileSet

```
scene_node_set:
  node_path: "World/GroundLayer"
  properties:
    tile_set: "res://assets/tilesets/overworld.tres"
    rendering_quadrant_size: 16
    collision_enabled: true
```

### PointLight2D

```
scene_node_set:
  node_path: "Dungeon/Lights/TorchLight"
  properties:
    texture: "res://assets/lights/soft_radial.png"
    color: "#FFD699"
    energy: 1.2
    texture_scale: 3.0
    shadow_enabled: true
    shadow_color: "#00000080"
    blend_mode: 0  # BLEND_MODE_ADD
```

### GPUParticles2D

```
scene_node_set:
  node_path: "Effects/DustPuff"
  properties:
    amount: 8
    lifetime: 0.3
    one_shot: true
    explosiveness: 1.0
    process_material: "res://assets/particles/dust_puff_material.tres"
    texture_filter: 0
```
