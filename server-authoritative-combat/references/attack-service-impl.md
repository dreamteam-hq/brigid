# AttackService Implementation Reference

Full implementation patterns for the `AttackService` `BackgroundService`, including
tick loop, hitbox math, attack registration, overlap processing, and broadcast helpers.

All code grounded in actual CrystalMagica patterns: `BackgroundService` tick loop from
`EnemyControllerService`, broadcast pattern from `MapHub.RelayCharacterAction`,
`ConcurrentDictionary` from `MapHub.ConnectedUsers`, DI registration from `Program.cs`.

## Table of Contents

- [HitboxMath (Static Helper)](#hitboxmath-static-helper)
- [AttackService Class](#attackservice-class)
- [Tick Loop](#tick-loop)
- [Register Attack](#register-attack-called-from-maphub)
- [Intent Validation](#intent-validation)
- [Process Loop](#process-loop)
- [Broadcast Helpers](#broadcast-helpers)
- [DI Registration](#di-registration)
- [EnemyControllerService Changes](#enemycontrollerservice-changes)
- [MapHub Changes](#maphub-changes)
- [Client-Side Integration](#client-side-integration)

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

    /// <summary>
    /// Construct an AABB in the attacker's facing direction.
    /// Returns (min, max) corners of the hitbox rectangle.
    /// </summary>
    public static (Vector2 Min, Vector2 Max) ComputeHitbox(
        Vector2 attackerPos, FaceDirection direction, AttackType attackType)
    {
        // All attack types use the same base dimensions for now.
        // Extend this switch when adding ranged/AoE attacks.
        var (width, height) = attackType switch
        {
            AttackType.MeleeSwing => (MeleeWidth, MeleeHeight),
            _ => (MeleeWidth, MeleeHeight)
        };

        var halfHeight = height * 0.5f;

        // Offset hitbox in facing direction from the attacker's center
        var min = direction switch
        {
            FaceDirection.Right => new Vector2(attackerPos.X, attackerPos.Y - halfHeight),
            FaceDirection.Left => new Vector2(attackerPos.X - width, attackerPos.Y - halfHeight),
            _ => attackerPos
        };

        var max = new Vector2(min.X + width, min.Y + height);

        return (min, max);
    }

    /// <summary>
    /// Test whether a circle (enemy hurtbox) overlaps an AABB (attack hitbox).
    /// Uses squared distance to avoid Math.Sqrt.
    /// </summary>
    public static bool Overlaps(Vector2 aabbMin, Vector2 aabbMax,
        Vector2 enemyCenter, float enemyRadius)
    {
        // Clamp the enemy center to the AABB to find the closest point
        var closestX = Math.Clamp(enemyCenter.X, aabbMin.X, aabbMax.X);
        var closestY = Math.Clamp(enemyCenter.Y, aabbMin.Y, aabbMax.Y);

        var dx = enemyCenter.X - closestX;
        var dy = enemyCenter.Y - closestY;

        // Compare squared distance to squared radius (no sqrt)
        return (dx * dx + dy * dy) <= (enemyRadius * enemyRadius);
    }
}
```

**Why circle-vs-AABB instead of AABB-vs-AABB**: enemies are represented by a single position
point on the server (no authoritative bounding box). A hurtbox radius around that point is
the simplest correct model. When enemies get proper server-side bounding boxes, switch to
AABB-vs-AABB.

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

**Tick budget at 10 Hz**: 100ms per tick is extremely generous for melee overlap checks.
Even with 50 active attacks x 100 enemies = 5000 overlap checks, each is a few
multiplications -- microseconds total. The tick loop will never overrun.

---

## Register Attack (Called from MapHub)

```csharp
    /// <summary>
    /// Called from MapHub.PerformAttack on the WebSocket receive thread.
    /// Validates the intent, builds an ActiveAttack, and stores it for
    /// the tick loop to process.
    /// </summary>
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

Note: `user.Character.Position` is used, not `intent.Position`. The server overwrites
identity and position -- same pattern as `MapHub.RelayCharacterAction` line 21-23:
```csharp
user.Character.Position = action.Position;
action.CharacterId = user.Character.Id;
```

---

## Intent Validation

```csharp
    private bool ValidateIntent(AttackIntent intent, ConnectedUser user)
    {
        // Player must be connected (not mid-disconnect)
        if (!mapHub.ConnectedUsers.ContainsKey(user.SessionId))
            return false;

        // Cooldown check -- 500ms (5 ticks) minimum between attacks
        if (_lastAttackTime.TryGetValue(user.Character.Id, out var lastTime)
            && _currentTick - lastTime < CooldownTicks)
            return false;

        // Position plausibility -- squared distance avoids sqrt
        var delta = intent.Position - user.Character.Position;
        if (delta.LengthSquared() > MaxPositionDrift * MaxPositionDrift)
            return false;

        // Attack type must be a valid enum value
        if (!Enum.IsDefined(intent.AttackType))
            return false;

        return true;
    }
```

Reject early, reject cheap. The connected check is a dictionary lookup. The cooldown
check is a dictionary lookup + subtraction. Position drift is two subtractions + a
multiply. Enum validation is the most expensive (reflection on first call, cached after).

---

## Process Loop

```csharp
    private void ProcessActiveAttacks()
    {
        // Snapshot enemy state once per tick -- read from EnemyControllerService
        // This returns a copy, so we can iterate without holding a lock
        var enemies = enemyService.GetEnemySnapshot();

        foreach (var attack in _activeAttacks.Values)
        {
            foreach (var enemy in enemies)
            {
                // Dedup: each attack damages each enemy at most once
                if (attack.HitEnemies.Contains(enemy.Id))
                    continue;

                // Overlap test: AABB (hitbox) vs circle (hurtbox)
                if (!HitboxMath.Overlaps(attack.Min, attack.Max,
                    enemy.Position, EnemyHurtboxRadius))
                    continue;

                // --- Hit confirmed ---
                attack.HitEnemies.Add(enemy.Id);
                var newHp = enemyService.ApplyDamage(enemy.Id, BaseMeleeDamage);

                // Broadcast to ALL connected users (attacker + observers)
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

**Why snapshot-then-iterate**: `EnemyControllerService` updates enemy positions on its
own schedule. If we read positions directly during the attack loop, an enemy could move
mid-iteration, causing inconsistent overlap results within a single tick. The snapshot
gives a consistent view.

**Why `HitEnemies` is a `HashSet<Guid>`**: `Contains` is O(1). For a 400ms swing at
10 Hz (4 ticks), each enemy is checked 4 times. Without dedup, the enemy takes 4x damage.
With dedup, exactly 1x.

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

The `_ =` pattern discards the `Task` returned by the generated `GameClient.Map` method.
This is the existing convention throughout the codebase. The generated method serializes
the model, writes to the `ConnectedUser.Outgoing` bounded channel, and returns. If the
channel is full (`BoundedChannelFullMode.DropOldest`), the oldest message is dropped --
acceptable for health updates where only the latest value matters.

---

## DI Registration

```csharp
// In Program.cs -- update existing EnemyControllerService registration
// and add AttackService

// BEFORE (Loop 2):
// _ = builder.Services.AddHostedService<EnemyControllerService>();

// AFTER (Loop 5):
_ = builder.Services.AddSingleton<EnemyControllerService>();
_ = builder.Services.AddHostedService(sp => sp.GetRequiredService<EnemyControllerService>());
_ = builder.Services.AddSingleton<AttackService>();
_ = builder.Services.AddHostedService(sp => sp.GetRequiredService<AttackService>());
```

The `AddSingleton` + `AddHostedService(factory)` pattern is necessary because:
- `AttackService` needs `EnemyControllerService` injected via constructor.
- `MapHub` needs `AttackService` injected via constructor.
- `AddHostedService<T>()` alone creates a separate instance that is not retrievable
  from DI -- only the host holds a reference for lifecycle management.
- The factory overload `sp => sp.GetRequiredService<T>()` tells the host to use the
  singleton instance already registered in DI.

---

## EnemyControllerService Changes

The existing service needs three additions for combat support. These are minimal,
non-breaking changes to the existing patrol logic.

```csharp
// New types (can be nested or in a separate file)
public record EnemySnapshot(Guid Id, Vector2 Position, int Hp, int MaxHp);

// Inside EnemyControllerService:
private readonly ConcurrentDictionary<Guid, EnemyState> _enemies = new();

public class EnemyState
{
    public CharacterData Character { get; init; }
    public int Hp { get; set; }
    public int MaxHp { get; init; }
    public object Lock { get; } = new();   // per-enemy lock for damage
}

/// <summary>
/// Returns a snapshot copy for the attack tick loop.
/// Called from AttackService once per tick.
/// </summary>
public IReadOnlyList<EnemySnapshot> GetEnemySnapshot()
{
    return _enemies.Values
        .Select(e => new EnemySnapshot(e.Character.Id, e.Character.Position, e.Hp, e.MaxHp))
        .ToList();
}

/// <summary>
/// Apply damage to an enemy. Returns the new HP.
/// Thread-safe via per-enemy lock.
/// </summary>
public int ApplyDamage(Guid enemyId, int damage)
{
    if (!_enemies.TryGetValue(enemyId, out var enemy))
        return 0;

    lock (enemy.Lock)
    {
        enemy.Hp = Math.Max(0, enemy.Hp - damage);
        return enemy.Hp;
    }
}
```

The existing `ExecuteAsync` patrol loop initializes the enemy in `_enemies` instead of
setting `mapHub.EnemyCharacter` directly:

```csharp
// In ExecuteAsync, replace:
//   mapHub.EnemyCharacter = enemy;
// With:
var state = new EnemyState { Character = enemy, Hp = 100, MaxHp = 100 };
_enemies[enemy.Id] = state;
mapHub.EnemyCharacter = enemy;   // keep for JoinRequest backward compat
```

---

## MapHub Changes

```csharp
// Update constructor to inject AttackService:
public class MapHub(SocketLogger socketLogger, AttackService attackService) : IMapHub
{
    // ... existing ConnectedUsers, EnemyCharacter, RelayCharacterAction, JoinRequest ...

    public async Task PerformAttack(AttackIntent intent, ConnectedUser user)
    {
        // Server-authoritative identity and position
        intent.Position = user.Character.Position;
        intent.AttackerId = user.Character.Id;

        attackService.RegisterAttack(intent, user);
    }
}
```

The `async Task` signature matches the pattern from `RelayCharacterAction`. The generated
`ReceiverHubInterfaceGenerator` expects this signature because the interface method in
`ClientHubs.Server.IMapHub` returns `Task`.

---

## Client-Side Integration

### LocalPlayerCharacterVM

Add a method to send attack intent. Follows the same pattern as `SendAction` for movement.

```csharp
public void PerformAttack(FaceDirection direction)
{
    // Cosmetic prediction -- play animation immediately
    AttackAnimationRequested?.Invoke(direction);

    // Send intent to server via generated ServerClient wrapper
    _serverClient.Map.PerformAttack(new AttackIntent
    {
        Position = Position,
        Direction = direction,
        AttackType = AttackType.MeleeSwing
    });
}
```

### MainViewModel (Message Routing)

The `MessageRouter` (generated) automatically routes `Map_EnemyHealthUpdated` and
`Map_EnemyDied` to the appropriate handler. Wire up the handlers in `MainViewModel`
(or wherever `ISocketContext` is implemented) to update enemy HP display and play
death animations.

```csharp
// These methods are called by the generated MessageRouter when the
// corresponding GameMessageType arrives
public void OnEnemyHealthUpdated(EnemyHealth health)
{
    // Update enemy VM's HP, trigger health bar animation
}

public void OnEnemyDied(Guid enemyId)
{
    // Remove enemy from SourceCache, play death animation
}
```
