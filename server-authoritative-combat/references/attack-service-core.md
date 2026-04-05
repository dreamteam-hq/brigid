# AttackService Core Reference

Full implementation patterns for the `AttackService` `BackgroundService`, including
hitbox math, attack registration, validation, tick loop, overlap processing, and
broadcast helpers.

All code grounded in actual CrystalMagica patterns: `BackgroundService` tick loop from
`EnemyControllerService`, broadcast pattern from `MapHub.RelayCharacterAction`,
`ConcurrentDictionary` from `MapHub.ConnectedUsers`.

## Table of Contents

- [HitboxMath](#hitboxmath-static-helper) | [AttackService Class](#attackservice-class) | [Tick Loop](#tick-loop)
- [Register Attack](#register-attack-called-from-maphub) | [Validation](#intent-validation) | [Process Loop](#process-loop) | [Broadcast](#broadcast-helpers)

---

## HitboxMath (Static Helper)

Pure math, no state. Place in `CrystalMagica.Server/Services/HitboxMath.cs`.

```csharp
using System.Numerics;
using CrystalMagica.Models;

namespace CrystalMagica.Server.Services;

public static class HitboxMath
{
    // Melee swing dimensions -- generous for networked play
    private const float MeleeWidth = 2.0f;
    private const float MeleeHeight = 1.5f;

    /// <summary>Construct an AABB in the attacker's facing direction.</summary>
    public static (Vector2 Min, Vector2 Max) ComputeHitbox(
        Vector2 attackerPos, FaceDirection direction, AttackType attackType)
    {
        var (width, height) = attackType switch  // extend for ranged/AoE
        {
            AttackType.MeleeSwing => (MeleeWidth, MeleeHeight),
            _ => (MeleeWidth, MeleeHeight)
        };

        var halfHeight = height * 0.5f;

        var min = direction switch  // offset in facing direction
        {
            FaceDirection.Right => new Vector2(attackerPos.X, attackerPos.Y - halfHeight),
            FaceDirection.Left => new Vector2(attackerPos.X - width, attackerPos.Y - halfHeight),
            _ => attackerPos
        };

        var max = new Vector2(min.X + width, min.Y + height);

        return (min, max);
    }

    /// <summary>Test circle (hurtbox) vs AABB (hitbox) overlap. No sqrt.</summary>
    public static bool Overlaps(Vector2 aabbMin, Vector2 aabbMax,
        Vector2 enemyCenter, float enemyRadius)
    {
        var closestX = Math.Clamp(enemyCenter.X, aabbMin.X, aabbMax.X);
        var closestY = Math.Clamp(enemyCenter.Y, aabbMin.Y, aabbMax.Y);
        var dx = enemyCenter.X - closestX;
        var dy = enemyCenter.Y - closestY;
        return (dx * dx + dy * dy) <= (enemyRadius * enemyRadius);
    }
}
```

**Why circle-vs-AABB**: enemies are a single position point on the server (no bounding
box). A hurtbox radius is the simplest correct model. Switch to AABB-vs-AABB when enemies
get proper server-side bounding boxes.

**Default branch**: `_ => attackerPos` is unreachable (`FaceDirection` only has
`Left`/`Right`). If the enum gains values, this default silently produces a right-offset
hitbox. Replace with `throw new ArgumentOutOfRangeException()` when expanding.

---

## AttackService Class

```csharp
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Numerics;
using CrystalMagica.Models;
using CrystalMagica.Server.ReceiverHubs;

namespace CrystalMagica.Server.Services;

public class AttackService(MapHub mapHub, EnemyControllerService enemyService)
    : BackgroundService
{
    private readonly ConcurrentDictionary<Guid, ActiveAttack> _activeAttacks = new();
    private readonly ConcurrentDictionary<Guid, long> _lastAttackTime = new();
    private long _currentTick;

    private const int TickIntervalMs = 100;         // 10 Hz attack tick
    private const int MeleeSwingDurationTicks = 4;   // 400ms active window
    private const int BaseMeleeDamage = 25;
    private const float EnemyHurtboxRadius = 0.5f;
    private const int CooldownTicks = 5;             // 500ms between attacks
    private const float MaxPositionDrift = 2.0f;
```

---

## Tick Loop

Follows the same `Stopwatch` + `Task.Delay` pattern as `EnemyControllerService`, but at
10 Hz instead of the patrol cadence.

```csharp
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var sw = Stopwatch.StartNew();

        while (!stoppingToken.IsCancellationRequested)
        {
            var tickStart = sw.ElapsedMilliseconds;
            _currentTick++;

            ProcessActiveAttacks();
            PurgeExpiredAttacks();

            var elapsed = sw.ElapsedMilliseconds - tickStart;
            var delay = Math.Max(0, TickIntervalMs - elapsed);
            await Task.Delay((int)delay, stoppingToken);
        }
    }
```

**Tick budget**: 100ms is extremely generous. 50 attacks x 100 enemies = 5000 overlap
checks, each a few multiplications -- microseconds total.

**Cancellation token**: neither method checks the token between calls. Both are
microsecond-level -- add a check only if they grow to include I/O.

---

## Register Attack (Called from MapHub)

```csharp
    /// <summary>Called from MapHub.PerformAttack on WebSocket receive thread.</summary>
    public bool RegisterAttack(AttackIntent intent, ConnectedUser user)
    {
        if (!ValidateIntent(intent, user))
            return false;

        var (min, max) = HitboxMath.ComputeHitbox(
            user.Character.Position,   // server-authoritative position
            intent.Direction,
            intent.AttackType);

        var attack = new ActiveAttack
        {
            AttackerId = user.Character.Id,
            Min = min,
            Max = max,
            TickBorn = _currentTick,
            TickExpires = _currentTick + MeleeSwingDurationTicks
        };

        _activeAttacks[attack.AttackId] = attack;
        _lastAttackTime[user.Character.Id] = _currentTick;
        return true;
    }
```

**Position authority**: `user.Character.Position` is used for hitbox construction,
not `intent.Position`. `RegisterAttack` is the canonical authority on attack origin --
the hub's `intent.Position` overwrite is defensive. This **intentionally diverges** from
`RelayCharacterAction` which accepts client position. See `references/integration-and-di.md`
for the full relay-vs-combat comparison.

---

## Intent Validation

```csharp
    private bool ValidateIntent(AttackIntent intent, ConnectedUser user)
    {
        if (!mapHub.ConnectedUsers.ContainsKey(user.SessionId))
            return false;                                           // not connected
        if (_lastAttackTime.TryGetValue(user.Character.Id, out var lastTime)
            && _currentTick - lastTime < CooldownTicks)
            return false;                                           // cooldown
        var delta = intent.Position - user.Character.Position;
        if (delta.LengthSquared() > MaxPositionDrift * MaxPositionDrift)
            return false;                                           // position drift
        if (!Enum.IsDefined(intent.AttackType))
            return false;                                           // bad enum

        return true;
    }
```

Reject early, reject cheap. Checks cost: connected (dict lookup), cooldown (lookup +
subtract), position drift (two subtracts + multiply), enum (`Enum.IsDefined`, fast in .NET 10).

**Validation order**: cheapest/most-likely-to-reject first. Connected (dictionary lookup),
cooldown (lookup + subtraction), position drift (two subtracts + multiply), enum (cached
reflection). This order rejects spammers and disconnects before doing any real math.

---

## Process Loop

```csharp
    private void ProcessActiveAttacks()
    {
        var enemies = enemyService.GetEnemySnapshot();  // snapshot: copy, no lock

        foreach (var attack in _activeAttacks.Values)
        {
            foreach (var enemy in enemies)
            {
                if (attack.HitEnemies.Contains(enemy.Id))  // dedup
                    continue;
                if (!HitboxMath.Overlaps(attack.Min, attack.Max,
                    enemy.Position, EnemyHurtboxRadius))    // overlap test
                    continue;

                attack.HitEnemies.Add(enemy.Id);
                var newHp = enemyService.ApplyDamage(enemy.Id, BaseMeleeDamage);
                BroadcastHealthUpdate(enemy.Id, newHp, enemy.MaxHp, attack.AttackerId);

                if (newHp <= 0)
                    BroadcastEnemyDied(enemy.Id, attack.AttackerId);
            }
        }
    }

    private void PurgeExpiredAttacks()
    {
        foreach (var kvp in _activeAttacks)
        {
            if (kvp.Value.TickExpires <= _currentTick)
                _activeAttacks.TryRemove(kvp.Key, out _);
        }
    }
```

**Why snapshot-then-iterate**: reading positions directly during the attack loop risks
mid-iteration movement by `EnemyControllerService`, causing inconsistent overlap results
within a single tick. The snapshot ensures consistency.

**Why `HashSet<Guid>`**: O(1) `Contains`. 400ms swing at 10 Hz = 4 checks per enemy.
Without dedup: 4x damage. With dedup: exactly 1x.

**Dead enemy in snapshot**: the snapshot may include `Hp <= 0` enemies (died earlier
in the same tick). `ApplyDamage` clamps to 0 again and a duplicate `EnemyDied` fires.
Clients must be idempotent -- see Race 3 in `references/thread-safety.md`.

---

## Broadcast Helpers

Follow the same fire-and-forget broadcast pattern as `EnemyControllerService.BroadcastAction`
and `MapHub.RelayCharacterAction`.

```csharp
    private void BroadcastHealthUpdate(Guid enemyId, int hp, int maxHp, Guid attackerId)
    {
        var health = new EnemyHealth
        {
            EnemyId = enemyId,
            CurrentHp = hp,
            MaxHp = maxHp,
            AttackerId = attackerId
        };

        foreach (var user in mapHub.ConnectedUsers.Values)
        {
            // Fire-and-forget -- same pattern as EnemyControllerService line 71
            _ = user.GameClient.Map.EnemyHealthUpdated(health);
        }
    }

    private void BroadcastEnemyDied(Guid enemyId, Guid attackerId)
    {
        foreach (var user in mapHub.ConnectedUsers.Values)
        {
            _ = user.GameClient.Map.EnemyDied(enemyId);
        }
    }
}
```

The `_ =` discard pattern is the existing codebase convention. The generated method
serializes, writes to `ConnectedUser.Outgoing` (bounded channel, `DropOldest`), and returns.
Dropping oldest messages is acceptable for health updates where only the latest value matters.

**Broadcast atomicity**: `foreach` over `ConnectedUsers.Values` is not atomic -- a player
connecting mid-broadcast may be missed (gets next update) and a disconnecting player's
write is a no-op. Same behavior as `EnemyControllerService.BroadcastAction` (line 68).
