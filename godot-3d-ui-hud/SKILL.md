---
name: godot-3d-ui-hud
description: >
  Implement 3D HUD elements in Godot 4.6 C# — health bars above enemies, floating damage
  numbers, nameplates, and billboarded UI. Covers SubViewport+Sprite3D, Label3D, shader
  quads, and object pooling. Grounded in CrystalMagica's MVVM pattern (EnemyNode, RemoteCharacterVM).
  Triggers: health bar, damage numbers, nameplate, 3D UI, billboard, floating text, HUD 3D.
scope: parameterized
quality: draft
lifecycle:
  status: active
  created: 2026-04-05
---

# 3D UI & HUD Elements — Godot 4.6 C#

## Quick Reference — Approach Comparison

| Approach | Use Case | Cost | Flexibility | Occlusion |
|----------|----------|------|-------------|-----------|
| **SubViewport + Sprite3D** | Health bars, rich UI | High (1 viewport per instance) | Full Control node tree | Yes |
| **Label3D** | Damage numbers, nameplates | Low | Text only, BBCode-free | Yes |
| **MeshInstance3D + Shader** | Minimal health bars | Lowest | Single-color bar only | Yes |
| **Projected Control** | Screen-space HUD | Medium | Full Control node tree | No (always on top) |

### Decision Flow

1. Need rich 2D controls (ProgressBar, TextureRect) in world space? **SubViewport + Sprite3D**
2. Text only, no styling beyond color/outline? **Label3D**
3. Single-color bar, 100+ instances, perf-critical? **Shader quad**
4. Must never be occluded by geometry? **Projected Control** (screen-space overlay)

### Billboard Modes (BaseMaterial3D.BillboardMode / SpriteBase3D.Billboard)

| Mode | Value | Behavior |
|------|-------|----------|
| `BILLBOARD_DISABLED` | 0 | No rotation toward camera |
| `BILLBOARD_ENABLED` | 1 | Z axis always faces camera (full billboard) |
| `BILLBOARD_FIXED_Y` | 2 | X axis faces camera, Y stays world-up |
| `BILLBOARD_PARTICLES` | 3 | Particle flipbook — do not use for UI |

For a 2.5D side-scroller (CrystalMagica), `BILLBOARD_FIXED_Y` is correct — keeps UI upright while facing the camera.

---

## Health Bars — SubViewport + Sprite3D

### Scene Tree

<!-- [DT-INTERNAL]: Node names reference CrystalMagica's Enemy.tscn hierarchy. Substitute your character root. -->

```
Enemy (CharacterBody3D)           # root — EnemyNode.cs
  EnemyMesh (MeshInstance3D)
  EnemyCollision (CollisionShape3D)
  HealthBar (Sprite3D)             # billboard, displays SubViewport texture
    SubViewport                    # renders the 2D ProgressBar
      ProgressBar                  # standard Control node
```

### Sprite3D Configuration

| Property | Value | Why |
|----------|-------|-----|
| `Billboard` | `BillboardMode.FixedY` | Faces camera, stays upright |
| `PixelSize` | `0.01` | 1 pixel = 0.01 world units; tune to match art scale |
| `NoDepthTest` | `false` | Occluded by geometry in front |
| `FixedSize` | `false` | Scales with distance (set `true` for screen-constant size) |
| `Transparent` | `true` | Required for alpha blending |
| `RenderPriority` | `1` | Draw after opaque geometry |
| `Position` | `new Vector3(0, 1.5f, 0)` | Above the enemy mesh — adjust per character height |

### SubViewport Configuration

| Property | Value | Why |
|----------|-------|-----|
| `Size` | `new Vector2I(128, 16)` | Small — health bar is a thin rectangle |
| `TransparentBg` | `true` | Background must be transparent |
| `Disable3D` | `true` | Only rendering 2D controls |
| `GuiDisableInput` | `true` | Non-interactive |
| `RenderTargetUpdateMode` | `UpdateMode.WhenVisible` | Only render when Sprite3D is visible |

### ProgressBar Styling

