---
name: .NET Game Server Hosting
description: .NET Generic Host patterns for headless game servers — BackgroundService tick loops, DI patterns, graceful shutdown, WebSocket hosting
triggers:
  - game server
  - BackgroundService
  - hosted service
  - server hosting
  - Generic Host
  - tick loop
  - graceful shutdown
category: dotnet
version: "1.0.0"
---

# .NET Game Server Hosting

Domain knowledge for .NET Generic Host patterns specific to headless game servers. NO MCP servers.

## 1. Generic Host for Games

Use `WebApplication.CreateBuilder()` + `AddHostedService<T>()` for background game logic. WebSocket endpoint handles client connections. Wire everything through DI.

**CrystalMagica pattern:** `MapHub` as singleton (owns all map state), `SocketHandler` as singleton (manages WebSocket connections), `BackgroundService` subclasses drive server-controlled entities (patrols, spawns, world ticks).

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<MapHub>();
builder.Services.AddSingleton<SocketHandler>();
builder.Services.AddHostedService<GameLoopService>();
builder.Services.AddHostedService<PatrolService>();
```

## 2. BackgroundService Tick Loop

`ExecuteAsync` with `while (!stoppingToken.IsCancellationRequested)`. Use `Task.Delay` for tick cadence. Never spin-wait. Pass `CancellationToken` on every `await`. For physics-rate ticks: `Stopwatch` + sleep to maintain consistent tick rate regardless of work duration.

```csharp
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    var sw = Stopwatch.StartNew();
    while (!stoppingToken.IsCancellationRequested)
    {
        var tickStart = sw.ElapsedMilliseconds;
        await DoTick(stoppingToken);
        var elapsed = sw.ElapsedMilliseconds - tickStart;
        var delay = Math.Max(0, TickIntervalMs - elapsed);
        await Task.Delay((int)delay, stoppingToken);
    }
}
```

## 3. DI Registration Patterns

- `AddSingleton` for game state (`MapHub`, `ConnectionService`) — one instance, shared across all services
- `AddHostedService` for background loops — started/stopped by the host
- Inject via constructor

**CrystalMagica:** `MapHub` registered as both concrete type and `IMapHub` interface for shared instance.

```csharp
builder.Services.AddSingleton<MapHub>();
builder.Services.AddSingleton<IMapHub>(sp => sp.GetRequiredService<MapHub>());
```

## 4. WebSocket Hosting

`app.UseWebSockets()` + `app.Map("/ws", handler.ProcessSocket)`. `SocketHandler` manages per-connection lifecycle. Each connection gets a `ConnectedUser` with an `Outgoing` channel. Use `BoundedChannel` with `FullMode.DropOldest` to prevent slow clients from blocking the server.

```csharp
var channel = Channel.CreateBounded<ServerMessage>(
    new BoundedChannelOptions(64) { FullMode = BoundedChannelFullMode.DropOldest });
```

Two tasks per connection: one reads from WebSocket, one writes from the channel. When either completes, the connection tears down.

## 5. Graceful Shutdown

`ApplicationStopping` token triggers shutdown sequence. `BackgroundService.StopAsync` called by the host. Drain player connections: send disconnect message, wait for outgoing channels to flush, close WebSockets with `CloseAsync`, timeout after 5s if clients don't disconnect cleanly.

```csharp
lifetime.ApplicationStopping.Register(() =>
{
    _ = connectionService.DisconnectAllAsync(TimeSpan.FromSeconds(5));
});
```

## 6. Health Checks

`app.MapHealthChecks("/health")` for container orchestration. Checks: can accept WebSocket connections, game loop is ticking (last tick within tolerance), memory pressure acceptable. Readiness probe: accepting new players? Liveness probe: process responsive?

## 7. Configuration

`appsettings.json` for tuning (tick rate, max players, patrol parameters). `IOptions<T>` pattern. Environment variable overrides for containers. CrystalMagica today: all consts in code — move to config when there is more than one tunable per concern.

```json
{ "GameServer": { "TickRateMs": 100, "MaxPlayers": 50, "PatrolSpeedMultiplier": 1.0 } }
```
