---
name: server-authoritative-combat
description: >
  Server-side combat resolution for CrystalMagica -- hitbox validation, damage computation,
  attack deduplication, and continuous collision for melee attacks. Covers the transition from
  pure relay to authoritative game logic: new hub methods, BackgroundService tick loop for
  active attacks, thread-safe state sharing between AttackService and EnemyControllerService,
  and source generator integration. Use this skill whenever the task involves attack, combat,
  damage, hitbox, melee, server authority, PerformAttack, EnemyHealthUpdated, Loop 5, Loop 6,
  knockback, dodge, or any server-side hit detection work.
triggers:
  - attack
  - combat
  - damage
  - hitbox
  - melee
  - server authority
  - PerformAttack
  - EnemyHealthUpdated
  - Loop 5
  - Loop 6
  - knockback
  - dodge
category: gamedev
version: "0.2.0"
---

# Server-Authoritative Combat

How the CrystalMagica server transitions from pure relay to authoritative combat logic. The
server receives attack **intent**, computes hitbox overlaps, resolves damage, deduplicates per
activation, and broadcasts results. Clients never report damage.

This skill is grounded in the actual CrystalMagica codebase as of Loop 2. Every pattern shown
here extends existing code rather than inventing parallel abstractions.

## Quick Reference

### Decision Table: What Lives Where

| Concern | Owner | Why |
|---|---|---|
| Attack input (key press) | Client | Responsiveness -- play animation immediately |
| Attack intent message | Client -> Server | `PerformAttack(AttackIntent)` via `ServerClient.Map` |
| Hitbox construction | Server | Anti-cheat -- server owns geometry |
| Enemy position truth | Server (`EnemyControllerService`) | Already authoritative from Loop 2 |
| Player position truth | Server (`MapHub.ConnectedUsers`) | Updated on every `RelayCharacterAction` |
| Overlap test | Server (`AttackService`) | AABB rect vs enemy position |
| Damage calculation | Server | Server applies formula, never trusts client values |
| Hit result broadcast | Server -> All Clients | `EnemyHealthUpdated(EnemyHealth)` |
| Death broadcast | Server -> All Clients | `EnemyDied(Guid enemyId)` |
| Attack animation | Client (local prediction) | Plays on input; server denial cancels |

### Message Flow

```
Client                         Server                          Other Clients
  |--- PerformAttack ----------->|                                |
  |    (pos, dir, attackType)    |-- validate intent              |
  |                              |-- overwrite identity/position  |
  |                              |-- build hitbox AABB            |
  |                              |-- register ActiveAttack        |
  |                              |== tick loop (100ms) ===========|
  |                              |-- snapshot enemies once        |
  |                              |-- overlap check all enemies    |
  |                              |-- dedup via HitEnemies set     |
  |                              |-- ApplyDamage on hit           |
  |<-- EnemyHealthUpdated -------|--- EnemyHealthUpdated -------->|
  |<-- EnemyDied (if hp <= 0) ---|--- EnemyDied ----------------->|
```

### New Types to Create

| Type | Project | Purpose |
|---|---|---|
| `AttackIntent` | `CrystalMagica/Models` | Wire model: `AttackerId`, `Position`, `Direction`, `AttackType`. Partial class for source-gen serialization. |
| `AttackType` | `CrystalMagica/Models` | Enum: `MeleeSwing` (extensible per weapon) |
| `EnemyHealth` | `CrystalMagica/Models` | Wire model: `EnemyId`, `CurrentHp`, `MaxHp`, `AttackerId`. Partial class. |
| `ActiveAttack` | `CrystalMagica.Server/Services` | Server-only: hitbox AABB, tick born/expires, `HitEnemies` dedup set |
| `AttackService` | `CrystalMagica.Server/Services` | `BackgroundService` -- tick loop, overlap, damage broadcast |

---

## Hub Method Integration

Adding methods to the client hub interfaces triggers the source generator cascade. This is the
single most important step -- get it right and the generator produces all routing, client
wrappers, and message types automatically.

### Step 1: Add to Client Hub Interfaces

**Client -> Server** (`CrystalMagica/ClientHubs/Server/IMapHub.cs`):
```csharp
// Existing methods:
//   Task JoinRequest();
//   Task RelayCharacterAction(CharacterAction action);
// Add:
public Task PerformAttack(AttackIntent intent);
```

