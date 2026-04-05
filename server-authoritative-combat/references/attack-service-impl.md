# AttackService Implementation Reference

Full implementation patterns for the `AttackService` `BackgroundService`, including
tick loop, attack registration, overlap processing, and broadcast helpers.

## AttackService Class

```csharp
public class AttackService(MapHub mapHub, EnemyControllerService enemyService)
    : BackgroundService
{
    private readonly ConcurrentDictionary<Guid, ActiveAttack> _activeAttacks = new();
    private readonly ConcurrentDictionary<Guid, long> _lastAttackTime = new();
    private long _currentTick;

    private const int TickIntervalMs = 100;        // 10 Hz attack tick
    private const int MeleeSwingDurationTicks = 4;  // 400ms active window
    private const int BaseMeleeDamage = 25;
    private const float EnemyHurtboxRadius = 0.5f;
    private const int CooldownTicks = 5;            // 500ms between attacks
    private const float MaxPositionDrift = 2.0f;
```

## Tick Loop

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

## Register Attack (Called from MapHub)

```csharp
public ActiveAttack RegisterAttack(AttackIntent intent, ConnectedUser user)
{
    var (min, max) = HitboxMath.ComputeHitbox(
        intent.Position, intent.Direction, intent.AttackType);

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
    return attack;
}
```

## Process Loop

```csharp
private void ProcessActiveAttacks()
{
    // Snapshot enemy state once per tick (read from EnemyControllerService)
    var enemies = enemyService.GetEnemySnapshot();

    foreach (var attack in _activeAttacks.Values)
    {
        foreach (var enemy in enemies)
        {
            if (attack.HitEnemies.Contains(enemy.Id))
                continue;

            if (!HitboxMath.Overlaps(attack.Min, attack.Max,
                enemy.Position, EnemyHurtboxRadius))
                continue;

            // Hit confirmed
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

## Broadcast Helpers

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
```

## Intent Validation

```csharp
private bool ValidateIntent(AttackIntent intent, ConnectedUser user)
{
    // Player must be connected
    if (!mapHub.ConnectedUsers.ContainsKey(user.SessionId))
        return false;

    // Cooldown check (500ms minimum between attacks)
    if (_lastAttackTime.TryGetValue(user.Character.Id, out var lastTime)
        && _currentTick - lastTime < CooldownTicks)
        return false;

    // Position plausibility (allow 2 units of drift for latency)
    var drift = Vector2.Distance(intent.Position, user.Character.Position);
    if (drift > MaxPositionDrift)
        return false;

    return true;
}
```

## DI Registration

```csharp
// In Program.cs:
builder.Services.AddSingleton<EnemyControllerService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<EnemyControllerService>());
builder.Services.AddSingleton<AttackService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<AttackService>());
```

Both services registered as singletons **and** hosted services so they can be
injected into each other and into `MapHub` while still having their `ExecuteAsync`
driven by the host.
