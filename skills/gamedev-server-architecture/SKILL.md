---
name: gamedev-server-architecture
description: >
  C# headless game server architecture — TCP/UDP socket management, connection
  pooling, tick-rate loops, .NET hosting model, SignalR real-time patterns,
  headless server design, and deployment. Load when building dedicated game
  servers in C#, designing server tick loops, implementing real-time networking
  with .NET, or when the user mentions "game server", "headless server",
  "tick rate", "SignalR", "Kestrel game server", "UDP socket", "connection
  pooling", or "server-authoritative".
---

# C# Game Server Architecture

Build headless .NET game servers using Generic Host, fixed-timestep tick loops, dual TCP/UDP networking, and SignalR for lobbies. This skill covers the server side -- for client-side Godot networking, load `gamedev-multiplayer` instead.

## Decision Framework

Before writing code, resolve these architectural choices.

### Dedicated vs Listen Server

Choose dedicated when you need server authority, anti-cheat, 24/7 availability, or 16+ players. Choose listen (player-hosted) for casual co-op with fewer than 8 players where infrastructure cost matters. A hybrid approach -- .NET dedicated server for game logic, Godot/Unity clients for rendering -- is the gold standard for competitive multiplayer.

### Protocol Selection

Use TCP for reliable, infrequent operations: authentication, chat, inventory changes, hit registration. Use UDP for latency-sensitive, frequent state: position/rotation sync, input commands, voice chat. Most game servers need both -- a dual-stack architecture with TCP on one port and UDP on another.

### SignalR vs Raw Sockets

Use SignalR for lobby systems, matchmaking, chat, turn-based games, and leaderboard updates -- anywhere reliability and built-in reconnection matter more than raw latency. Use raw UDP for real-time action games at 60Hz where SignalR's overhead and head-of-line blocking are unacceptable. Many games use both: SignalR for lobby/chat, raw UDP for gameplay.

### Tick Rate Selection

| Game Type | Tick Rate | Rationale |
|-----------|-----------|-----------|
| Fast FPS / action | 60-128 Hz | Precise hit detection, smooth movement |
| MOBA / RTS | 20-30 Hz | Lower precision acceptable, more entities |
| MMO / persistent world | 10-20 Hz | Many entities, bandwidth constrained |
| Turn-based | Event-driven | No tick loop needed |

Always use fixed-tick simulation. If bandwidth is a concern, vary the network send rate, not the simulation rate.

## .NET Hosting Model

Build game servers on `Microsoft.Extensions.Hosting` (Generic Host) rather than raw console apps. Generic Host gives you lifecycle management (graceful SIGTERM handling), dependency injection, structured logging, configuration binding, and `BackgroundService` for the game loop -- all without reinventing infrastructure.

```csharp
var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddSingleton<GameWorld>();
builder.Services.AddSingleton<TickEngine>();
builder.Services.AddSingleton<ConnectionManager>();
builder.Services.AddHostedService<GameServerService>();
builder.Services.AddHostedService<HeartbeatService>();

var host = builder.Build();
await host.RunAsync();
```

Use the options pattern for server configuration (tick rate, max players, ports, grace period). Bind from `appsettings.json` via `builder.Services.Configure<GameServerOptions>(...)`.

Use `runtime` Docker images (not `aspnet`) for pure headless servers. Switch to `aspnet` only if hosting SignalR or REST endpoints. Enable Server GC (`DOTNET_GCServer=1`) and concurrent GC for multi-threaded throughput. Expose both TCP and UDP ports. Use `--network=host` in production to avoid Docker NAT overhead for UDP.

## Tick-Rate Architecture

Implement the game loop as a `BackgroundService` with a `Stopwatch`-based fixed timestep. The tick engine runs simulation at a constant rate, decoupled from wall-clock time, ensuring deterministic physics regardless of server load.

### Tick Budget

For a 60 Hz server (16.67ms per tick), budget roughly:

| Phase | Budget | Purpose |
|-------|--------|---------|
| Input processing | 1-2ms | Dequeue and validate client inputs |
| Game simulation | 4-8ms | Physics, AI, game logic |
| State diffing | 1-2ms | Calculate deltas since last tick |
| Snapshot broadcast | 2-4ms | Serialize and send to clients |
| Headroom | 2-4ms | GC pauses, load variance |

Always measure tick duration and log warnings when ticks overrun budget. Implement clock recovery: if the loop falls behind by 5+ ticks, reset the clock rather than spiraling.

For complete tick engine implementation, read `references/tick-engine.md`.

## TCP/UDP Socket Management

### Dual-Stack Setup

Create a `ConnectionManager` that starts both a `TcpListener` and a UDP `Socket`. Accept TCP connections asynchronously and assign peer IDs. Receive UDP datagrams into pre-allocated pinned buffers (`GC.AllocateArray<byte>(size, pinned: true)`) to avoid GC pressure.

### Socket Tuning

For TCP: disable Nagle's algorithm (`NoDelay = true`), set 64KB send/receive buffers, use `LingerOption(true, 0)` for immediate close. For UDP: set 256KB send/receive buffers, use non-blocking mode.

### High-Throughput TCP with Pipelines

