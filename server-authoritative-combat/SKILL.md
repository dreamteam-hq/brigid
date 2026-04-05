---
name: server-authoritative-combat
description: >
  Server-side combat resolution for CrystalMagica — hitbox validation, damage computation,
  attack deduplication, and continuous collision for melee attacks. Covers the transition from
  pure relay to authoritative game logic: new hub methods, BackgroundService tick loop for
  active attacks, thread-safe state sharing between AttackService and EnemyControllerService,
  and source generator integration. Triggers: attack, combat, damage, hitbox, melee, server authority,
  PerformAttack, EnemyHealthUpdated, Loop 5.
scope: consumer
metadata:
  category: reference
  tags:
    domain: [gamedev, multiplayer, networking]
    depth: intermediate
    pipeline: build
---

# Server-Authoritative Combat

How the CrystalMagica server transitions from pure relay to authoritative combat logic. The
server receives attack **intent**, computes hitbox overlaps, resolves damage, deduplicates per
activation, and broadcasts results. Clients never report damage.

## Quick Reference

### Decision Table: What Lives Where

| Concern | Owner | Why |
|---|---|---|
| Attack input (key press) | Client | Responsiveness -- play animation immediately |
| Attack intent message | Client -> Server | `PerformAttack(position, direction, attackType)` |
| Hitbox construction | Server | Anti-cheat -- server owns geometry |
| Enemy position truth | Server (`EnemyControllerService`) | Already authoritative from Loop 2 |
| Player position truth | Server (`MapHub.ConnectedUsers`) | Updated on every `RelayCharacterAction` |
| Overlap test | Server (`AttackService`) | AABB rect vs enemy position |
| Damage calculation | Server | Server applies formula, never trusts client values |
| Hit result broadcast | Server -> All Clients | `EnemyHealthUpdated(enemyId, newHp, attackerId)` |
| Death broadcast | Server -> All Clients | `EnemyDied(enemyId, attackerId)` |
| Attack animation | Client (local prediction) | Plays on input; server denial cancels it |

### Message Flow

```
Client                         Server                          Other Clients
  |--- PerformAttack ----------->|                                |
  |    (pos, dir, attackType)    |-- validate, build hitbox       |
  |                              |-- register ActiveAttack        |
  |                              |== tick loop (100ms) ===========|
  |                              |-- overlap check all enemies    |
  |                              |-- dedup via HitEnemies set     |
  |<-- EnemyHealthUpdated -------|--- EnemyHealthUpdated -------->|
  |<-- EnemyDied (if hp <= 0) ---|--- EnemyDied ----------------->|
```

### New Types

| Type | Project | Purpose |
|---|---|---|
| `AttackIntent` | Shared/Models | Wire model: `Position`, `Direction`, `AttackType` |
| `AttackType` | Shared/Models | Enum: `MeleeSwing` (extensible) |
| `ActiveAttack` | Server/Services | Hitbox rect, tick born/expires, `HitEnemies` set |
| `EnemyHealth` | Shared/Models | Wire model: `EnemyId`, `CurrentHp`, `MaxHp`, `AttackerId` |
| `AttackService` | Server/Services | `BackgroundService` -- tick loop, overlap, damage |

---

## Hub Method Integration

### Step 1: Add to Client Hub Interfaces

Adding methods triggers source generators (`HubClientGenerator`, `MessageRouterGenerator`,
`MessageTypeGenerator`, `ReceiverHubInterfaceGenerator`).

**Client -> Server** (`ClientHubs.Server.IMapHub`):
```csharp
public Task PerformAttack(AttackIntent intent);
```

**Server -> Client** (`ClientHubs.Game.IMapHub`):
```csharp
public void EnemyHealthUpdated(EnemyHealth health);
public void EnemyDied(Guid enemyId);
```

### Step 2: Implement in MapHub

```csharp
public async Task PerformAttack(AttackIntent intent, ConnectedUser user)
{
    intent.Position = user.Character.Position;   // server-authoritative
    intent.AttackerId = user.Character.Id;       // same pattern as RelayCharacterAction
    _attackService.RegisterAttack(intent, user); // damage comes from tick loop
}
```

### Step 3: Source Generator Cascade

