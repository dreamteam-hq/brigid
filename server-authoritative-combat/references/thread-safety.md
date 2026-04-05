# Thread Safety Reference

Detailed thread safety analysis for shared state between `AttackService`,
`EnemyControllerService`, and `MapHub`. Every mechanism described here maps to
existing CrystalMagica patterns or standard .NET concurrent primitives.

## Table of Contents

- [Thread Map](#thread-map)
- [Shared State Matrix](#shared-state-matrix)
- [Snapshot Pattern for Enemy State](#snapshot-pattern-for-enemy-state)
- [Per-Enemy Damage Lock](#per-enemy-damage-lock)
- [ConcurrentDictionary for Active Attacks](#concurrentdictionary-for-active-attacks)
- [ConnectedUsers Access](#connectedusers-access)
- [Race Condition Analysis](#race-condition-analysis)
- [Scaling Considerations](#scaling-considerations)

---

## Thread Map

Understanding which code runs on which thread is the foundation of the safety analysis.

| Thread | Service | What Runs There |
|---|---|---|
| WebSocket receive (per connection) | `SocketHandler.ReceiveLoop` | Deserialize, route to `MapHub.PerformAttack` |
| WebSocket send (per connection) | `SocketHandler.SendLoop` | Drain `Outgoing` channel, write to socket |
| AttackService tick | `AttackService.ExecuteAsync` | 10 Hz: snapshot, overlap, damage, broadcast |
| EnemyControllerService tick | `EnemyControllerService.ExecuteAsync` | Patrol movement, position updates |
| Host thread | Generic Host | Startup, shutdown, lifecycle |

Key observations:
- `MapHub.PerformAttack` runs on **any** WebSocket receive thread. Multiple players
  attacking simultaneously means multiple concurrent calls.
- `AttackService` tick loop runs on **one** thread (the `Task` from `ExecuteAsync`).
- `EnemyControllerService` runs on **one** thread.
- The two `BackgroundService` ticks are independent -- they do not coordinate timing.

---

## Shared State Matrix

| State | Type | Written By | Read By | Thread Safety Mechanism |
|---|---|---|---|---|
| `MapHub.ConnectedUsers` | `ConcurrentDictionary<Guid, ConnectedUser>` | `MapHub.JoinRequest`, `ConnectionService.ConnectionDisconnected` | `AttackService` (broadcast), `EnemyControllerService` (broadcast) | `ConcurrentDictionary` -- already thread-safe for concurrent reads and writes |
| `AttackService._activeAttacks` | `ConcurrentDictionary<Guid, ActiveAttack>` | `RegisterAttack` (WebSocket thread), `PurgeExpiredAttacks` (tick thread) | `ProcessActiveAttacks` (tick thread) | `ConcurrentDictionary` -- safe for concurrent add/remove during enumeration |
| `AttackService._lastAttackTime` | `ConcurrentDictionary<Guid, long>` | `RegisterAttack` (WebSocket thread) | `ValidateIntent` (WebSocket thread) | `ConcurrentDictionary` -- both sides are WebSocket threads |
| `EnemyState.Character.Position` | `Vector2` (struct on class) | `EnemyControllerService` (patrol tick) | `AttackService` (via snapshot) | Snapshot pattern -- read a copy, not the live value |
| `EnemyState.Hp` | `int` | `AttackService.ProcessActiveAttacks` (via `ApplyDamage`) | `AttackService`, `EnemyControllerService` | Per-enemy `lock` |
| `MapHub.EnemyCharacter` | `CharacterData` (reference) | `EnemyControllerService` (once at startup) | `MapHub.JoinRequest` | Single writer at init, reads after -- safe |
| `ActiveAttack.HitEnemies` | `HashSet<Guid>` | `ProcessActiveAttacks` (tick thread) | `ProcessActiveAttacks` (tick thread) | Single-threaded access -- only the tick loop touches this |

---

## Snapshot Pattern for Enemy State

The most important safety mechanism. Without it, the attack tick loop would need to
hold a lock across the entire attack x enemy iteration, blocking patrol movement.

### How It Works

```csharp
// EnemyControllerService exposes:
public IReadOnlyList<EnemySnapshot> GetEnemySnapshot()
{
    return _enemies.Values
        .Select(e => new EnemySnapshot(e.Character.Id, e.Character.Position, e.Hp, e.MaxHp))
        .ToList();
}
```

`EnemySnapshot` is a `record` (immutable value type). The `.ToList()` creates a new
list with copied values. The `AttackService` tick loop calls this once at the start of
each tick and iterates the snapshot without contention.

### What Could Go Wrong Without It

If `AttackService` read `EnemyState.Character.Position` directly during iteration:
1. Tick starts, reads enemy at position (5, 2).
2. Mid-iteration, `EnemyControllerService` patrol updates position to (6, 2).
3. A second overlap check within the same tick sees position (6, 2).
4. The attack might hit at (5, 2) but miss at (6, 2), or vice versa -- inconsistent
   within a single tick.

With the snapshot, all overlap checks within a tick use the same position. Consistency
within a tick matters more than absolute freshness -- the enemy moved 1 unit in 100ms,
and the hitbox is 2 units wide. The next tick will use the updated position.

### Cost

For 1 enemy: trivial. For 100 enemies: ~100 struct copies + 1 list allocation per tick.
At 10 Hz, that is 1000 copies/second -- negligible. For 1000+ enemies, consider a
double-buffer instead of per-tick allocation.

---

## Per-Enemy Damage Lock

```csharp
// In EnemyControllerService:
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

### Why Per-Enemy, Not Global

A global lock serializes all damage:
```
Player A attacks Enemy 1 -- takes lock --
Player B attacks Enemy 2 -- waits for lock -- BLOCKED
```

Per-enemy locks allow parallel damage to different enemies:
```
Player A attacks Enemy 1 -- takes lock(enemy1) -- processes
Player B attacks Enemy 2 -- takes lock(enemy2) -- processes in parallel
```

### Why Lock, Not Interlocked

`Interlocked.Add` would work for simple subtraction:
```csharp
Interlocked.Add(ref enemy.Hp, -damage);
```

But HP clamping (`Math.Max(0, ...)`) and death checks require reading the new value
atomically with the write. With `Interlocked.Add`, the clamp and death check would be
a separate step, creating a TOCTOU race:

```
Thread A: Interlocked.Add(hp, -30) -> hp = -5  (should be 0)
Thread B: reads hp = -5, applies another -30 -> hp = -35
```

The lock ensures read-modify-clamp-return is atomic.

### Lock Contention

Contention occurs only when two players hit the **same** enemy in the **same** tick.
At 10 Hz, this is a 100ms window. The lock body is a subtraction + clamp + return --
nanoseconds. Even with 50 players attacking the same boss, the contention is
negligible.

---

## ConcurrentDictionary for Active Attacks

`_activeAttacks` is a `ConcurrentDictionary<Guid, ActiveAttack>` because:

1. **Writers**: `RegisterAttack` runs on WebSocket receive threads (concurrent, per-player).
2. **Readers/Removers**: `ProcessActiveAttacks` and `PurgeExpiredAttacks` run on the
   tick thread.

`ConcurrentDictionary` is safe for:
- Concurrent `TryAdd` from multiple WebSocket threads.
- `foreach` enumeration while other threads add/remove entries. The enumeration sees a
  snapshot-in-time view. New entries added after enumeration starts are not guaranteed
  to be seen in that iteration -- they will be picked up on the next tick. This is
  acceptable because the next tick is 100ms later.
- `TryRemove` during `foreach` of `.ToArray()` or the `ConcurrentDictionary` itself.

### Caveat: ActiveAttack.HitEnemies

`HitEnemies` is a plain `HashSet<Guid>`, not concurrent. This is safe because only the
tick loop thread reads and writes `HitEnemies`. The WebSocket threads that call
`RegisterAttack` never touch `HitEnemies` -- it is initialized as empty in the
`ActiveAttack` constructor and only modified in `ProcessActiveAttacks`.

---

## ConnectedUsers Access

`MapHub.ConnectedUsers` is a `ConcurrentDictionary<Guid, ConnectedUser>` that is already
shared across threads in the existing codebase:

- Written by `MapHub.JoinRequest` (WebSocket receive thread) and
  `ConnectionService.ConnectionDisconnected` (WebSocket receive thread).
- Read by `MapHub.RelayCharacterAction` (WebSocket receive thread) and
  `EnemyControllerService.BroadcastAction` (patrol tick thread).

`AttackService` adds another reader (broadcast helpers). This is safe -- `ConcurrentDictionary`
supports any number of concurrent readers.

The broadcast pattern (`foreach var user in ConnectedUsers.Values`) may miss a user who
connects mid-broadcast or include a user who disconnects mid-broadcast. Both are acceptable:
- Missed user: will get the next health update.
- Disconnected user: the `GameClient.Map.EnemyHealthUpdated` write to the `Outgoing`
  channel is a no-op if the channel is closed, or the message is dropped on the next
  `SendLoop` attempt.

---

## Race Condition Analysis

### Race 1: Attack registered after tick starts but before processing

A player attacks between the snapshot read and the overlap loop. The new `ActiveAttack`
is added to `_activeAttacks` via `ConcurrentDictionary.TryAdd`. If the tick's `foreach`
has already started, the new attack may or may not be seen. If not seen, it is processed
on the next tick (100ms later). Acceptable.

### Race 2: Enemy moves between snapshot and overlap check

Cannot happen. The snapshot is immutable. The overlap check uses the snapshot position.
The enemy's live position may have changed, but the check is consistent within the tick.

### Race 3: Two players kill the same enemy in the same tick

Both call `ApplyDamage` with the per-enemy lock. One sees `Hp = 0`, the other sees
`Hp = -25` (clamped to 0). Both `BroadcastEnemyDied`. The client receives two death
broadcasts for the same enemy -- the client should be idempotent (ignore second death
for an already-dead enemy).

### Race 4: Enemy dies during patrol

`EnemyControllerService` continues moving a dead enemy until it checks HP. Add an
`if (enemy.Hp <= 0) continue;` check in the patrol loop after combat is added.
Alternatively, remove the enemy from `_enemies` on death and let the patrol loop's
`_enemies.TryGetValue` return false.

### Race 5: Player disconnects mid-attack

The `ActiveAttack` references the player's `Character.Id` (a `Guid` value type, copied
on creation). The attack continues to process even after the player disconnects -- this
is correct. The attack was already validated and registered. Damage still applies.
Broadcasts to the disconnected player fail silently (channel closed).

---

## Scaling Considerations

### Current: 1 Enemy, < 50 Players

All mechanisms are overkill-safe. The snapshot is trivially one element. Per-enemy locks
have zero contention. The `ConcurrentDictionary` overhead is negligible.

### Future: 100 Enemies, 200 Players

- **Snapshot**: 100 struct copies per tick, 10 Hz = 1000 copies/sec. Negligible.
- **Active attacks**: burst of 50 attacks = 50 entries in `_activeAttacks`.
  Each attack checks 100 enemies = 5000 overlap tests per tick. Each test is
  a few float operations. Total: microseconds.
- **Per-enemy locks**: contention only when multiple attacks hit the same enemy
  in the same tick. With per-enemy granularity, parallel damage to different enemies
  is unblocked.
- **Broadcast**: 200 * (health updates per tick). Each broadcast writes to a
  `BoundedChannel`. Dropping oldest under pressure is acceptable for health updates.

### Future: 1000+ Enemies

- **Snapshot**: switch to double-buffer pattern. `EnemyControllerService` writes to
  buffer A while `AttackService` reads buffer B. Swap references atomically with
  `Interlocked.Exchange`. Zero allocation per tick.
- **Overlap**: add spatial hashing. Partition enemies into grid cells. Each attack
  only checks enemies in overlapping cells. Reduces O(attacks * enemies) to
  O(attacks * enemies_per_cell).
- **Broadcast**: add Area of Interest (AoI). Only send health updates to players
  within visibility radius of the damaged enemy.