**Server -> Client** (`CrystalMagica/ClientHubs/Game/IMapHub.cs`):
```csharp
// Existing methods:
//   void JoinMapResponse(JoinMapResponse mapResponse);
//   void CharacterSpawned(CharacterData characterData);
//   void CharacterDespawned(Guid id);
//   void ReceiveCharacterAction(CharacterAction action);
// Add:
public void EnemyHealthUpdated(EnemyHealth health);
public void EnemyDied(Guid enemyId);
```

### Step 2: Build to Verify Codegen

Build the solution after adding interface methods. The generators produce:

| Generator | What It Emits |
|---|---|
| `MessageTypeGenerator` | `ServerMessageType.Map_PerformAttack`, `GameMessageType.Map_EnemyHealthUpdated`, `GameMessageType.Map_EnemyDied` |
| `HubClientGenerator` | `ServerClient.Map.PerformAttack(AttackIntent)`; `GameClient.Map.EnemyHealthUpdated(EnemyHealth)`, `.EnemyDied(Guid)` |
| `MessageRouterGenerator` | Routes `Map_PerformAttack` bytes to `MapHub.PerformAttack(AttackIntent, ConnectedUser)` |
| `ReceiverHubInterfaceGenerator` | `IMapHub` receiver interface adds `Task PerformAttack(AttackIntent, ConnectedUser)` |
| `ModelSerializationGenerator` | `Serialize`/`Deserialize` on `AttackIntent` and `EnemyHealth` partial classes |

Build errors after this step mean the new model types are missing or the interface method
signatures don't match the generator's expectations. Fix those first.

### Step 3: Implement in MapHub

```csharp
// In MapHub.cs -- same file as existing RelayCharacterAction
public async Task PerformAttack(AttackIntent intent, ConnectedUser user)
{
    // Server-authoritative identity (same pattern as RelayCharacterAction line 23:
    //   action.CharacterId = user.Character.Id)
    intent.AttackerId = user.Character.Id;

    // Server-authoritative position -- INTENTIONAL DIVERGENCE from RelayCharacterAction.
    //
    // RelayCharacterAction TRUSTS client position (line 21):
    //   user.Character.Position = action.Position;   // server ACCEPTS client claim
    //
    // PerformAttack OVERWRITES with server-known position (anti-cheat):
    //   intent.Position = user.Character.Position;   // server IGNORES client claim
    //
    // This ensures hitbox construction uses the server-known position, preventing
    // teleport-attack cheats where a client claims to be next to an enemy while
    // their server-known position is across the map.
    intent.Position = user.Character.Position;

    // Note: RegisterAttack also reads user.Character.Position directly for hitbox
    // construction, making this overwrite defensive. The canonical source of truth
    // for attack origin is RegisterAttack, not intent.Position.
    _attackService.RegisterAttack(intent, user);
}
```

**Position handling: relay vs combat** -- both paths apply server-authoritative identity
(`CharacterId` / `AttackerId`), but they handle position oppositely. `RelayCharacterAction`
stores the client-reported position as truth because movement is client-predicted and the
server has no physics simulation to contradict it. `PerformAttack` overwrites with the
server-known position because combat must be server-authoritative -- a cheating client
could claim to be adjacent to an enemy while actually being across the map. See
`references/integration-and-di.md` for the full comparison table.

MapHub needs an `AttackService` dependency. Add it via primary constructor:
```csharp
public class MapHub(SocketLogger socketLogger, AttackService attackService) : IMapHub
```

---

## Shared Models

Follow existing conventions: partial classes in `CrystalMagica/Models/`, `System.Numerics.Vector2`
for positions, `FaceDirection` enum for direction. The `partial` keyword triggers
`ModelSerializationGenerator` to emit `Serialize`/`Deserialize`.

```csharp
// AttackIntent.cs
using System.Numerics;

namespace CrystalMagica.Models
{
    public enum AttackType { MeleeSwing }

    public partial class AttackIntent
    {
        public Guid AttackerId { get; set; }     // set server-side (like CharacterAction.CharacterId)
        public Vector2 Position { get; set; }
        public FaceDirection Direction { get; set; }
        public AttackType AttackType { get; set; }
    }
}

// EnemyHealth.cs
namespace CrystalMagica.Models
{
    public partial class EnemyHealth
    {
        public Guid EnemyId { get; set; }
        public int CurrentHp { get; set; }
        public int MaxHp { get; set; }
        public Guid AttackerId { get; set; }
    }
}
```

---