```csharp
// In HealthBarNode.cs or inline in EnemyNode.Bind()
var bar = GetNode<ProgressBar>("HealthBar/SubViewport/ProgressBar");
bar.MinValue = 0;
bar.MaxValue = 100;
bar.Value = 100;
bar.ShowPercentage = false;
bar.Size = new Vector2(128, 16);  // match SubViewport size exactly
bar.Position = Vector2.Zero;

// Style overrides for the fill
var bgStyle = new StyleBoxFlat { BgColor = new Color(0.2f, 0.2f, 0.2f, 0.8f) };
var fillStyle = new StyleBoxFlat { BgColor = new Color(0.1f, 0.8f, 0.1f, 1.0f) };
bar.AddThemeStyleboxOverride("background", bgStyle);
bar.AddThemeStyleboxOverride("fill", fillStyle);
```

### Binding to RemoteCharacterVM (MVVM)

<!-- [DT-INTERNAL]: CrystalMagica uses System.Reactive observables on the VM. Adapt to your observable/event pattern. -->

CrystalMagica's `RemoteCharacterVM` exposes `IObservable<Vector2> Position` and `Subject<CharacterAction> Updates`. Health is not yet on the VM — it needs to be added:

```csharp
// RemoteCharacterVM — add Health observable
public class RemoteCharacterVM
{
    // ... existing properties ...
    public IObservable<float> Health { get; set; }

    public RemoteCharacterVM(CharacterData data)
    {
        // ... existing init ...
        Health = Updates
            .OfType<HealthUpdate>()
            .Select(x => x.CurrentHealth)
            .StartWith(data.MaxHealth);
    }
}
```

```csharp
// EnemyNode.cs — bind health bar in Bind()
public void Bind(RemoteCharacterVM viewModel)
{
    // ... existing mesh/position/action bindings ...

    var bar = GetNode<ProgressBar>("HealthBar/SubViewport/ProgressBar");

    _ = viewModel.Health.Subscribe(hp =>
    {
        bar.Value = hp;

        // Color shift: green > yellow > red
        var ratio = (float)(hp / bar.MaxValue);
        var fill = bar.GetThemeStylebox("fill") as StyleBoxFlat;
        if (fill is not null)
        {
            fill.BgColor = ratio > 0.5f
                ? Colors.Green.Lerp(Colors.Yellow, 1f - (ratio - 0.5f) * 2f)
                : Colors.Yellow.Lerp(Colors.Red, 1f - ratio * 2f);
        }
    });
}
```

### Visibility Control

```csharp
// Hide health bar when at full HP, show on damage
_ = viewModel.Health.Subscribe(hp =>
{
    var healthBar = GetNode<Sprite3D>("HealthBar");
    healthBar.Visible = hp < bar.MaxValue;
});
```

---

## Floating Damage Numbers — Label3D

Label3D is the right tool for damage numbers: lightweight, no SubViewport overhead, spawn-and-forget with a tween.

### Scene Tree (spawned dynamically)

```
DamageNumber (Label3D)    # spawned at hit position, tweened, freed
```

### Implementation

```csharp
public partial class DamageNumberSpawner : Node3D
{
    [Export] public float RiseDistance { get; set; } = 1.5f;
    [Export] public float Duration { get; set; } = 0.8f;
    [Export] public int FontSize { get; set; } = 48;
    [Export] public float PixelSize { get; set; } = 0.005f;

    public void Spawn(Vector3 worldPosition, int amount, DamageType type)
    {
        var label = new Label3D
        {
            Text = amount.ToString(),
            FontSize = FontSize,
            PixelSize = PixelSize,
            Billboard = BaseMaterial3D.BillboardMode.FixedY,
            NoDepthTest = true,   // always visible — damage feedback must not be hidden
            FixedSize = false,
            Modulate = ColorForType(type),
            OutlineSize = 8,
            OutlineModulate = Colors.Black,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Position = worldPosition,
        };

        AddChild(label);

        // Tween: rise + fade over Duration
        var tween = CreateTween();
        tween.SetParallel(true);
        tween.TweenProperty(label, "position:y",
            worldPosition.Y + RiseDistance, Duration)
            .SetEase(Tween.EaseType.Out)
            .SetTrans(Tween.TransitionType.Cubic);
        tween.TweenProperty(label, "modulate:a", 0f, Duration)
            .SetEase(Tween.EaseType.In)
            .SetTrans(Tween.TransitionType.Cubic);
        tween.SetParallel(false);
        tween.TweenCallback(Callable.From(label.QueueFree));
    }

    private static Color ColorForType(DamageType type) => type switch
    {
        DamageType.Normal => Colors.White,
        DamageType.Critical => Colors.Yellow,
        DamageType.Self => Colors.Red,
        DamageType.Heal => Colors.Green,
        _ => Colors.White,
    };
}

public enum DamageType { Normal, Critical, Self, Heal }
```