| Generator | What Changes |
|---|---|
| `MessageTypeGenerator` | `ServerMessageType.Map_PerformAttack`, `GameMessageType.Map_EnemyHealthUpdated`, `GameMessageType.Map_EnemyDied` |
| `HubClientGenerator` | `ServerClient.Map.PerformAttack`; `GameClient.Map.EnemyHealthUpdated`, `.EnemyDied` |
| `MessageRouterGenerator` | Routes `Map_PerformAttack` to `MapHub.PerformAttack` |
| `ReceiverHubInterfaceGenerator` | `IMapHub` receiver adds `PerformAttack(AttackIntent, ConnectedUser)` |

Build after adding interface methods to verify codegen before writing implementation.

---

## Shared Models

```csharp
public partial class AttackIntent           // partial -> ModelSerializationGenerator
{
    public Guid AttackerId { get; set; }    // set server-side, like CharacterAction.CharacterId
    public Vector2 Position { get; set; }
    public FaceDirection Direction { get; set; }
    public AttackType AttackType { get; set; }
}

public enum AttackType { MeleeSwing }       // one to start, extend per weapon

public partial class EnemyHealth
{
    public Guid EnemyId { get; set; }
    public int CurrentHp { get; set; }
    public int MaxHp { get; set; }
    public Guid AttackerId { get; set; }
}
```

---

## Server-Side Hitbox Computation

The server constructs an AABB in the attacker's facing direction. Pure `System.Numerics`
math -- no Godot physics on the server.

**AABB construction**: `MeleeSwing` = 2 units wide, 1.5 units tall, offset in
`FaceDirection`. Overlap test: clamp enemy center to AABB, check squared distance
against enemy hurtbox radius (~0.5 units). No `Math.Sqrt`. Keep hitboxes generous --
pixel-perfect in a networked game feels unfair.

**The 2.5D consideration**: wire format uses `Vector2` (X = horizontal, Y = depth on
ground plane). Godot maps this to X/Z in the 3D world (Y is gravity). All overlap
checks are 2D. Jumping does not affect hit detection.

For full `HitboxMath.ComputeHitbox` and `HitboxMath.Overlaps` implementations, read
`references/attack-service-impl.md`.

---

## Active Attack Tracking and Deduplication

```csharp
public class ActiveAttack
{
    public Guid AttackId { get; init; } = Guid.NewGuid();
    public Guid AttackerId { get; init; }
    public Vector2 Min { get; init; }
    public Vector2 Max { get; init; }
    public long TickBorn { get; init; }
    public long TickExpires { get; init; }
    public HashSet<Guid> HitEnemies { get; } = [];  // dedup set
}
```

**Per-attack dedup**: `HitEnemies.Contains(enemyId)` before applying damage. One swing
= one damage per enemy, even across multiple tick checks.

**Continuous collision**: tick loop re-checks all active attacks every tick. Enemies
walking into an already-active hitbox get hit. Combined with dedup:
- Tick 5: Enemy A enters -> damaged, added to set.
- Tick 6: Enemy A still inside -> skipped. Enemy B enters -> damaged.
- Tick 8: Attack expires -> removed.

---

## AttackService (BackgroundService)

`AttackService(MapHub, EnemyControllerService) : BackgroundService`

- 10 Hz tick loop (`Stopwatch` + `Task.Delay`).
- Each tick: `ProcessActiveAttacks()` then `PurgeExpiredAttacks()`.
- `RegisterAttack()` called from `MapHub.PerformAttack` -- builds `ActiveAttack` from intent.
- `ProcessActiveAttacks()`: snapshot enemies once per tick, iterate attacks x enemies,
  dedup check, overlap test, apply damage via `EnemyControllerService.ApplyDamage()`,
  broadcast `EnemyHealthUpdated` / `EnemyDied`.

DI registration (singleton + hosted service, matching CrystalMagica pattern):
```csharp
builder.Services.AddSingleton<AttackService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<AttackService>());
```

For full implementation, read `references/attack-service-impl.md`.

---

## Thread Safety

| State | Writer | Reader | Mechanism |
|---|---|---|---|
| `MapHub.ConnectedUsers` | `MapHub` | `AttackService` | `ConcurrentDictionary` |
| `_activeAttacks` | `MapHub` (register), `AttackService` (purge) | `AttackService` | `ConcurrentDictionary` |
| Enemy positions | `EnemyControllerService` | `AttackService` | Snapshot pattern |
| Enemy HP | `AttackService` | Both services | Per-enemy `lock` |

