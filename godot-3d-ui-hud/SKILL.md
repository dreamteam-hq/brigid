---
name: godot-3d-ui-hud
description: >
  3D HUD elements in Godot 4.6 C# — shader-quad health bars (default for enemies),
  SubViewport bars (player/boss only), floating damage numbers with Label3D + object pool,
  nameplates, billboard modes, and LOD strategy for MMO-scale entity counts.
  Grounded in CrystalMagica MVVM (EnemyNode, RemoteCharacterVM, IBindable).
triggers:
  - health bar
  - damage numbers
  - nameplate
  - 3D UI
  - billboard
  - floating text
  - HUD 3D
  - shader quad
  - SubViewport
  - Label3D
  - enemy health
  - boss health
category: gamedev
version: "1.0.0"
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
  YES -> MeshInstance3D + shader quad (instance uniform per entity)
  NO  -> Is it the local player HUD or a boss bar (max 1-2)?
    YES -> SubViewport + Sprite3D (full Control node richness)
    NO  -> Is it text (damage number, nameplate)?
      YES -> Label3D + billboard + tween
      NO  -> Sprite3D with texture atlas
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

For the full shader code, billboard setup, and configuration details, read
`references/health-bar-shader.md`.

### Key Concepts

- **`instance uniform float health`** — per-instance value without unique materials.
  Set via `SetInstanceShaderParameter("health", ratio)` in C#.
- **Shader billboard** — `MODELVIEW_MATRIX` manipulation in the vertex shader makes the
  quad face the camera regardless of entity rotation.
- **`render_mode unshaded, cull_disabled`** — no lighting, visible from all angles.

### C# Integration Pattern

`SetInstanceShaderParameter` writes to the per-instance uniform buffer. It does not
allocate a new material — all enemies share the same ShaderMaterial. This is the key
performance advantage over creating unique materials per entity.

```csharp
// Pattern: subscribe to health observable, update instance shader parameter
_ = viewModel.HealthRatio.Subscribe(ratio =>
{
    if (IsInstanceValid(this))
        HealthBar.SetInstanceShaderParameter("health", ratio);
});
```

For the full integration with CrystalMagica's MVVM architecture — including the actual
current state of `EnemyNode.cs`, `RemoteCharacterVM.cs`, and `Enemy.tscn`, plus the
proposed extensions — read `references/scene-integration.md`.

---

## SubViewport + Sprite3D (Player HUD / Boss Bars)

Reserve this approach for the local player's overhead bar or a single boss health bar
where rich 2D controls justify the render cost.

### Scene Setup

```
BossHealthBar (Sprite3D)
  +-- SubViewport (size: 256x32, transparent_bg: true)
      +-- ProgressBar (Control)
          +-- Fill (TextureProgressBar)
          +-- Label (current / max HP text)
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

Damage numbers appear above enemies when damage is dealt, float upward, and fade out.
With many enemies taking AoE damage simultaneously, you can easily spawn 20+ numbers in
a single frame.

For the complete `DamageNumberPool` implementation (C# class, Label3D configuration,
pool sizing, and MVVM integration), read `references/damage-number-pool.md`.

### Key Design Decisions

- **Object pool** — pre-allocate Label3D instances at `_Ready()`. Reuse after animation.
  Never `new Label3D()` or `QueueFree()` during gameplay.
- **Silent drop on exhaustion** — if the pool is empty, skip the number. The player will
  not notice a missing number in a high-volume AoE, but an allocation spike will cause a
  visible frame hitch.
- **Tween animation** — parallel rise + fade using `CreateTween().SetParallel(true)`.
  Return to pool via `TweenCallback` after animation completes.
- **Crit scaling** — crits start at 2x scale and shrink with a `Back` ease for pop effect.

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

Reduce visual fidelity for entities far from the camera. Consider using a single
zone-level LOD manager that iterates entities rather than per-entity `_Process` checks,
or use `VisibleOnScreenNotifier3D` for culling.

| Distance | Health Bar | Damage Numbers | Nameplate |
|----------|-----------|----------------|-----------|
| Near (0-15m) | Full size, border, gradient | All shown, crit effects | Full name + title |
| Mid (15-30m) | Reduced size, no border | Only crits shown | Name only |
| Far (30m+) | Hidden | Hidden | Hidden |

### Throttling Updates

For entities at mid distance, throttle health bar updates to reduce shader parameter writes:

```csharp
// Throttle distant updates — max 10 updates/sec
_ = viewModel.HealthRatio
    .Sample(TimeSpan.FromMilliseconds(100))
    .Subscribe(ratio =>
    {
        if (IsInstanceValid(this))
            HealthBar.SetInstanceShaderParameter("health", ratio);
    });
```

For near enemies, subscribe without throttling for immediate visual feedback.

---

## Nameplates — Label3D

Enemy or player nameplates use Label3D positioned above the health bar. Configure with
`Billboard = Enabled`, `FixedSize = true`, `FontSize = 24`, `OutlineSize = 4`.

For the proposed Nameplate class and scene tree layout, see `references/scene-integration.md`.

---

## Anti-Patterns

### SubViewport per Enemy

```csharp
// WRONG: SubViewport for each generic enemy — 20 enemies = 20 extra render passes
public partial class EnemyHealthBar : Sprite3D
{
    [Export] public SubViewport Viewport { get; set; }
}

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

## Checklists

### Adding Health Bars to a New Entity

1. Add `QuadMesh` MeshInstance3D child to entity scene, positioned above mesh
2. Create or reuse `HealthBar3D.gdshader` with instance uniform
3. Assign shared ShaderMaterial to the QuadMesh
4. Add `[Export] public MeshInstance3D HealthBar` to the entity's C# script
5. In `Bind()`, subscribe to health observable and call `SetInstanceShaderParameter`
6. Add LOD visibility toggle based on camera distance
7. Test with 20+ entities on screen — verify no frame drops

### Adding Damage Numbers

1. Create `DamageNumberPool` scene and add to zone/level scene
2. Size pool based on max expected simultaneous numbers (see pool sizing table)
3. Subscribe to damage events in the coordinator, call `DamageNumbers.Show()`
4. Test AoE scenario — verify pool exhaustion drops silently, no allocation spikes