### Critical Hit Emphasis

```csharp
// In Spawn(), after creating the tween:
if (type == DamageType.Critical)
{
    label.FontSize = (int)(FontSize * 1.5f);
    // Punch scale effect
    tween.TweenProperty(label, "scale",
        new Vector3(1.3f, 1.3f, 1.3f), 0.1f);
    tween.TweenProperty(label, "scale",
        Vector3.One, 0.15f);
}
```

---

## Object Pooling — High-Frequency Spawns

Damage numbers can fire rapidly. Allocating/freeing Label3D nodes every hit causes GC pressure. Pool them.

```csharp
public partial class DamageNumberPool : Node3D
{
    [Export] public int PoolSize { get; set; } = 32;

    private readonly Queue<Label3D> _pool = new();

    public override void _Ready()
    {
        for (int i = 0; i < PoolSize; i++)
        {
            var label = CreateLabel();
            label.Visible = false;
            AddChild(label);
            _pool.Enqueue(label);
        }
    }

    public Label3D Acquire()
    {
        if (_pool.Count == 0)
        {
            // Pool exhausted — expand
            var fresh = CreateLabel();
            AddChild(fresh);
            return fresh;
        }

        var label = _pool.Dequeue();
        label.Visible = true;
        return label;
    }

    public void Release(Label3D label)
    {
        label.Visible = false;
        label.Modulate = Colors.White; // reset
        _pool.Enqueue(label);
    }

    private Label3D CreateLabel() => new()
    {
        FontSize = 48,
        PixelSize = 0.005f,
        Billboard = BaseMaterial3D.BillboardMode.FixedY,
        NoDepthTest = true,
        OutlineSize = 8,
        OutlineModulate = Colors.Black,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };
}
```

Usage with the pool replaces `new Label3D()` + `QueueFree()` with `Acquire()` + `Release()`:

```csharp
public void Spawn(Vector3 worldPosition, int amount, DamageType type)
{
    var label = _pool.Acquire();
    label.Text = amount.ToString();
    label.Modulate = ColorForType(type);
    label.Position = worldPosition;
    label.Visible = true;

    var tween = CreateTween();
    tween.SetParallel(true);
    tween.TweenProperty(label, "position:y",
        worldPosition.Y + RiseDistance, Duration)
        .SetEase(Tween.EaseType.Out)
        .SetTrans(Tween.TransitionType.Cubic);
    tween.TweenProperty(label, "modulate:a", 0f, Duration)
        .SetEase(Tween.EaseType.In)
        .SetTrans(Tween.TransitionType.Cubic);
    tween.SetParallel(false);
    tween.TweenCallback(Callable.From(() => _pool.Release(label)));
}
```

---

## Nameplates — Player Names Above Characters

Same infrastructure as health bars. Two approaches depending on complexity:

### Simple: Label3D Only

```csharp
// In RemotePlayerNode.Bind()
var nameplate = GetNode<Label3D>("Nameplate");
nameplate.Text = viewModel.DisplayName;
nameplate.Billboard = BaseMaterial3D.BillboardMode.FixedY;
nameplate.FontSize = 32;
nameplate.PixelSize = 0.005f;
nameplate.NoDepthTest = true;
nameplate.OutlineSize = 6;
nameplate.Position = new Vector3(0, 2.0f, 0); // above health bar
```

### Rich: SubViewport (name + guild + icon)

```
RemotePlayer (CharacterBody3D)
  Mesh (MeshInstance3D)
  HealthBar (Sprite3D)
    SubViewport
      VBoxContainer
        Label (player name)
        ProgressBar (health)
```

Combine nameplate + health bar into a single SubViewport to reduce viewport count.

---

## Performance Guidelines

