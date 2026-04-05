---
name: godot-3d-ui-hud
description: >
  3D HUD elements in Godot 4.6 C# — shader-quad health bars (default for enemies),
  SubViewport bars (player/boss only), floating damage numbers with Label3D + object pool,
  nameplates, billboard modes, and LOD strategy for MMO-scale entity counts.
  Grounded in CrystalMagica MVVM (EnemyNode, RemoteCharacterVM, IBindable).
  Triggers: health bar, damage numbers, nameplate, 3D UI, billboard, floating text,
  HUD 3D, shader quad, SubViewport, Label3D, enemy health, boss health.
scope: parameterized
quality: curated
lifecycle:
  status: active
  created: 2026-04-05
---

# 3D UI & HUD Elements — Godot 4.6 C#

## Approach Comparison

| Approach | Draw Cost | Flexibility | Max Instances | Default For |
|----------|-----------|-------------|---------------|-------------|
| **MeshInstance3D + shader quad** | Lowest — 1 draw call per bar, no render target | Single-color bar with gradient/segments via shader | 100+ | Enemy health bars |
| **SubViewport + Sprite3D** | High — 1 render pass per viewport | Full Control tree (ProgressBar, icons, text) | 1-2 | Player HUD, boss bars |
| **Label3D** | Low — SDF text rendering | Text + outline + color, no rich controls | 50+ | Damage numbers, nameplates |
| **Sprite3D (texture)** | Low — 1 draw call | Static or atlas-swapped images | 50+ | Status icons, simple indicators |

### Decision Flow

```
Is it an enemy health bar (potentially 20+ on screen)?
  YES → MeshInstance3D + shader quad (instance uniform per entity)
  NO  → Is it the local player HUD or a boss bar (max 1-2)?
    YES → SubViewport + Sprite3D (full Control node richness)
    NO  → Is it text (damage number, nameplate)?
      YES → Label3D + billboard + tween
      NO  → Sprite3D with texture atlas
```

### Why SubViewport is WRONG for Enemy Health Bars

Each SubViewport allocates its own render target and executes a separate 2D render pass.
With 20+ enemies visible, that means 20+ additional render passes per frame on top of the
main 3D pass. The GPU memory and draw-call overhead scales linearly with entity count.

In an MMO zone with 20-50 visible enemies, SubViewport health bars will:
- Spike VRAM usage (each viewport allocates a texture, typically 200x26+ pixels)
- Add 20-50 extra render passes per frame
- Create GC pressure from viewport texture updates
- Cause frame drops on mid-range hardware

**SubViewport is appropriate only when:**
- There are at most 1-2 instances (player HUD, single boss bar)
- You need full 2D Control node features (styled ProgressBar, icons, text labels)
- The visual complexity justifies the render cost

---

## MeshInstance3D + Shader Quad (Default for Enemies)

This is the recommended approach for any entity that can appear in quantity. A QuadMesh
with a spatial shader renders the health bar as a single draw call per entity. The shader
uses an `instance uniform` so all enemies share a single ShaderMaterial — only the health
value differs per instance.

### Scene Setup

Add a `MeshInstance3D` child to the enemy scene, positioned above the entity mesh:

```
Enemy (CharacterBody3D)
  ├── EnemyMesh (MeshInstance3D)
  ├── EnemyCollision (CollisionShape3D)
  └── HealthBar (MeshInstance3D)          ← QuadMesh + ShaderMaterial
```

Configure the HealthBar MeshInstance3D:
- **Mesh**: `QuadMesh` — size `(0.8, 0.08)` (adjust to entity scale)
- **Position**: `Vector3(0, 1.2, 0)` above entity center
- **Material**: `ShaderMaterial` with the health bar shader (shared across all enemies)

### Health Bar Shader

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

Key features:
- **`instance uniform float health`** — each MeshInstance3D stores its own health value without requiring a unique material. Set via `SetInstanceShaderParameter("health", ratio)` in C#.
- **Billboard in vertex shader** — the quad always faces the camera regardless of entity rotation.
- **`render_mode unshaded`** — no lighting calculations, the bar looks the same in shadow or light.
- **`cull_disabled`** — visible from behind if the camera orbits past.

### C# Integration with MVVM

In CrystalMagica, `EnemyNode` implements `IBindable` and receives a `RemoteCharacterVM`.
The health bar binds to a health observable on the ViewModel.

#### Step 1 — Add Health Observable to ViewModel

