# Networking Implementation

## Table of Contents
- [ConnectionManager (dual-stack TCP/UDP)](#connectionmanager)
- [Socket configuration](#socket-configuration)
- [System.IO.Pipelines for high-throughput TCP](#pipelines)
- [PlayerConnection model](#playerconnection-model)
- [Heartbeat service](#heartbeat-service)
- [Graceful shutdown](#graceful-shutdown)
- [Health checks](#health-checks)
- [Docker deployment](#docker-deployment)

## ConnectionManager

Dual-stack TCP/UDP server with concurrent connection tracking.

```csharp
public sealed class ConnectionManager : IAsyncDisposable
{
    private readonly IOptions<GameServerOptions> _options;
    private readonly ILogger<ConnectionManager> _logger;
    private readonly ConcurrentDictionary<int, PlayerConnection> _connections = new();
    private TcpListener? _tcpListener;
    private Socket? _udpSocket;
    private int _nextPeerId;

    public ConnectionManager(
        IOptions<GameServerOptions> options,
        ILogger<ConnectionManager> logger)
    {
        _options = options;
        _logger = logger;
    }

    public async Task StartListeningAsync(CancellationToken ct)
    {
        // TCP for reliable messages
        _tcpListener = new TcpListener(IPAddress.Any, _options.Value.Port);
        _tcpListener.Start();
        _ = AcceptTcpClientsAsync(ct);

        // UDP for real-time state
        _udpSocket = new Socket(
            AddressFamily.InterNetwork,
            SocketType.Dgram,
            ProtocolType.Udp);
        _udpSocket.Bind(new IPEndPoint(IPAddress.Any, _options.Value.UdpPort));
        _ = ReceiveUdpAsync(ct);

        _logger.LogInformation(
            "Listening on TCP:{TcpPort} UDP:{UdpPort}",
            _options.Value.Port, _options.Value.UdpPort);
    }

    private async Task AcceptTcpClientsAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            var tcpClient = await _tcpListener!.AcceptTcpClientAsync(ct);
            var peerId = Interlocked.Increment(ref _nextPeerId);
            var connection = new PlayerConnection(peerId, tcpClient);
            _connections.TryAdd(peerId, connection);

            _logger.LogInformation("Player {PeerId} connected from {Endpoint}",
                peerId, tcpClient.Client.RemoteEndPoint);

            _ = HandleTcpClientAsync(connection, ct);
        }
    }

    private async Task ReceiveUdpAsync(CancellationToken ct)
    {
        var buffer = GC.AllocateArray<byte>(2048, pinned: true);
        var memory = buffer.AsMemory();

        while (!ct.IsCancellationRequested)
        {
            var result = await _udpSocket!.ReceiveFromAsync(
                memory, SocketFlags.None, new IPEndPoint(IPAddress.Any, 0), ct);

            ProcessUdpMessage(
                memory[..result.ReceivedBytes].Span,
                (IPEndPoint)result.RemoteEndPoint);
        }
    }

    public async ValueTask DisposeAsync()
    {
        _tcpListener?.Stop();
        _udpSocket?.Dispose();
        foreach (var conn in _connections.Values)
            await conn.DisposeAsync();
    }
}
```

## Socket Configuration

```csharp
// TCP socket tuning
tcpClient.NoDelay = true;               // Disable Nagle's -- low latency
tcpClient.ReceiveBufferSize = 65536;     // 64 KB receive buffer
tcpClient.SendBufferSize = 65536;        // 64 KB send buffer
tcpClient.LingerState = new LingerOption(true, 0);  // Immediate close

// UDP socket tuning
udpSocket.SetSocketOption(
    SocketOptionLevel.Socket,
    SocketOptionName.ReceiveBuffer, 262144);  // 256 KB
udpSocket.SetSocketOption(
    SocketOptionLevel.Socket,
    SocketOptionName.SendBuffer, 262144);
udpSocket.Blocking = false;
```

## Pipelines

Zero-copy, backpressure-aware TCP I/O for high-connection-count servers.

```csharp
public async Task ProcessTcpWithPipelines(NetworkStream stream, CancellationToken ct)
{
    var pipe = new Pipe();
    var filling = FillPipeAsync(stream, pipe.Writer, ct);
    var reading = ReadPipeAsync(pipe.Reader, ct);
    await Task.WhenAll(filling, reading);
}

private async Task FillPipeAsync(
    NetworkStream stream, PipeWriter writer, CancellationToken ct)
{
    while (!ct.IsCancellationRequested)
    {
        var memory = writer.GetMemory(4096);
        var bytesRead = await stream.ReadAsync(memory, ct);
        if (bytesRead == 0) break;

        writer.Advance(bytesRead);
        var result = await writer.FlushAsync(ct);
        if (result.IsCompleted) break;
    }
    await writer.CompleteAsync();
}

private async Task ReadPipeAsync(PipeReader reader, CancellationToken ct)
{
    while (!ct.IsCancellationRequested)
    {
        var result = await reader.ReadAsync(ct);
        var buffer = result.Buffer;

        while (TryParseMessage(ref buffer, out var message))
            ProcessGameMessage(message);

        reader.AdvanceTo(buffer.Start, buffer.End);
        if (result.IsCompleted) break;
    }
    await reader.CompleteAsync();
}
```

## PlayerConnection Model

```csharp
public sealed class PlayerConnection : IAsyncDisposable
{
    public int PeerId { get; }
    public string? SessionId { get; set; }
    public TcpClient TcpClient { get; }
    public IPEndPoint? UdpEndpoint { get; set; }
    public ConnectionState State { get; set; }
    public DateTimeOffset ConnectedAt { get; } = DateTimeOffset.UtcNow;
    public DateTimeOffset LastHeartbeat { get; set; } = DateTimeOffset.UtcNow;
    public long LastAcknowledgedTick { get; set; }

    private readonly Channel<byte[]> _outboundTcp;
    private readonly Channel<byte[]> _outboundUdp;

    public PlayerConnection(int peerId, TcpClient tcpClient)
    {
        PeerId = peerId;
        TcpClient = tcpClient;
        _outboundTcp = Channel.CreateBounded<byte[]>(256);
        _outboundUdp = Channel.CreateBounded<byte[]>(64);
    }

    public void EnqueueTcp(byte[] data) =>
        _outboundTcp.Writer.TryWrite(data);

    public void EnqueueUdp(byte[] data) =>
        _outboundUdp.Writer.TryWrite(data);

    public async ValueTask DisposeAsync()
    {
        _outboundTcp.Writer.TryComplete();
        _outboundUdp.Writer.TryComplete();
        TcpClient.Dispose();
    }
}

public enum ConnectionState
{
    Connecting,
    Authenticating,
    Connected,
    InGame,
    Disconnecting,
    Disconnected
}
```

## Heartbeat Service

```csharp
public sealed class HeartbeatService : BackgroundService
{
    private readonly ConnectionManager _connections;
    private readonly IOptions<GameServerOptions> _options;
    private readonly ILogger<HeartbeatService> _logger;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var interval = TimeSpan.FromSeconds(5);
        var timeout = TimeSpan.FromSeconds(_options.Value.GracePeriodSeconds);

        while (!ct.IsCancellationRequested)
        {
            await Task.Delay(interval, ct);
            var now = DateTimeOffset.UtcNow;

            foreach (var conn in _connections.GetAllConnections())
            {
                if (now - conn.LastHeartbeat > timeout)
                {
                    _logger.LogWarning("Player {PeerId} timed out", conn.PeerId);
                    await _connections.DisconnectAsync(conn.PeerId,
                        DisconnectReason.Timeout);
                }
            }
        }
    }
}
```

## Graceful Shutdown

```csharp
public sealed class GameServerService : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // ... game loop runs here ...

        // When stoppingToken is cancelled (SIGTERM, Ctrl+C):
        _logger.LogInformation("Shutdown signal received, draining...");

        // 1. Stop accepting new connections
        await _connections.StopAcceptingAsync();

        // 2. Notify connected players
        await _connections.BroadcastAsync(
            new ServerMessage(MessageType.ServerShutdown, shutdownDelay: 10));

        // 3. Wait for grace period (let matches finish or save state)
        await Task.Delay(TimeSpan.FromSeconds(10));

        // 4. Save persistent state
        await _world.SaveStateAsync();

        // 5. Disconnect all remaining players
        await _connections.DisconnectAllAsync(DisconnectReason.ServerShutdown);
    }
}
```

## Health Checks

```csharp
public sealed class GameServerHealthCheck : IHealthCheck
{
    private readonly TickEngine _tick;
    private readonly ConnectionManager _connections;
    private readonly IOptions<GameServerOptions> _options;

    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken ct)
    {
        var playerCount = _connections.PlayerCount;
        var maxPlayers = _options.Value.MaxPlayers;
        var tickLag = _tick.TickLag;

        if (tickLag > TimeSpan.FromSeconds(1))
            return Task.FromResult(HealthCheckResult.Unhealthy(
                $"Tick loop lagging: {tickLag.TotalMilliseconds:F0}ms behind"));

        if (playerCount >= maxPlayers)
            return Task.FromResult(HealthCheckResult.Degraded(
                $"Server full: {playerCount}/{maxPlayers}"));

        return Task.FromResult(HealthCheckResult.Healthy(
            $"Players: {playerCount}/{maxPlayers}, Tick: {_tick.CurrentTick}"));
    }
}
```

## Docker Deployment

```dockerfile
FROM mcr.microsoft.com/dotnet/runtime:10.0-alpine AS runtime

WORKDIR /app
COPY --from=build /app/publish .

# Game servers need precise timing
ENV DOTNET_GCServer=1
ENV DOTNET_gcConcurrent=1

EXPOSE 7777/tcp 7778/udp

ENTRYPOINT ["dotnet", "GameServer.dll"]
```

Key considerations:
- Use `runtime` image, not `aspnet` -- no HTTP stack needed for pure game servers
- Use `aspnet` image only if the server also hosts SignalR or REST endpoints
- Alpine base for smaller image size (~80MB vs ~200MB)
- Expose both TCP and UDP ports
- Server GC mode (`GCServer=1`) for multi-threaded throughput
- `--network=host` in production for UDP performance (avoids Docker NAT overhead)