## Server-Side Hitbox Computation

The server constructs an AABB in the attacker's facing direction. Pure `System.Numerics`
math -- no Godot physics on the server.

**AABB construction**: `MeleeSwing` = 2 units wide, 1.5 units tall, offset in `FaceDirection`.
The origin point is the attacker's server-known position (not the client-claimed position).

**The 2.5D consideration**: the wire format uses `Vector2` (X = horizontal, Y = depth on
ground plane). Godot maps this to X/Z in 3D (Y is gravity). All overlap checks are 2D on the
XZ plane. Jumping does not affect hit detection -- this is intentional for a side-scrolling
MMO feel.

**Overlap test**: clamp enemy center to AABB, check squared distance against enemy hurtbox
radius (~0.5 units). No `Math.Sqrt` -- squared comparison avoids the cost and the precision
is sufficient for large melee hitboxes.

Keep hitboxes generous. Pixel-perfect collision in a networked game with 50-200ms RTT feels
unfair to the attacker.

For full `HitboxMath` implementation, read `references/attack-service-core.md`.

---

## Active Attack Tracking and Deduplication

```csharp
public class ActiveAttack
{
    public Guid AttackId { get; init; } = Guid.NewGuid();
    public Guid AttackerId { get; init; }
    public Vector2 Min { get; init; }     // AABB lower-left
    public Vector2 Max { get; init; }     // AABB upper-right
    public long TickBorn { get; init; }
    public long TickExpires { get; init; }
    public HashSet<Guid> HitEnemies { get; } = [];   // dedup set
}
```

**Per-attack dedup**: `HitEnemies.Contains(enemyId)` before applying damage. One swing
= one damage instance per enemy, even across multiple tick checks.

**Continuous collision**: the tick loop re-checks all active attacks every tick. Enemies
walking into an already-active hitbox get hit on the next tick. Combined with dedup:
- Tick 5: Enemy A enters hitbox -> damaged, added to `HitEnemies`.
- Tick 6: Enemy A still inside -> skipped (dedup). Enemy B enters -> damaged.
- Tick 8: Attack expires -> removed from `_activeAttacks`.

This is the key difference from "check once on swing start." Without continuous collision,
enemies that walk into an active swing are never hit.

---

## AttackService (BackgroundService)

`AttackService(MapHub, EnemyControllerService) : BackgroundService`

- 10 Hz tick loop (`Stopwatch` + `Task.Delay`, matching the pattern in `EnemyControllerService`).
- Each tick: `ProcessActiveAttacks()` then `PurgeExpiredAttacks()`.
- `RegisterAttack()` called from `MapHub.PerformAttack` -- builds `ActiveAttack` from intent.
- `ProcessActiveAttacks()`: snapshot enemies once per tick, iterate attacks x enemies,
  dedup check, overlap test, apply damage, broadcast `EnemyHealthUpdated` / `EnemyDied`.

DI registration follows the CrystalMagica pattern (singleton + hosted service so the service
can be injected into `MapHub` while also having its `ExecuteAsync` driven by the host):
```csharp
// In Program.cs, alongside existing registrations:
_ = builder.Services.AddSingleton<EnemyControllerService>();
_ = builder.Services.AddHostedService(sp => sp.GetRequiredService<EnemyControllerService>());
_ = builder.Services.AddSingleton<AttackService>();
_ = builder.Services.AddHostedService(sp => sp.GetRequiredService<AttackService>());
```

Note: `EnemyControllerService` is currently registered only as `AddHostedService<>`, which
does not expose it for injection. The change above registers it as a singleton first, then
wires the hosted service from the same instance. This is required so `AttackService` can
inject `EnemyControllerService` for the snapshot/damage methods.

For full `AttackService` implementation, tick loop, validation, and broadcast helpers,
read `references/attack-service-core.md`. For DI registration, `EnemyControllerService` changes,
`MapHub` changes, and client-side integration, read `references/integration-and-di.md`.

---

## Thread Safety

| State | Writer | Reader | Mechanism |
|---|---|---|---|
| `MapHub.ConnectedUsers` | `MapHub` (join), `ConnectionService` (leave) | `AttackService` (broadcast) | `ConcurrentDictionary` -- already thread-safe |
| `_activeAttacks` | `MapHub.PerformAttack` (register), `AttackService` (purge) | `AttackService` (tick loop) | `ConcurrentDictionary<Guid, ActiveAttack>` |
| Enemy positions | `EnemyControllerService` (patrol tick) | `AttackService` (overlap check) | Snapshot pattern |
| Enemy HP | `AttackService` (damage) | Both services | Per-enemy `lock` |

