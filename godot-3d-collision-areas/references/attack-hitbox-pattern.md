# Attack Hitbox Pattern (Area3D)

Reference material for `godot-3d-collision-areas`. See SKILL.md for core collision concepts.

## Scene Structure

```
Player (CharacterBody3D)               layer=2
  +-- Collision (CollisionShape3D)      # physics body
  +-- Mesh (MeshInstance3D)
  +-- AttackHitbox (Area3D)             layer=4 (PlayerHitbox), mask=6 (EnemyHurtbox)
      +-- CollisionShape3D              # disabled by default
  +-- Hurtbox (Area3D)                  layer=3 (PlayerHurtbox), mask=7 (EnemyHitbox)
      +-- CollisionShape3D              # always active
```

## Enable/Disable on Attack

```csharp
public partial class PlayerNode : CharacterBody3D
{
    private Area3D _attackHitbox;
    private CollisionShape3D _attackShape;
    private bool _isAttacking;

    public override void _Ready()
    {
        _attackHitbox = GetNode<Area3D>("AttackHitbox");
        _attackShape = _attackHitbox.GetNode<CollisionShape3D>("CollisionShape3D");

        // Start disabled
        _attackHitbox.Monitoring = false;
        _attackShape.Disabled = true;

        // Connect signal for hit detection
        _attackHitbox.AreaEntered += OnAttackHit;
    }

    public void StartAttack()
    {
        if (_isAttacking) return;

        _isAttacking = true;
        _attackHitbox.Monitoring = true;
        _attackShape.Disabled = false;

        // Position hitbox in front of player based on facing direction
        float facing = /* 1.0f or -1.0f based on direction */;
        _attackHitbox.Position = new Vector3(facing * 0.8f, 0.0f, 0.0f);
    }

    public void EndAttack()
    {
        _attackHitbox.Monitoring = false;
        _attackShape.Disabled = true;
        _isAttacking = false;
    }

    private void OnAttackHit(Area3D area)
    {
        // area is an enemy hurtbox -- get the enemy node
        if (area.GetParent() is CharacterBody3D enemy)
        {
            GD.Print($"Hit enemy: {enemy.Name}");
        }
    }
}
```

## Single-Hit vs Multi-Hit

For a single-hit attack (sword slash), track which enemies were already hit this swing:

```csharp
private readonly HashSet<Node3D> _hitThisSwing = new();

private void OnAttackHit(Area3D area)
{
    var enemy = area.GetParent() as CharacterBody3D;
    if (enemy == null || _hitThisSwing.Contains(enemy)) return;

    _hitThisSwing.Add(enemy);
    // Apply damage once
}

public void StartAttack()
{
    _hitThisSwing.Clear();
    // ... enable hitbox ...
}
```

For a multi-hit attack (spinning), skip the `HashSet` -- let each overlap frame deal damage (with a per-enemy cooldown timer).

## Enemy Hurtbox Setup

```
Enemy (CharacterBody3D)                 layer=5 (Enemy)
  +-- Collision (CollisionShape3D)      # physics body
  +-- EnemyMesh (MeshInstance3D)
  +-- Hurtbox (Area3D)                  layer=6 (EnemyHurtbox), mask=4 (PlayerHitbox)
      +-- CollisionShape3D              # always active
  +-- Hitbox (Area3D)                   layer=7 (EnemyHitbox), mask=3 (PlayerHurtbox)
      +-- CollisionShape3D              # active during enemy attacks
```

## Hitbox Shape Sizing (2.5D)

All hitbox/hurtbox shapes must use Z-depth = 4.0 to match CrystalMagica's collision convention:

```csharp
// Player melee hitbox -- box extending in attack direction
var hitboxShape = new BoxShape3D { Size = new Vector3(1.5f, 1.0f, 4.0f) };

// Enemy hurtbox -- slightly larger than visual mesh
var hurtboxShape = new BoxShape3D { Size = new Vector3(1.0f, 1.2f, 4.0f) };
```

## Integration with AnimationPlayer

For animation-driven attacks, use AnimationPlayer method tracks to call `StartAttack()` and `EndAttack()` at the correct keyframes:

1. Add a method track in the attack animation
2. At the "hit start" keyframe, call `StartAttack()`
3. At the "hit end" keyframe, call `EndAttack()`

This ties hitbox activation to the visual animation rather than relying on timers, ensuring the hitbox matches what the player sees on screen.
