# Tick Engine Implementation

## Table of Contents
- [TickEngine class](#tickengine-class)
- [BackgroundService game loop](#backgroundservice-game-loop)
- [Configuration options](#configuration-options)

## TickEngine Class

Fixed-timestep game loop using `Stopwatch` for precise timing. Monitors tick budget overruns and recovers from clock spiral.

```csharp
public sealed class TickEngine
{
    private readonly IOptions<GameServerOptions> _options;
    private readonly ILogger<TickEngine> _logger;
    private readonly Stopwatch _stopwatch = new();

    public int TickRate => _options.Value.TickRate;
    public long CurrentTick { get; private set; }

    public TickEngine(IOptions<GameServerOptions> options, ILogger<TickEngine> logger)
    {
        _options = options;
        _logger = logger;
    }

    public async Task RunAsync(GameWorld world, CancellationToken ct)
    {
        var tickInterval = TimeSpan.FromSeconds(1.0 / TickRate);
        var maxBudget = TimeSpan.FromMilliseconds(_options.Value.MaxTickBudgetMs);

        _stopwatch.Start();
        var nextTickTime = _stopwatch.Elapsed;

        while (!ct.IsCancellationRequested)
        {
            var now = _stopwatch.Elapsed;

            if (now < nextTickTime)
            {
                var sleepTime = nextTickTime - now;
                if (sleepTime > TimeSpan.FromMilliseconds(1))
                    await Task.Delay(sleepTime, ct);
                continue;
            }

            var tickStart = _stopwatch.Elapsed;
            world.Tick(CurrentTick);
            var tickDuration = _stopwatch.Elapsed - tickStart;

            if (tickDuration > maxBudget)
            {
                _logger.LogWarning(
                    "Tick {Tick} overran budget: {Duration:F2}ms > {Budget:F2}ms",
                    CurrentTick, tickDuration.TotalMilliseconds,
                    maxBudget.TotalMilliseconds);
            }

            CurrentTick++;
            nextTickTime += tickInterval;

            // Catch up if behind, but cap to prevent spiral
            if (_stopwatch.Elapsed - nextTickTime > tickInterval * 5)
            {
                _logger.LogError("Tick loop fell behind by 5+ ticks, resetting clock");
                nextTickTime = _stopwatch.Elapsed;
            }
        }
    }
}
```

## BackgroundService Game Loop

Wrap the tick engine in a `BackgroundService` for Generic Host integration.

```csharp
public class GameServerService : BackgroundService
{
    private readonly GameWorld _world;
    private readonly TickEngine _tick;
    private readonly ConnectionManager _connections;
    private readonly ILogger<GameServerService> _logger;

    public GameServerService(
        GameWorld world,
        TickEngine tick,
        ConnectionManager connections,
        ILogger<GameServerService> logger)
    {
        _world = world;
        _tick = tick;
        _connections = connections;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Game server starting, tick rate: {TickRate} Hz",
            _tick.TickRate);

        await _connections.StartListeningAsync(stoppingToken);
        await _tick.RunAsync(_world, stoppingToken);
    }
}
```

## Configuration Options

```json
{
  "GameServer": {
    "TickRate": 60,
    "MaxPlayers": 64,
    "Port": 7777,
    "UdpPort": 7778,
    "GracePeriodSeconds": 30,
    "MaxTickBudgetMs": 16.0
  }
}
```

```csharp
public sealed class GameServerOptions
{
    public int TickRate { get; init; } = 60;
    public int MaxPlayers { get; init; } = 64;
    public int Port { get; init; } = 7777;
    public int UdpPort { get; init; } = 7778;
    public int GracePeriodSeconds { get; init; } = 30;
    public double MaxTickBudgetMs { get; init; } = 16.0;
}

// Registration
builder.Services.Configure<GameServerOptions>(
    builder.Configuration.GetSection("GameServer"));
```