**Snapshot pattern**: `EnemyControllerService.GetEnemySnapshot()` returns a list copy.
`AttackService` reads once per tick, iterates without contention. This is critical --
holding a lock across the entire attack x enemy loop would serialize all combat.

**Damage lock**: `lock` on a per-enemy object, not a global lock. Allows parallel damage
to different enemies. `Interlocked.Add` is an alternative for simple subtraction, but a
lock is clearer when HP clamping and death checks are involved.

For detailed thread safety analysis, shared state map, and the snapshot pattern
implementation, read `references/thread-safety.md`.

---

## Evolving EnemyControllerService

Loop 2's `EnemyControllerService` has a single `CharacterData EnemyCharacter` field on
`MapHub`. To support combat, the service needs:

1. **HP tracking**: new `EnemyState` class wrapping `CharacterData` + `Hp`/`MaxHp`.
2. **Snapshot method**: `GetEnemySnapshot()` returning `IReadOnlyList<EnemySnapshot>`.
3. **Damage method**: `ApplyDamage(Guid enemyId, int damage) -> int` returning new HP.
4. **Death handling**: remove dead enemy from state, broadcast stop-patrol if needed.

For the single-enemy case (Loop 5), this is a one-element dictionary. The pattern scales
to N enemies without architectural change.

---

## Intent Validation

Validate before registering the attack. Reject early, reject cheap.

| Check | Reject If | Why |
|---|---|---|
| Connected | Player not in `ConnectedUsers` | Dead/disconnected players cannot attack |
| Cooldown | < 500ms since last attack (5 ticks at 10 Hz) | Prevents spam / speed hacks |
| Position drift | > 2 units from server-known position | Position tampering |
| Attack type | Not a valid `AttackType` enum value | Malformed packet |

Position drift uses squared distance to avoid `Math.Sqrt`:
```csharp
var delta = intent.Position - user.Character.Position;
if (delta.LengthSquared() > MaxPositionDrift * MaxPositionDrift)
    return false;
```

---

## Tick Rate Selection

| Concern | Rate | Rationale |
|---|---|---|
| `EnemyControllerService` patrol | Existing `Task.Delay(2s)` | Low-frequency, works as-is |
| `AttackService` overlap checks | 10 Hz (100ms) | 3-5 checks per 400ms swing is sufficient |
| Future: physics tick | 20-30 Hz | When projectiles or knockback arrive |

10 Hz is deliberate. Melee AABB checks against large hitboxes do not need 60 Hz.
Higher rates waste CPU without improving the player experience for melee.

---

## Client-Side Prediction

Client plays the attack animation immediately on input (cosmetic prediction). Server sends
damage results asynchronously. No client-side hit detection. No local HP modification.

```csharp
// In LocalPlayerCharacterVM -- client side:
public void PerformAttack(FaceDirection direction)
{
    AttackAnimationRequested?.Invoke(direction);      // play immediately
    _serverClient.Map.PerformAttack(new AttackIntent  // send intent
    {
        Position = Position,
        Direction = direction,
        AttackType = AttackType.MeleeSwing
    });
}
```

The `_serverClient.Map.PerformAttack` call uses the generated `ServerClient` wrapper, which
serializes `AttackIntent` via the generated `Serialize` method and writes it to the
`ConnectedUser.Outgoing` channel as a binary WebSocket frame.

---

## Lag Compensation for Melee

**Why melee does not need server rewind**: hitboxes are large (2+ units), attack windows
are long (300-500ms / 3-5 ticks), and continuous collision naturally absorbs < 200ms RTT.
An enemy that was at position X when the player pressed attack will still be within the
hitbox window by the time the server processes the intent.

**When to add rewind**: ranged/hitscan attacks, player complaints at > 150ms latency,
or competitive PvP melee. For PvE melee against server-controlled enemies, continuous
collision is sufficient and dramatically simpler.

---

## Scaling to Multiple Enemies

| Current (Loop 2) | Target (Loop 5+) |
|---|---|
| `MapHub.EnemyCharacter` (single `CharacterData`) | `ConcurrentDictionary<Guid, EnemyState>` inside `EnemyControllerService` |
| No HP | `EnemyState { CharacterData, Hp, MaxHp }` |
| Broadcast to all | Broadcast to all (AoI comes later) |