```csharp
// RemoteCharacterVM.cs
public IObservable<float> HealthRatio { get; set; }

public RemoteCharacterVM(CharacterData data)
{
    Id = data.Id;
    Color = data.Color.ToGodot();

    Position = Updates
        .Select(x => x.Position)
        .StartWith(data.Position);

    HealthRatio = Updates
        .Where(x => x is HealthUpdate)
        .Cast<HealthUpdate>()
        .Select(x => (float)x.CurrentHp / x.MaxHp)
        .StartWith(data.CurrentHp / (float)data.MaxHp);
}
```

#### Step 2 — Bind in EnemyNode

```csharp
// EnemyNode.cs
public partial class EnemyNode : PlayerNode, IBindable
{
    [Export] public MeshInstance3D Mesh { get; set; }
    [Export] public MeshInstance3D HealthBar { get; set; }

    public void Bind(RemoteCharacterVM viewModel)
    {
        var material = new StandardMaterial3D { AlbedoColor = viewModel.Color };
        Mesh.SetSurfaceOverrideMaterial(0, material);

        _ = viewModel.Position.Subscribe(x => Position = x.ToGodot3D());

        // Health bar binding — instance shader parameter
        _ = viewModel.HealthRatio.Subscribe(ratio =>
        {
            if (IsInstanceValid(this))
                HealthBar.SetInstanceShaderParameter("health", ratio);
        });

        _ = viewModel.Updates.Subscribe(x =>
        {
            if (x.Action is CharacterActions.Jump)
                Jump();
            else if (x.Action is CharacterActions.Stop)
                StopMoving();
            else if (x is MoveBegin moveBegin)
                MoveBegin(moveBegin);
        });
    }

    public void Bind(object viewModel)
    {
        if (viewModel is not RemoteCharacterVM typedVM)
            throw new InvalidOperationException(
                $"EnemyNode.Bind expected RemoteCharacterVM, got {viewModel?.GetType().Name}");
        Bind(typedVM);
    }
}
```

**`SetInstanceShaderParameter`** writes to the per-instance uniform buffer. It does not
allocate a new material — all enemies share the same ShaderMaterial. This is the key
performance advantage over creating unique materials per entity.

### Updated Enemy.tscn

```
[gd_scene format=3]

[ext_resource type="Script" path="res://Views/EnemyNode.cs" id="1"]
[ext_resource type="Shader" path="res://Shaders/HealthBar3D.gdshader" id="2"]

[sub_resource type="SphereMesh" id="SphereMesh_1"]
[sub_resource type="SphereShape3D" id="SphereShape3D_1"]
radius = 0.50563383

[sub_resource type="QuadMesh" id="QuadMesh_1"]
size = Vector2(0.8, 0.08)

[sub_resource type="ShaderMaterial" id="ShaderMaterial_1"]
shader = ExtResource("2")
shader_parameter/fill_color = Color(0.2, 0.8, 0.2, 1)
shader_parameter/damage_color = Color(0.8, 0.2, 0.2, 1)
shader_parameter/background_color = Color(0.1, 0.1, 0.1, 0.6)
shader_parameter/border_width = 0.02

[node name="Enemy" type="CharacterBody3D" node_paths=PackedStringArray("Mesh", "HealthBar")]
script = ExtResource("1")
Mesh = NodePath("EnemyMesh")
HealthBar = NodePath("HealthBar")

[node name="EnemyMesh" type="MeshInstance3D" parent="."]
mesh = SubResource("SphereMesh_1")

[node name="EnemyCollision" type="CollisionShape3D" parent="."]
shape = SubResource("SphereShape3D_1")

[node name="HealthBar" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.2, 0)
mesh = SubResource("QuadMesh_1")
surface_material_override/0 = SubResource("ShaderMaterial_1")
```

---

## SubViewport + Sprite3D (Player HUD / Boss Bars)

Reserve this approach for the local player's overhead bar or a single boss health bar
where rich 2D controls justify the render cost.

### Scene Setup

```
BossHealthBar (Sprite3D)
  └── SubViewport (size: 256x32, transparent_bg: true)
      └── ProgressBar (Control)
          ├── Fill (TextureProgressBar)
          └── Label (current / max HP text)
```

### C# Script

```csharp
public partial class BossHealthBar3D : Sprite3D
{
    [Export] public SubViewport Viewport { get; set; }
    [Export] public ProgressBar Bar { get; set; }
    [Export] public Label HpLabel { get; set; }

    public override void _Ready()
    {
        // Sprite3D renders the SubViewport texture
        Texture = Viewport.GetTexture();
        Billboard = BaseMaterial3D.BillboardModeEnum.Enabled;
    }

    public void BindHealth(IObservable<(int current, int max)> health)
    {
        _ = health.Subscribe(hp =>
        {
            if (!IsInstanceValid(this)) return;
            Bar.Value = hp.current;
            Bar.MaxValue = hp.max;
            HpLabel.Text = $"{hp.current} / {hp.max}";
        });
    }
}
```

