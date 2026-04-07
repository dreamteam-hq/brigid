---
name: gamedev-blender
description: Blender 3D asset creation and Godot import pipeline. Covers Blender MCP server usage, AI mesh generation (Hyper3D Rodin, Hunyuan3D), asset marketplaces (PolyHaven, Sketchfab), PBR materials, UV mapping, and glTF export to Godot. Load for any 3D asset work.
triggers:
  - Blender
  - 3D asset
  - UV mapping
  - PBR material
  - glTF export
  - PolyHaven
  - Sketchfab
  - Hyper3D
  - mesh generation
  - Blender MCP
version: "1.0.0"
---

# Blender Asset Pipeline

## Blender MCP Server

The Blender MCP server is a **plugin running inside Blender**. It drives modeling, material setup, AI generation, and marketplace imports.

### Before any operation
- Check connection status with `get_scene_info`
- Use ToolSearch to discover available Blender MCP tools

### Core tools
- `execute_blender_code` — run arbitrary Blender Python for modeling, materials, transforms
- `get_scene_info` / `get_object_info` — inspect current state
- `get_viewport_screenshot` — visual verification after any change
- `set_texture` — apply textures to objects
- `import_generated_asset` / `import_generated_asset_hunyuan` — bring AI-generated models in

## AI Mesh Generation

### Hyper3D Rodin
- `generate_hyper3d_model_via_text` or `generate_hyper3d_model_via_images` → `get_hyper3d_status` / `poll_rodin_job_status` → `import_generated_asset`
- Best for: concept art to 3D, text-described objects

### Hunyuan3D
- `generate_hunyuan3d_model` → `get_hunyuan3d_status` / `poll_hunyuan_job_status` → `import_generated_asset_hunyuan`
- Best for: alternative generation when Rodin results aren't suitable

### Always review AI-generated assets
- Screenshot after import with `get_viewport_screenshot`
- Check topology, scale, material assignments before export

## Asset Marketplaces

### PolyHaven
- `get_polyhaven_status` → `get_polyhaven_categories` → `search_polyhaven_assets` → `download_polyhaven_asset`
- High-quality CC0 models, HDRIs, and textures

### Sketchfab
- `get_sketchfab_status` → `search_sketchfab_models` → `get_sketchfab_model_preview` → `download_sketchfab_model`
- Vast library, check licensing per model

## Asset Pipeline: Blender → Godot

### Export workflow
1. Apply all transforms (Ctrl+A → All Transforms)
2. Verify materials are PBR-compatible (Principled BSDF)
3. Check UV mapping — unwrap if needed
4. Export as **glTF 2.0** (.glb or .gltf) to Godot project assets directory
5. Import to Godot, verify materials and textures render correctly
6. Test in scene at correct scale

### Material considerations
- Use Principled BSDF node for Godot compatibility
- Bake procedural textures to images before export
- Pack textures into .glb for single-file distribution
- Check normal map format (OpenGL vs DirectX) matches Godot expectations

### Scale and orientation
- Blender: Z-up, meters by default
- Godot: Y-up — glTF handles the conversion
- Verify scale after import; adjust export scale if needed