The `ActiveAttack` / `HitEnemies` / snapshot pattern supports N enemies with zero
architectural change. For > 100 enemies in a zone, add spatial hashing to the broad phase
(grid cells, test only attacks overlapping the same cells as enemies).

---

## Anti-Patterns

| Anti-Pattern | Tempting Because | Why It Fails |
|---|---|---|
| Client reports damage | Simpler server code | Any client can claim arbitrary damage -- game over |
| Client hitbox, server validates | Client has Godot physics | Client can lie about overlap results |
| One check per attack (no continuous) | Simpler logic | Enemies walking into active swings are never hit |
| Global lock for enemy state | Simple correctness | Serializes all combat through one lock -- 50 players attacking different enemies block each other |
| 60 Hz attack ticks | Higher fidelity | Wastes CPU; 10 Hz is sufficient for large melee AABB |
| No dedup | Overlap "just works" | Same enemy takes damage every tick (4x damage at 10 Hz over 400ms window) |
| Allocating per tick | Simpler code | GC pressure kills server perf -- reuse snapshots, pool broadcast messages |
| Blocking tick loop with I/O | Persistence seems important | Stalls all combat processing -- queue persistence to a separate task |

---

## Implementation Checklist

### Server -- Models and Interfaces
1. Create `AttackType` enum and `AttackIntent` partial class in `CrystalMagica/Models/`
2. Create `EnemyHealth` partial class in `CrystalMagica/Models/`
3. Add `PerformAttack` to `ClientHubs/Server/IMapHub.cs`
4. Add `EnemyHealthUpdated`, `EnemyDied` to `ClientHubs/Game/IMapHub.cs`
5. Build solution -- verify source generators produce expected types

### Server -- Services
6. Create `ActiveAttack` in `CrystalMagica.Server/Services/`
7. Add `EnemyState`, `GetEnemySnapshot()`, `ApplyDamage()` to `EnemyControllerService`
8. Create `AttackService` with tick loop, registration, overlap, broadcast
9. Update `MapHub` with `PerformAttack` implementation
10. Update `Program.cs` DI registration (singleton + hosted service pattern)

### Server -- Race Condition Guards
11. **Dead enemy patrol guard (Race 4)**: add `if (state.Hp <= 0) continue;` in `EnemyControllerService` patrol loop. Without this, dead enemies continue patrolling and broadcasting movement after death -- a visible bug.
12. **Idempotent death broadcast (Race 3)**: two players killing the same enemy in the same tick produces two `EnemyDied` broadcasts. The client `OnEnemyDied` handler must guard against double-removal (e.g., check `_enemyCache.Lookup(enemyId).HasValue` before removing). Without this, clients may throw `KeyNotFoundException`, play the death animation twice, or award double XP.

### Client
13. Add client-side `PerformAttack` call in `LocalPlayerCharacterVM`
14. Implement `OnEnemyHealthUpdated` handler -- update enemy VM HP, trigger health bar animation
15. Implement `OnEnemyDied` handler -- remove from `SourceCache`, play death animation (idempotent, see item 12)

### Verification
16. Test: single attack -> single enemy -> health update broadcast
17. Test: kill enemy -> verify patrol stops (Race 4 guard)
18. Test: two simultaneous kills -> verify client handles duplicate death gracefully (Race 3 guard)

---

## Reference Material

- `references/attack-service-core.md` -- `AttackService` class, `HitboxMath`, tick loop, registration, validation, process loop, broadcast helpers
- `references/integration-and-di.md` -- DI registration in `Program.cs`, `EnemyControllerService` changes (`EnemyState`, snapshot, damage, dead patrol guard), `MapHub` changes (position divergence), client-side integration (idempotent death handling)
- `references/thread-safety.md` -- shared state analysis, snapshot pattern, damage locks, race conditions, scaling

## Cross-References

| Skill | When to Load |
|---|---|
| `mmo-action-relay` | Action relay fundamentals, validation pipeline, broadcast patterns |
| `gamedev-multiplayer` | Client-side prediction, entity interpolation, lag compensation theory |
| `gamedev-server-architecture` | BackgroundService tick loops, GC tuning, thread architecture |
| `dotnet-gameserver-hosting` | DI registration, WebSocket hosting, graceful shutdown |
| `crystal-magica-architecture` | Source generator cascade, hub interfaces, MVVM pattern |
