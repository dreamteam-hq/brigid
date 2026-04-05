# DamageNumberPool — Label3D Object Pool

Damage numbers appear above enemies when damage is dealt, float upward, and fade out.
With many enemies taking AoE damage simultaneously, you can easily spawn 20+ numbers in
a single frame. Object pooling prevents allocation spikes.

## Label3D Configuration

| Property | Value | Why |
|----------|-------|-----|
| `Billboard` | `BaseMaterial3D.BillboardModeEnum.Enabled` | Always faces camera |
| `FixedSize` | `true` | Constant screen size regardless of distance |
| `NoDepthTest` | `true` | Renders on top of geometry (visible through enemies) |
| `FontSize` | 32-48 | Readable at gameplay distance |
| `OutlineSize` | 4-6 | Legible against any background |
| `Modulate` | varies | White for normal, yellow for crit, red for self-damage |

## DamageNumberPool Implementation

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

## Pool Sizing

| Scenario | Pool Size | Reasoning |
|----------|-----------|-----------|
| Single-target combat | 10 | Rapid attacks on one enemy |
| AoE (10 enemies) | 30 | 10 enemies x ~3 overlapping numbers |
| AoE (20 enemies) | 60 | 20 enemies x ~3 overlapping numbers |
| Raid boss (20+ players) | 50-100 | Many simultaneous damage sources |

If the pool is exhausted, numbers are silently dropped. This is intentional — the player
will not notice a missing number in a high-volume AoE scenario, but an allocation spike
will cause a visible frame hitch.

## PROPOSED FOR LOOP 4 — MVVM Integration

> The types and patterns below do NOT exist in CrystalMagica today. They show how
> damage numbers would integrate with the MVVM architecture once health/damage systems
> are implemented.

### Scene Coordinator Integration

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

### Proposed ViewModel Extension

```csharp
// PROPOSED: RemoteCharacterVM.cs — damage as a fire-and-forget event stream
// Does NOT exist today. Requires: DamageEvent type, server damage messages.
public Subject<DamageEvent> DamageEvents { get; } = new();

// Populated by the message processor:
target.Value.DamageEvents.OnNext(new DamageEvent(amount, isCrit));
```

### Proposed Types

```csharp
// PROPOSED: new type — does not exist in CrystalMagica today
public record DamageEvent(int Amount, bool IsCrit);
```