### When SubViewport is Justified

- Boss encounter with a single target — styled bar with HP text, phase indicators, icons
- Local player HUD bar that needs TextureProgressBar styling
- Inspection window (hovering over NPC shows detailed stats)

**Never use SubViewport for the 20+ generic enemy health bars.**

---

## Floating Damage Numbers — Label3D + Object Pool

### Architecture

Damage numbers appear above enemies when damage is dealt, float upward, and fade out.
With many enemies taking AoE damage simultaneously, you can easily spawn 20+ numbers in
a single frame. Object pooling prevents allocation spikes.

### Label3D Configuration

Label3D renders SDF text in 3D space. Configure for damage numbers:

| Property | Value | Why |
|----------|-------|-----|
| `Billboard` | `BaseMaterial3D.BillboardModeEnum.Enabled` | Always faces camera |
| `FixedSize` | `true` | Constant screen size regardless of distance |
| `NoDepthTest` | `true` | Renders on top of geometry (visible through enemies) |
| `FontSize` | 32-48 | Readable at gameplay distance |
| `OutlineSize` | 4-6 | Legible against any background |
| `Modulate` | varies | White for normal, yellow for crit, red for self-damage |

### DamageNumberPool — Object Pool

```csharp
public partial class DamageNumberPool : Node3D
{
    [Export] public int PoolSize { get; set; } = 30;
    [Export] public float RiseDuration { get; set; } = 0.8f;
    [Export] public float RiseHeight { get; set; } = 1.5f;
    [Export] public float SpreadRadius { get; set; } = 0.3f;

    private readonly Queue<Label3D> _available = new();
    private static readonly Random Rng = new();

    public override void _Ready()
    {
        for (int i = 0; i < PoolSize; i++)
        {
            var label = CreateLabel();
            label.Visible = false;
            AddChild(label);
            _available.Enqueue(label);
        }
    }

    private static Label3D CreateLabel()
    {
        return new Label3D
        {
            Billboard = BaseMaterial3D.BillboardModeEnum.Enabled,
            FixedSize = true,
            NoDepthTest = true,
            FontSize = 36,
            OutlineSize = 5,
            PixelSize = 0.005f,
            Modulate = Colors.White,
        };
    }

    /// <summary>
    /// Spawn a damage number at <paramref name="worldPosition"/>.
    /// Safe to call rapidly — excess requests are silently dropped.
    /// </summary>
    public void Show(int damage, Vector3 worldPosition, bool isCrit = false)
    {
        if (_available.Count == 0)
            return; // Pool exhausted — skip rather than allocate

        var label = _available.Dequeue();
        label.Text = damage.ToString();
        label.Modulate = isCrit ? Colors.Yellow : Colors.White;
        label.GlobalPosition = worldPosition + RandomSpread();
        label.Visible = true;

        // Scale pop for crits
        float startScale = isCrit ? 2.0f : 1.0f;
        label.Scale = Vector3.One * startScale;

        AnimateAndReturn(label, startScale);
    }

    private void AnimateAndReturn(Label3D label, float startScale)
    {
        var tween = CreateTween();
        tween.SetParallel(true);

        // Rise
        tween.TweenProperty(label, "global_position:y",
            label.GlobalPosition.Y + RiseHeight, RiseDuration)
            .SetEase(Tween.EaseType.Out)
            .SetTrans(Tween.TransitionType.Cubic);

        // Fade out
        tween.TweenProperty(label, "modulate:a", 0.0f, RiseDuration)
            .SetEase(Tween.EaseType.In)
            .SetTrans(Tween.TransitionType.Quad);

        // Scale down (crits shrink from 2x to 1x quickly, then continue)
        if (startScale > 1.0f)
        {
            tween.TweenProperty(label, "scale", Vector3.One, 0.2f)
                .SetEase(Tween.EaseType.Out)
                .SetTrans(Tween.TransitionType.Back);
        }

        tween.SetParallel(false);

        // Return to pool after animation
        tween.TweenCallback(Callable.From(() =>
        {
            label.Visible = false;
            label.Modulate = new Color(label.Modulate, 1.0f); // Reset alpha
            _available.Enqueue(label);
        }));
    }

    private Vector3 RandomSpread()
    {
        float x = (float)(Rng.NextDouble() * 2 - 1) * SpreadRadius;
        float z = (float)(Rng.NextDouble() * 2 - 1) * SpreadRadius;
        return new Vector3(x, 0, z);
    }
}
```