For servers handling many concurrent TCP connections, use `System.IO.Pipelines` for zero-copy, backpressure-aware I/O instead of raw `NetworkStream.ReadAsync`.

For complete socket and pipeline implementations, read `references/networking.md`.

## Connection Lifecycle

Model player connections with a state machine:

```
CONNECT (TCP) -> AUTHENTICATE -> UDP_ASSOCIATE -> LOBBY -> JOIN_GAME -> IN_GAME -> DISCONNECT
                                                                           |
                                                                      GRACE_PERIOD -> RECONNECT
                                                                           |
                                                                        TIMEOUT -> CLEANUP
```

Each `PlayerConnection` tracks: peer ID, session ID, TCP client, UDP endpoint, connection state, last heartbeat timestamp, last acknowledged tick, and outbound message channels (bounded `Channel<byte[]>` for both TCP and UDP).

Run a `HeartbeatService` as a separate `BackgroundService` that checks connections every 5 seconds and disconnects players who exceed the grace period timeout.

### Graceful Shutdown

On SIGTERM: stop accepting new connections, broadcast shutdown warning to all players, wait a grace period for matches to finish, persist game state, then disconnect remaining players.

## Binary Serialization

### Message Format

Use a compact wire format: `[MessageType:1][Length:2][Payload:variable]`. Define message types as a `byte` enum with ranges for client-to-server (0x01-0x0F), server-to-client (0x10-0x1F), and bidirectional (0x20+).

### Serialization Approach

Use `BinaryPrimitives` for zero-allocation serialization. Quantize values where precision allows -- rotation as a single byte (256 directions = 1.4 degree precision) reduces an entity state update from ~80 bytes (JSON) to ~14 bytes (binary).

### Delta Compression

Track last-sent state per entity per client. Compute dirty flags for changed fields and transmit only the deltas. A position-only update drops from 14 bytes to 9 bytes; unchanged entities cost 0 bytes.

For serialization and delta compression implementations, read `references/serialization.md`.

## SignalR for Lobbies and Chat

When using SignalR for lobby systems, matchmaking, and chat:

- Use typed hub clients (`Hub<IGameLobbyClient>`) for compile-time safety instead of magic string method names
- Use SignalR Groups for lobby membership -- `Groups.AddToGroupAsync` / `Clients.Group(id).SendAsync`
- Replace JSON protocol with MessagePack (`AddMessagePackProtocol()`) for 2-4x smaller payloads
- Set `KeepAliveInterval` to 15s and `ClientTimeoutInterval` to 30s
- Cap `MaximumReceiveMessageSize` at 32KB
- For multi-server deployments, add Redis backplane (`AddStackExchangeRedis`)

For hub implementation patterns, read `references/signalr.md`.

## GC Tuning and Performance

### GC Configuration

Enable Server GC and Concurrent GC in the `.csproj`. Server GC uses multiple collection threads for higher throughput. Concurrent GC runs Gen2 collections without stopping all threads. Use Workstation GC only for servers with fewer than 4 cores.

### Reducing GC Pressure

- Rent buffers from `ArrayPool<byte>.Shared` instead of allocating
- Use `Span<T>` / `Memory<T>` for zero-copy parsing
- Use `ObjectPool<T>` from `Microsoft.Extensions.ObjectPool` for message objects
- Prefer value types (structs) for components, vectors, and small messages
- Use `FrozenDictionary` for static config/lookup tables
- Use `stackalloc` for small temporary buffers

### Thread Architecture

Keep the game loop single-threaded. Run network receive and send on separate async tasks. Run heartbeat/housekeeping at lower priority. Only parallelize simulation if entity batches are independent (ECS system-level parallelism).

## Anti-Patterns

**Allocating per-tick.** Creating `new List<byte[]>` or `new byte[]` every tick generates massive GC pressure. Rent from `ArrayPool`, reuse collections, pool message objects.

**Blocking the tick loop.** Never call synchronous I/O (database reads, file I/O) inside the tick. Queue persistence operations and flush asynchronously on a separate task.

**Single-threaded network I/O.** Reading and writing sockets on the same thread as the game loop means network stalls block simulation. Use async I/O on separate tasks, with `ConcurrentQueue` or `Channel` to pass messages to/from the tick loop.

**No tick budget monitoring.** Running without measuring tick duration means overruns go undetected. The server silently falls behind, clients rubber-band, and no alert fires. Always measure and log.

**Hardcoded tick rate.** Magic numbers like `Thread.Sleep(16)` drift, can't be tuned per-deployment, and don't account for tick processing time. Use `Stopwatch`-based timing with configurable tick rate from options.

**Using `Thread.Sleep` for timing.** `Thread.Sleep` has ~15ms resolution on Windows. Use `Stopwatch` + `Task.Delay` with a 1ms threshold for the game loop.

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-multiplayer` | Client-side networking, state sync, lag compensation, Godot multiplayer API |
| `gamedev-ecs` | Entity Component System architecture for server-side game state |
| `dotnet-architecture` | Clean Architecture, DDD patterns for server design |
| `dotnet-dependency-injection` | DI patterns for game server services |
| `dotnet-error-handling` | Server-side error handling and resilience |
| `dotnet-logging` | Structured logging for game servers |