**Snapshot pattern**: `EnemyControllerService.GetEnemySnapshot()` returns a list copy.
`AttackService` reads once per tick, iterates without contention.

**Damage**: `lock (_enemies[enemyId])` -- per-enemy, not global. Allows parallel damage
to different enemies.

For full thread safety analysis, read `references/thread-safety.md`.

---

## Tick Rate Selection

| Concern | Rate | Rationale |
|---|---|---|
| `EnemyControllerService` patrol | Existing (Task.Delay) | Low-frequency, works as-is |
| `AttackService` overlap checks | 10 Hz (100ms) | 3-5 checks per 400ms swing is sufficient |
| Future: physics tick | 20-30 Hz | When projectiles or knockback arrive |

10 Hz is deliberate. Melee AABB checks against large hitboxes do not need 60 Hz.

---

## Intent Validation

| Check | Reject If | Why |
|---|---|---|
| Connected | Player not in `ConnectedUsers` | Dead/disconnected players cannot attack |
| Cooldown | < 500ms since last attack | Prevents spam / speed hacks |
| Position drift | > 2 units from server-known position | Position tampering |
| Attack type | Not a valid `AttackType` enum value | Malformed packet |

---

## Client-Side Prediction

Client plays attack animation on input (cosmetic prediction). Server sends damage
results, not confirmations. No client-side hit detection. No local HP modification.

```csharp
// In LocalPlayerCharacterVM:
public void PerformAttack(FaceDirection direction)
{
    AttackAnimationRequested?.Invoke(direction);     // play immediately
    _serverClient.Map.PerformAttack(new AttackIntent // send intent
    {
        Position = Position,
        Direction = direction,
        AttackType = AttackType.MeleeSwing
    });
}
```

---

## Lag Compensation for Melee

**Why melee does not need server rewind**: hitboxes are large (2+ units), attack windows
are long (300-500ms / 3-5 ticks), and continuous collision naturally absorbs < 200ms RTT.

**When to add rewind**: ranged/hitscan attacks, player complaints at > 150ms latency,
or competitive PvP melee. For PvE melee against server-controlled enemies, continuous
collision is sufficient and dramatically simpler.

---

## Scaling to Multiple Enemies

| Current (Loop 2) | Future (Loop 6+) |
|---|---|
| Single `CharacterData EnemyCharacter` | `ConcurrentDictionary<Guid, EnemyState>` |
| No HP | `EnemyState.Hp` / `MaxHp` |
| Broadcast to all | Interest-based (AoI) |

The `ActiveAttack` / `HitEnemies` / snapshot pattern supports N enemies with zero
architectural change. For > 100, add spatial hashing to the broad phase.

---

## Anti-Patterns

| Anti-Pattern | Tempting Because | Why It Fails |
|---|---|---|
| Client reports damage | Simpler server | Any client can claim arbitrary damage |
| Client hitbox, server validates | Client has Godot physics | Client can lie about overlap results |
| One check per attack (no continuous) | Simpler | Enemies walking into active swings never hit |
| Global lock for enemy state | Simple correctness | Serializes all combat through one lock |
| 60 Hz attack ticks | Higher fidelity | Wastes CPU; 10 Hz is sufficient for melee AABB |
| No dedup | Overlap "just works" | Same enemy takes damage every tick (4x at 10 Hz) |

---

## Reference Material

- `references/attack-service-impl.md` -- full `AttackService`, tick loop, validation, DI
- `references/thread-safety.md` -- shared state map, snapshot pattern, damage locks

## Cross-References

| Skill | When to Load |
|---|---|
| `mmo-action-relay` | Action relay fundamentals, validation pipeline, broadcast patterns |
| `gamedev-multiplayer` | Client-side prediction, entity interpolation, lag compensation theory |
| `gamedev-server-architecture` | BackgroundService tick loops, GC tuning, thread architecture |
| `dotnet-gameserver-hosting` | DI registration, WebSocket hosting, graceful shutdown |
| `gamedev-2d-ai` | Enemy state machines, aggro tables, server-authoritative AI |
| `crystal-magica-architecture` | Source generator cascade, hub interfaces, MVVM pattern |