| Concern | Threshold | Mitigation |
|---------|-----------|------------|
| SubViewport count | >20 active hurts low-end GPUs | Use Label3D or shader quads for distant/less-important NPCs |
| SubViewport size | Keep under 256x64 for health bars | Smaller = fewer pixels to render per frame |
| Update mode | `WhenVisible` minimum | Use `UpdateOnce` + manual trigger for static bars |
| Damage number spawn rate | >10/second sustained | Object pool (see above) |
| Label3D count | >50 simultaneous | Pool + reduce Duration to free faster |
| FixedSize labels | Screen-space overdraw | Cull by distance: hide labels beyond a threshold |

### LOD Strategy for Health Bars

```csharp
// In _Process() — distance-based LOD
var camPos = GetViewport().GetCamera3D().GlobalPosition;
var dist = GlobalPosition.DistanceTo(camPos);

var healthBar = GetNode<Sprite3D>("HealthBar");
if (dist > 30f)
{
    healthBar.Visible = false;  // too far — cull entirely
}
else if (dist > 15f)
{
    // Switch to simple Label3D showing "HP: 75%"
    healthBar.Visible = false;
    GetNode<Label3D>("HealthLabel").Visible = true;
}
else
{
    healthBar.Visible = true;
    GetNode<Label3D>("HealthLabel").Visible = false;
}
```

---

## .tscn Integration — Enemy Scene

The existing `Enemy.tscn` has this structure:

```
Enemy (CharacterBody3D) — EnemyNode.cs
  EnemyMesh (MeshInstance3D)
  EnemyCollission (CollisionShape3D)
```

To add a health bar, the scene grows to:

```
Enemy (CharacterBody3D) — EnemyNode.cs
  EnemyMesh (MeshInstance3D)
  EnemyCollission (CollisionShape3D)
  HealthBar (Sprite3D)              # NEW
    SubViewport                     # NEW
      ProgressBar                   # NEW
```

In `Enemy.tscn` format:

```
[node name="HealthBar" type="Sprite3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.5, 0)
billboard = 2
pixel_size = 0.01
transparent = true

[node name="SubViewport" type="SubViewport" parent="HealthBar"]
transparent_bg = true
disable_3d = true
gui_disable_input = true
size = Vector2i(128, 16)
render_target_update_mode = 2

[node name="ProgressBar" type="ProgressBar" parent="HealthBar/SubViewport"]
offset_right = 128.0
offset_bottom = 16.0
show_percentage = false
```

---

## Edge Cases

**SubViewport texture is blank**: The SubViewport must be a child of the Sprite3D (not a sibling). Godot auto-assigns the ViewportTexture when parented this way. If using MeshInstance3D instead, you must manually set `ViewportTexture` on the material's albedo.

**Health bar faces wrong direction**: Verify `billboard` is set to `2` (FixedY), not `0` (disabled). In a 2.5D side-scroller, `FixedY` is correct — full billboard (`1`) can cause the bar to tilt when the camera has pitch.

**Damage numbers overlap**: Add random horizontal jitter to spawn position: `worldPosition.X += (float)GD.RandRange(-0.3, 0.3)`.

**Transparency sorting artifacts**: Set `RenderPriority = 1` on the Sprite3D to draw after opaque geometry. If multiple transparent Sprite3Ds overlap, increase priority for elements that should render on top.

**SubViewport not updating**: Check `RenderTargetUpdateMode` is `WhenVisible` or `Always`, not `Disabled`. Also verify the Sprite3D itself is visible — `WhenVisible` respects the parent's visibility.

---

## Anti-Patterns

**One SubViewport per damage number**: SubViewports are expensive. Damage numbers are ephemeral text — use Label3D, not SubViewport + RichTextLabel. Reserve SubViewports for persistent, styled UI like health bars.

**Updating health bar every frame**: Only update the ProgressBar value when health actually changes. The Rx subscription in the binding pattern handles this naturally — it fires on change, not per-frame.

**Using BILLBOARD_ENABLED in a side-scroller**: Full billboard rotates on all axes. When the camera has any pitch (common in 2.5D), health bars tilt awkwardly. Use `BILLBOARD_FIXED_Y` to keep them upright.

**Skipping object pooling for damage numbers**: In an MMO with many enemies, a boss fight can generate dozens of damage numbers per second. Without pooling, each one allocates a new node and triggers GC on free. Pool early.

**Putting UI in _Process without distance check**: Rendering 50 SubViewport health bars for off-screen enemies wastes GPU. Cull by distance or use `WhenVisible` update mode (which respects frustum culling).