### Integration with MVVM

The pool lives as a scene-level singleton. Enemies report damage through an observable,
and the main scene subscribes to spawn numbers.

```csharp
// In the scene coordinator (e.g., Main.cs or a ZoneNode)
[Export] public DamageNumberPool DamageNumbers { get; set; }

// When binding an enemy:
_ = viewModel.DamageEvents.Subscribe(dmg =>
{
    if (IsInstanceValid(this))
    {
        var pos = enemyNode.GlobalPosition + Vector3.Up * 1.5f;
        DamageNumbers.Show(dmg.Amount, pos, dmg.IsCrit);
    }
});
```

The ViewModel exposes damage as an event stream (not state):

```csharp
// RemoteCharacterVM.cs — damage is a fire-and-forget event
public Subject<DamageEvent> DamageEvents { get; } = new();

// Populated by the message processor:
target.Value.DamageEvents.OnNext(new DamageEvent(amount, isCrit));
```

### Pool Sizing

| Scenario | Pool Size | Reasoning |
|----------|-----------|-----------|
| Single-target combat | 10 | Rapid attacks on one enemy |
| AoE (10 enemies) | 30 | 10 enemies x ~3 overlapping numbers |
| Raid boss (20+ players) | 50 | Many simultaneous damage sources |

If the pool is exhausted, numbers are silently dropped. This is intentional — the player
will not notice a missing number in a high-volume AoE scenario, but an allocation spike
will cause a visible frame hitch.

---

## Billboard Modes

All world-space UI must face the camera. Godot offers three billboard strategies.

### Shader Billboard (Recommended for Shader Quads)

Set `MODELVIEW_MATRIX` in the vertex shader. This is already included in the health bar
shader above. It works on any MeshInstance3D.

```glsl
void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0],
        INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2],
        MODEL_MATRIX[3]
    );
}
```

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

---

## Performance Thresholds and LOD Strategy

### Budget

Target: 60 FPS on mid-range hardware. The 3D UI system should consume less than 10% of
frame budget (~1.6ms at 60 FPS).

| Entity Count | Shader Quads | SubViewports | Label3Ds |
|--------------|:------------:|:------------:|:--------:|
| 1-5 | Any approach fine | Any approach fine | Any approach fine |
| 6-20 | Recommended | Avoid (6-20 extra render passes) | Fine |
| 20-50 | Required | Never | Fine with LOD |
| 50-100 | Required + LOD | Never | LOD required |

### Distance-Based LOD

Reduce visual fidelity for entities far from the camera. Implement in `_Process` or via
a `VisibleOnScreenNotifier3D` callback.

```csharp
public partial class EnemyNode : PlayerNode, IBindable
{
    [Export] public MeshInstance3D HealthBar { get; set; }
    [Export] public float HideDistance { get; set; } = 30.0f;
    [Export] public float SimplifyDistance { get; set; } = 15.0f;

    private Camera3D _camera;

    public override void _Ready()
    {
        _camera = GetViewport().GetCamera3D();
    }

    public override void _Process(double delta)
    {
        if (_camera is null || !IsInstanceValid(HealthBar)) return;

        float distance = GlobalPosition.DistanceTo(_camera.GlobalPosition);

        if (distance > HideDistance)
        {
            HealthBar.Visible = false;
        }
        else
        {
            HealthBar.Visible = true;
            // Optional: scale bar smaller at distance
            float scale = distance > SimplifyDistance ? 0.6f : 1.0f;
            HealthBar.Scale = new Vector3(scale, scale, 1.0f);
        }
    }
}
```

### LOD Tiers

| Distance | Health Bar | Damage Numbers | Nameplate |
|----------|-----------|----------------|-----------|
| Near (0-15m) | Full size, border, gradient | All shown, crit effects | Full name + title |
| Mid (15-30m) | Reduced size, no border | Only crits shown | Name only |
| Far (30m+) | Hidden | Hidden | Hidden |

### Throttling Updates

For entities at mid distance, throttle health bar updates to reduce shader parameter
writes:

```csharp
// In ViewModel or binding layer — throttle distant updates
_ = viewModel.HealthRatio
    .Sample(TimeSpan.FromMilliseconds(100)) // Max 10 updates/sec for distant enemies
    .Subscribe(ratio =>
    {
        if (IsInstanceValid(this))
            HealthBar.SetInstanceShaderParameter("health", ratio);
    });
```

