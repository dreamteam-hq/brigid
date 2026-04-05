# Integration and DI Reference

Changes required to existing services and the client to integrate the combat system.
Covers DI registration in `Program.cs`, `EnemyControllerService` additions,
`MapHub` changes, and client-side integration.

All patterns match existing CrystalMagica conventions: DI registration from `Program.cs`,
primary constructors from `MapHub`, `CharacterData` model patterns from `Models/`,
generated `ServerClient`/`GameClient` wrappers from the source generator cascade.

## Table of Contents

- [DI Registration](#di-registration)
- [EnemyControllerService Changes](#enemycontrollerservice-changes)
- [MapHub Changes](#maphub-changes)
- [Client-Side Integration](#client-side-integration)

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

### Why the Registration Must Change

The `AddSingleton` + `AddHostedService(factory)` pattern is necessary because:

- **`AttackService` needs `EnemyControllerService` injected via constructor.**
  The current `AddHostedService<EnemyControllerService>()` registration creates an
  instance owned by the host's lifecycle manager. That instance is not registered in
  the DI container and cannot be resolved by other services.

- **`MapHub` needs `AttackService` injected via constructor.**
  Same problem -- `AddHostedService<T>()` alone creates a separate instance that is
  not retrievable from DI. Only the host holds a reference for lifecycle management.

- **The factory overload resolves to the singleton.**
  `sp => sp.GetRequiredService<T>()` tells the host to use the singleton instance
  already registered in DI, ensuring `MapHub` and the host's lifecycle manager
  both reference the same `AttackService` instance.

### Registration Order

Order the registrations so that dependencies are registered before dependents:

```csharp
// 1. Services with no dependencies on other game services
_ = builder.Services.AddSingleton<MapHub>();             // existing (line 22)
_ = builder.Services.AddSingleton<SocketLogger>();       // existing

// 2. EnemyControllerService (depends on MapHub)
_ = builder.Services.AddSingleton<EnemyControllerService>();
_ = builder.Services.AddHostedService(sp => sp.GetRequiredService<EnemyControllerService>());

// 3. AttackService (depends on MapHub + EnemyControllerService)
_ = builder.Services.AddSingleton<AttackService>();
_ = builder.Services.AddHostedService(sp => sp.GetRequiredService<AttackService>());
```

Order doesn't affect resolution (DI resolves at construction time), but dependency
order makes `Program.cs` self-documenting.

**Verify**: `dotnet build` (no resolution errors), run server (both services log
`ExecuteAsync` entry), inject `AttackService` into `MapHub` (resolves correctly).

---

## EnemyControllerService Changes

The existing service needs three additions for combat support. These are minimal,
non-breaking changes to the existing patrol logic.

### New Types

```csharp
// New types (can be nested in EnemyControllerService or in a separate file)
// EnemySnapshot is a record (immutable value type) for the snapshot pattern
public record EnemySnapshot(Guid Id, Vector2 Position, int Hp, int MaxHp);
```

### EnemyState Class

```csharp
// Inside EnemyControllerService:
private readonly ConcurrentDictionary<Guid, EnemyState> _enemies = new();

public class EnemyState
{
    public CharacterData Character { get; init; }
    public int Hp { get; set; }
    public int MaxHp { get; init; }
    public object Lock { get; } = new();   // per-enemy lock for damage
}
```

**Why wrap**: `CharacterData` is a shared wire model. Adding `Hp`/`MaxHp` to it
would expose server-internal state to clients. `EnemyState` is server-only.

### GetEnemySnapshot

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
```

Snapshots copy live state into immutable records for contention-free iteration.
See `references/thread-safety.md` for the full analysis. For 1000+ enemies,
replace `.ToList()` with a double-buffer (`Interlocked.Exchange`, zero allocation).

### ApplyDamage

```csharp
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

The per-enemy `lock` ensures the read-subtract-clamp-return sequence is atomic.
See `references/thread-safety.md` (Per-Enemy Damage Lock) for why `Interlocked.Add`
is insufficient.

### Patrol Loop Update

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

### Dead Enemy Patrol Guard

**Important**: after combat is integrated, the patrol loop must skip dead enemies.
Without this guard, `EnemyControllerService` will continue moving and broadcasting
position updates for enemies with `Hp <= 0` -- a visible bug where dead enemies
keep patrolling.

```csharp
// In the patrol loop, before updating position:
if (state.Hp <= 0)
    continue;  // dead enemies don't patrol
```

Alternative: remove the enemy from `_enemies` on death in `ApplyDamage`. Cleaner,
but requires callers to handle "enemy no longer exists" within the same tick.

---

## MapHub Changes

```csharp
// Update constructor to inject AttackService:
public class MapHub(SocketLogger socketLogger, AttackService attackService) : IMapHub
{
    // ... existing ConnectedUsers, EnemyCharacter, RelayCharacterAction, JoinRequest ...

    public async Task PerformAttack(AttackIntent intent, ConnectedUser user)
    {
        // Server-authoritative identity -- same pattern as RelayCharacterAction line 23:
        //   action.CharacterId = user.Character.Id;
        intent.AttackerId = user.Character.Id;

        // Server-authoritative position -- DIFFERENT from RelayCharacterAction.
        // RelayCharacterAction TRUSTS client position (line 21):
        //   user.Character.Position = action.Position;
        // PerformAttack OVERWRITES with server-known position (anti-cheat):
        intent.Position = user.Character.Position;

        attackService.RegisterAttack(intent, user);
    }
}
```

### Why PerformAttack Diverges from RelayCharacterAction

Both methods apply server-authoritative identity (`CharacterId` / `AttackerId`).
But they handle position **oppositely**:

| Aspect | `RelayCharacterAction` | `PerformAttack` |
|---|---|---|
| Identity | Server overwrites `action.CharacterId` | Server overwrites `intent.AttackerId` |
| Position | Server **accepts** `action.Position` (stores it as truth) | Server **overwrites** `intent.Position` (ignores client claim) |
| Rationale | Movement is client-authoritative by design | Combat must use server-known position for hitbox accuracy |

This is intentional. `RelayCharacterAction` stores the client-reported position as the
latest truth because movement is client-predicted and the server has no physics simulation
to contradict it. `PerformAttack` overwrites the position because a cheating client could
claim to be adjacent to an enemy while actually being across the map.

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

**Why send Position if the server overwrites it?** Two reasons: (1) `ValidateIntent`
compares `intent.Position` to `user.Character.Position` as an anti-cheat signal,
(2) future server reconciliation may use the client claim to detect desync.

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

### Client-Side Idempotent Death Handling

**Important (Race 3 mitigation)**: the client may receive multiple `EnemyDied` broadcasts
for the same enemy if two players kill it in the same server tick. The `OnEnemyDied`
handler must be idempotent:

```csharp
public void OnEnemyDied(Guid enemyId)
{
    // Guard: ignore if already dead/removed
    if (!_enemyCache.Lookup(enemyId).HasValue)
        return;

    _enemyCache.RemoveKey(enemyId);
    // Play death animation, award XP, etc.
}
```

Without this guard, the client could play the death animation twice, award double XP,
or throw a KeyNotFoundException when removing an already-removed enemy.
