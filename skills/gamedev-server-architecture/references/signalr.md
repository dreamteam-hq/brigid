# SignalR Game Hub Implementation

## Table of Contents
- [Game lobby hub](#game-lobby-hub)
- [Typed hub clients](#typed-hub-clients)
- [Server setup](#server-setup)
- [MessagePack protocol](#messagepack-protocol)

## Game Lobby Hub

```csharp
public sealed class GameLobbyHub : Hub
{
    private readonly LobbyManager _lobbies;
    private readonly ILogger<GameLobbyHub> _logger;

    public GameLobbyHub(LobbyManager lobbies, ILogger<GameLobbyHub> logger)
    {
        _lobbies = lobbies;
        _logger = logger;
    }

    public async Task CreateLobby(string lobbyName, GameMode mode)
    {
        var playerId = Context.ConnectionId;
        var lobby = _lobbies.Create(lobbyName, mode, playerId);

        await Groups.AddToGroupAsync(playerId, lobby.Id);
        await Clients.Caller.SendAsync("LobbyCreated", lobby);
        _logger.LogInformation("Player {Player} created lobby {Lobby}",
            playerId, lobby.Id);
    }

    public async Task JoinLobby(string lobbyId)
    {
        var playerId = Context.ConnectionId;
        var result = _lobbies.TryJoin(lobbyId, playerId);

        if (!result.Success)
        {
            await Clients.Caller.SendAsync("JoinFailed", result.Reason);
            return;
        }

        await Groups.AddToGroupAsync(playerId, lobbyId);
        await Clients.Group(lobbyId).SendAsync("PlayerJoined", playerId);
    }

    public async Task SetReady(string lobbyId, bool ready)
    {
        var playerId = Context.ConnectionId;
        _lobbies.SetReady(lobbyId, playerId, ready);

        await Clients.Group(lobbyId).SendAsync("ReadyStateChanged",
            playerId, ready);

        if (_lobbies.AllReady(lobbyId))
            await Clients.Group(lobbyId).SendAsync("AllPlayersReady");
    }

    public async Task SendChatMessage(string lobbyId, string message)
    {
        var playerId = Context.ConnectionId;
        await Clients.Group(lobbyId).SendAsync("ChatMessage",
            playerId, message, DateTimeOffset.UtcNow);
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var playerId = Context.ConnectionId;
        var lobbyId = _lobbies.RemovePlayer(playerId);

        if (lobbyId is not null)
            await Clients.Group(lobbyId).SendAsync("PlayerLeft", playerId);
    }
}
```

## Typed Hub Clients

Replace magic string method names with compile-time-safe typed clients.

```csharp
public interface IGameLobbyClient
{
    Task LobbyCreated(LobbyInfo lobby);
    Task JoinFailed(string reason);
    Task PlayerJoined(string playerId);
    Task PlayerLeft(string playerId);
    Task ReadyStateChanged(string playerId, bool ready);
    Task AllPlayersReady();
    Task ChatMessage(string playerId, string message, DateTimeOffset timestamp);
    Task ServerShutdown(int delaySeconds);
}

public sealed class GameLobbyHub : Hub<IGameLobbyClient>
{
    // Now Clients.Caller.LobbyCreated(lobby) is strongly typed
    // Compile-time safety instead of magic strings
}
```

## Server Setup

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSignalR(options =>
{
    options.EnableDetailedErrors = builder.Environment.IsDevelopment();
    options.KeepAliveInterval = TimeSpan.FromSeconds(15);
    options.ClientTimeoutInterval = TimeSpan.FromSeconds(30);
    options.MaximumReceiveMessageSize = 32 * 1024;  // 32 KB
});

// For multi-server deployments, use Redis backplane
// builder.Services.AddSignalR().AddStackExchangeRedis(connectionString);

builder.Services.AddSingleton<LobbyManager>();

var app = builder.Build();
app.MapHub<GameLobbyHub>("/game-lobby");
app.Run();
```

## MessagePack Protocol

Replace JSON with MessagePack for 2-4x smaller payloads and faster serialization.

```csharp
// Server
builder.Services.AddSignalR()
    .AddMessagePackProtocol();

// Client (C#)
var connection = new HubConnectionBuilder()
    .WithUrl("https://server/game-lobby")
    .AddMessagePackProtocol()
    .Build();
```