For near enemies, subscribe without throttling for immediate visual feedback.

---

## Nameplates — Label3D

Enemy or player nameplates use Label3D positioned above the health bar.

```csharp
public partial class Nameplate : Label3D
{
    public void Bind(RemoteCharacterVM viewModel)
    {
        Text = viewModel.Name;
        Billboard = BaseMaterial3D.BillboardModeEnum.Enabled;
        FixedSize = true;
        FontSize = 24;
        OutlineSize = 4;
        PixelSize = 0.005f;
        // Color by faction
        Modulate = viewModel.IsHostile ? Colors.Red : Colors.LightGreen;
    }
}
```

Position in scene tree:

```
Enemy (CharacterBody3D)
  ├── EnemyMesh
  ├── EnemyCollision
  ├── HealthBar (MeshInstance3D)       y = 1.2
  └── Nameplate (Label3D)             y = 1.4
```

---

## Anti-Patterns

### SubViewport per Enemy

```
BAD — 20 enemies = 20 extra render passes
```

```csharp
// WRONG: SubViewport for each generic enemy
public partial class EnemyHealthBar : Sprite3D
{
    [Export] public SubViewport Viewport { get; set; }
    // Every enemy instance gets its own viewport allocation
}
```

```csharp
// CORRECT: Shader quad with instance uniform
HealthBar.SetInstanceShaderParameter("health", ratio);
// All enemies share one ShaderMaterial — zero extra render passes
```

### Unique Material per Enemy

```csharp
// WRONG: Creates a new material for each enemy's health bar
var mat = (ShaderMaterial)HealthBar.MaterialOverride.Duplicate();
mat.SetShaderParameter("health", ratio);
HealthBar.MaterialOverride = mat;
```

```csharp
// CORRECT: Instance shader parameter — no material duplication
HealthBar.SetInstanceShaderParameter("health", ratio);
```

### Allocating Damage Numbers Every Hit

```csharp
// WRONG: Instantiate + QueueFree per hit — GC spikes under AoE
var label = new Label3D();
AddChild(label);
// ... animate ...
label.QueueFree();
```

```csharp
// CORRECT: Object pool — pre-allocate, reuse, never free
DamageNumbers.Show(damage, position, isCrit);
```

### Subscribing to Health in _Process

```csharp
// WRONG: New subscription every frame
public override void _Process(double delta)
{
    _ = viewModel.HealthRatio.Subscribe(r =>
        HealthBar.SetInstanceShaderParameter("health", r));
}
```

```csharp
// CORRECT: Subscribe once in Bind(), let Rx push updates
public void Bind(RemoteCharacterVM viewModel)
{
    _ = viewModel.HealthRatio.Subscribe(ratio =>
    {
        if (IsInstanceValid(this))
            HealthBar.SetInstanceShaderParameter("health", ratio);
    });
}
```

### Missing IsInstanceValid Guard

```csharp
// WRONG: Node may be freed before subscription fires
_ = viewModel.HealthRatio.Subscribe(r =>
    HealthBar.SetInstanceShaderParameter("health", r));

// CORRECT: Guard against freed node
_ = viewModel.HealthRatio.Subscribe(r =>
{
    if (IsInstanceValid(this))
        HealthBar.SetInstanceShaderParameter("health", r);
});
```

---

## Checklist — Adding Health Bars to a New Entity

1. Add `QuadMesh` MeshInstance3D child to entity scene, positioned above mesh
2. Create or reuse `HealthBar3D.gdshader` with instance uniform
3. Assign shared ShaderMaterial to the QuadMesh
4. Add `[Export] public MeshInstance3D HealthBar` to the entity's C# script
5. Add `HealthRatio` observable to the ViewModel (derive from health updates)
6. In `Bind()`, subscribe to `HealthRatio` and call `SetInstanceShaderParameter`
7. Add LOD visibility toggle in `_Process` based on camera distance
8. Test with 20+ entities on screen — verify no frame drops

## Checklist — Adding Damage Numbers

1. Create `DamageNumberPool` scene and add to zone/level scene
2. Size pool based on max expected simultaneous numbers (30 for typical AoE)
3. Add `DamageEvents` Subject to ViewModel
4. Subscribe to `DamageEvents` in the coordinator, call `DamageNumbers.Show()`
5. Test AoE scenario — verify pool exhaustion drops silently, no allocation spikes
