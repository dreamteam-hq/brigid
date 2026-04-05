# Thread Safety Reference

Detailed thread safety patterns for shared state between `AttackService`,
`EnemyControllerService`, and `MapHub`.

## Shared State Map

| State | Written By | Read By | Mechanism |
|---|---|---|---|
| `MapHub.ConnectedUsers` | `MapHub` (join/leave) | `AttackService` (broadcast) | `ConcurrentDictionary` -- already thread-safe |
| `MapHub.EnemyCharacter` | `EnemyControllerService` | `MapHub` (join response) | Single writer, reads are non-critical |
| `_activeAttacks` | `MapHub.PerformAttack` (register), `AttackService` (purge) | `AttackService` (tick loop) | `ConcurrentDictionary` |
| Enemy positions | `EnemyControllerService` (patrol tick) | `AttackService` (overlap check) | Snapshot pattern (see below) |
| Enemy HP | `AttackService` (damage) | `AttackService`, `EnemyControllerService` (death) | `Interlocked` or lock per enemy |

## Snapshot Pattern for Enemy State

`EnemyControllerService` exposes a method that returns a **snapshot** of current enemy
state. The `AttackService` reads this snapshot once per tick and processes it without
holding a lock across the entire loop.

```csharp
// In EnemyControllerService:
public IReadOnlyList<EnemySnapshot> GetEnemySnapshot()
{
    // Return a copy -- AttackService can iterate without contention
    return _enemies.Values.Select(e => new EnemySnapshot(e.Id, e.Position, e.Hp, e.MaxHp))
        .ToList();
}
```

For the current single-enemy case, this is trivially a one-element list. The pattern
scales to multi-enemy without architectural change.

## Damage Application

```csharp
// In EnemyControllerService:
public int ApplyDamage(Guid enemyId, int damage)
{
    // Lock per-enemy, not globally
    lock (_enemies[enemyId])
    {
        var enemy = _enemies[enemyId];
        enemy.Hp = Math.Max(0, enemy.Hp - damage);
        return enemy.Hp;
    }
}
```

Using `Interlocked.Add` is an alternative for simple subtraction, but a lock is
clearer when HP clamping and death checks are involved.

## Why Not a Global Lock

A single lock for all enemies serializes the attack tick across all combat.
With 50 players attacking different enemies simultaneously, a global lock means
only one damage application at a time. Per-enemy locks allow parallel damage
to different enemies. The snapshot pattern for reads eliminates read contention
entirely.
