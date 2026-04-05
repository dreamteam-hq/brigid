# Health Bar Shader — Shader Quad Approach

The health bar shader renders a single-color bar on a `QuadMesh` with per-instance health
via `instance uniform`. All enemies share one `ShaderMaterial` — only the health value
differs per instance.

## Scene Setup

Add a `MeshInstance3D` child to the enemy scene, positioned above the entity mesh:

- **Mesh**: `QuadMesh` — size `(0.8, 0.08)` (adjust to entity scale)
- **Position**: `Vector3(0, 1.2, 0)` above entity center
- **Material**: `ShaderMaterial` with the shader below (shared across all enemies)

## HealthBar3D.gdshader

```glsl
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 fill_color : source_color = vec4(0.2, 0.8, 0.2, 1.0);
uniform vec4 damage_color : source_color = vec4(0.8, 0.2, 0.2, 1.0);
uniform vec4 background_color : source_color = vec4(0.1, 0.1, 0.1, 0.6);
uniform float border_width : hint_range(0.0, 0.1) = 0.02;
instance uniform float health : hint_range(0.0, 1.0) = 1.0;

void vertex() {
    // Billboard: always face camera
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0],
        INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2],
        MODEL_MATRIX[3]
    );
}

void fragment() {
    // Border check
    bool in_border = UV.x < border_width || UV.x > (1.0 - border_width)
                  || UV.y < border_width || UV.y > (1.0 - border_width);

    if (in_border) {
        ALBEDO = vec3(0.0);
        ALPHA = 0.8;
    } else if (UV.x < health) {
        // Gradient from fill_color to damage_color as health drops
        vec4 bar = mix(damage_color, fill_color, health);
        ALBEDO = bar.rgb;
        ALPHA = bar.a;
    } else {
        ALBEDO = background_color.rgb;
        ALPHA = background_color.a;
    }
}
```

## Key Features

- **`instance uniform float health`** — each MeshInstance3D stores its own health value
  without requiring a unique material. Set via `SetInstanceShaderParameter("health", ratio)`
  in C#.
- **Billboard in vertex shader** — the quad always faces the camera regardless of entity
  rotation.
- **`render_mode unshaded`** — no lighting calculations, the bar looks the same in shadow
  or light.
- **`cull_disabled`** — visible from behind if the camera orbits past.

## Billboard Alternatives

All world-space UI must face the camera. There are three billboard strategies:

### Shader Billboard (Recommended for Shader Quads)

The `MODELVIEW_MATRIX` approach shown above. Works on any MeshInstance3D.

### SpriteBase3D.Billboard Property (For Sprite3D / Label3D)

```csharp
mySprite3D.Billboard = BaseMaterial3D.BillboardModeEnum.Enabled;
myLabel3D.Billboard = BaseMaterial3D.BillboardModeEnum.Enabled;
```

| Mode | Behavior |
|------|----------|
| `Disabled` | No billboarding — rotates with parent |
| `Enabled` | Faces camera on all axes |
| `FixedY` | Faces camera but stays upright (no tilt) |

For health bars and nameplates, use `Enabled`. For trees or grass cards, use `FixedY`.

### Material Billboard (For StandardMaterial3D)

```csharp
var material = new StandardMaterial3D();
material.BillboardMode = BaseMaterial3D.BillboardModeEnum.Enabled;
```

Least recommended — requires a unique material if other instances should not billboard.
