---
name: MMO Zone Architecture
description: MMO zone architecture — spatial partitioning, area of interest, zone transitions, instancing, load balancing
triggers:
  - zone
  - zone architecture
  - area of interest
  - spatial partitioning
  - instancing
  - zone transition
  - world architecture
category: gamedev
version: "1.0.0"
---

# MMO Zone Architecture

Zone architecture determines how a persistent world is partitioned across servers, how players move between partitions, and how the server selects which entities each player needs to see. This skill covers the full progression from CrystalMagica's current single-zone model through AoI filtering, instancing, and cross-zone communication — all grounded in ASP.NET patterns.

## Current State: Single-Zone MapHub

CrystalMagica today runs one `MapHub` that holds all connected players in a single `ConcurrentDictionary<Guid, ConnectedUser>`. Every action is broadcast to everyone. This is correct and simple up to roughly 50-100 concurrent players. No partitioning code exists yet — the progression below is additive.

```csharp
// Current broadcast pattern in MapHub
foreach (var (id, user) in ConnectedUsers)
{
    if (id == senderId) continue;
    user.GameClient.Map.ReceiveCharacterAction(stamped);
}
```

This O(n) fan-out is fine at low player counts. The upgrade path is to replace the `foreach` with an AoI-filtered version when needed.

## Zone Boundaries and Handoff

### Loading Screen vs Seamless Handoff

**Loading screen** — the client disconnects from zone A's WebSocket, connects to zone B's WebSocket, and replays the join handshake. Simple to implement. Correct for instanced dungeons, arenas, and areas where the player expects a hard transition.

**Seamless handoff** — the player's entity exists briefly in both zones during crossing. Requires an overlap region, state transfer between zone servers, and coordinated despawn/spawn messages to nearby players. Use only when the player experience demands it (open-world map transitions). The complexity cost is high.

For CrystalMagica, start with loading screen transitions. Seamless handoff comes only with the open world feature.

### Handoff Protocol (Loading Screen)

1. Client hits zone boundary trigger (an `Area3D` in Godot).
2. Client sends `ZoneTransferRequest { TargetZoneId, CharacterId }` to current zone server.
3. Server validates, persists character state, generates a short-lived transfer token.
4. Server responds with `ZoneTransferResponse { ZoneServerEndpoint, Token, ExpiresAt }`.
5. Client disconnects, connects to new zone server, sends `JoinRequest` with token.
6. New zone server validates token against shared token store (Redis or DB), restores character state, broadcasts spawn to zone occupants.

```csharp
// MapHub — handle transfer request
public async Task RequestZoneTransfer(ZoneTransferRequest request)
{
    var user = ConnectedUsers[request.CharacterId];

    // Persist current state so new zone can restore it
    await _characterService.PersistAsync(user.Character);

    // Issue token (short TTL — 10 seconds is enough)
    var token = await _transferTokenService.IssueAsync(request.CharacterId, request.TargetZoneId);

    await user.GameClient.Map.ZoneTransferReady(new ZoneTransferResponse
    {
        Endpoint = _zoneRegistry.EndpointFor(request.TargetZoneId),
        Token = token,
        ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(10)
    });
}
```

## Area of Interest (AoI) Filtering

### Why It Matters

Flat broadcast scales as O(n²) — 200 players each sending 1 action/tick = 200 × 199 = 39,800 deliveries/tick. AoI reduces this to O(n × k) where k is the average number of players within visibility range (typically 10-30).

### Spatial Hash Grid

Divide the world into fixed-size cells. An entity's position maps to a cell index via integer division. Broadcast only to entities in the same cell and its 8 neighbors (3×3 neighborhood).

```csharp
public sealed class SpatialHashGrid
{
    private readonly float _cellSize;
    private readonly ConcurrentDictionary<(int X, int Y), HashSet<Guid>> _cells = new();

    public SpatialHashGrid(float cellSize) => _cellSize = cellSize;

    public (int X, int Y) CellFor(Vector2 position) =>
        ((int)MathF.Floor(position.X / _cellSize),
         (int)MathF.Floor(position.Y / _cellSize));

    public void Move(Guid entityId, Vector2 oldPos, Vector2 newPos)
    {
        var oldCell = CellFor(oldPos);
        var newCell = CellFor(newPos);
        if (oldCell == newCell) return;

        Remove(entityId, oldCell);
        Add(entityId, newCell);
    }

    public IEnumerable<Guid> NearbyEntities(Vector2 position)
    {
        var (cx, cy) = CellFor(position);
        for (int dx = -1; dx <= 1; dx++)
        for (int dy = -1; dy <= 1; dy++)
        {
            var cell = (cx + dx, cy + dy);
            if (_cells.TryGetValue(cell, out var set))
                foreach (var id in set) yield return id;
        }
    }

    private void Add(Guid id, (int, int) cell) =>
        _cells.GetOrAdd(cell, _ => new HashSet<Guid>()).Add(id);

    private void Remove(Guid id, (int, int) cell)
    {
        if (_cells.TryGetValue(cell, out var set)) set.Remove(id);
    }
}
```

Cell size should equal the client's maximum visibility range. Too small and the 3×3 neighborhood misses players at the edge; too large and too many cells are included, eroding the savings.

### Integrating AoI into MapHub

Replace the flat broadcast with an AoI-filtered version. The `SpatialHashGrid` is injected as a singleton and updated on every position change.

```csharp
// AoI-filtered relay in MapHub
public void RelayCharacterAction(CharacterAction action)
{
    // Overwrite CharacterId with server-authoritative value
    var user = ConnectedUsers[_connectionService.CallerSessionId];
    action.CharacterId = user.Character.Id;

    // Update grid position
    _aoi.Move(action.CharacterId, _lastPositions[action.CharacterId], action.Position);
    _lastPositions[action.CharacterId] = action.Position;

    // Broadcast only to nearby players
    foreach (var nearbyId in _aoi.NearbyEntities(action.Position))
    {
        if (nearbyId == action.CharacterId) continue;
        if (ConnectedUsers.TryGetValue(nearbyId, out var nearby))
            nearby.GameClient.Map.ReceiveCharacterAction(action);
    }
}
```

### AoI Edge Cases

**Entering a new area** — when a player moves into a cell, they need a burst of state from players already in that cell (positions, HP, animations). Send a join snapshot scoped to the new neighborhood, not the whole world.

**Leaving an area** — players outside the old neighborhood need a despawn message for the departing entity. Track each player's previous neighborhood and diff on move to generate enter/leave events.

**Chat and system messages** — these are not position-filtered. Chat goes through a separate channel that bypasses AoI. See Cross-Zone Communication below.

## Zone Instancing

Instancing creates multiple independent copies of the same zone template — dungeons, arenas, personal housing. Each instance runs in the same server process (or a dedicated one at higher scale) and is identified by an `InstanceId` included in every message.

### Instance Lifecycle

```csharp
public sealed class ZoneInstanceService
{
    private readonly ConcurrentDictionary<Guid, ZoneInstance> _instances = new();

    public ZoneInstance GetOrCreate(Guid zoneTemplateId)
    {
        // Find an existing instance with capacity, or create a new one
        var existing = _instances.Values
            .FirstOrDefault(i => i.TemplateId == zoneTemplateId && i.HasCapacity);

        if (existing is not null) return existing;

        var instance = new ZoneInstance(
            instanceId: Guid.NewGuid(),
            templateId: zoneTemplateId,
            maxPlayers: 5);

        _instances[instance.InstanceId] = instance;
        return instance;
    }

    public void DestroyIfEmpty(Guid instanceId)
    {
        if (_instances.TryGetValue(instanceId, out var instance) && instance.PlayerCount == 0)
            _instances.TryRemove(instanceId, out _);
    }
}
```

The `InstanceId` travels with every wire message for the duration of the session. When the last player leaves, a background sweep or the disconnect handler calls `DestroyIfEmpty`.

## Cross-Zone Communication

Players in different zones still need to communicate via chat, party, and guild systems. These are routing concerns — messages must fan out to the right `ConnectedUser` objects regardless of which zone server holds them.

### Single-Server (Current) — In-Process Routing

When all zones run in the same process, a shared `ChatService` singleton holds subscriptions by player ID. Zone does not matter.

```csharp
// ChatService — shared singleton across all MapHub instances
public sealed class ChatService
{
    private readonly ConcurrentDictionary<Guid, ConnectedUser> _allUsers = new();

    public void Register(ConnectedUser user) => _allUsers[user.SessionId] = user;
    public void Unregister(Guid sessionId) => _allUsers.TryRemove(sessionId, out _);

    public async Task BroadcastGlobalAsync(ChatMessage message)
    {
        foreach (var user in _allUsers.Values)
            await user.GameClient.Chat.ReceiveMessage(message);
    }

    public async Task SendToPartyAsync(Guid partyId, ChatMessage message)
    {
        var members = _partyService.MembersOf(partyId);
        foreach (var memberId in members)
            if (_allUsers.TryGetValue(memberId, out var user))
                await user.GameClient.Chat.ReceiveMessage(message);
    }
}
```

### Multi-Server — Message Bus

When zone servers are separate processes, use a message bus (Redis Pub/Sub, NATS, or RabbitMQ). Each zone server subscribes to topics for global chat, party channels (keyed by party ID), and guild channels. The publishing server posts the message to the bus; all subscribers fan out to their local `ConnectedUsers`.

For CrystalMagica, implement single-server routing first. The message bus path adds an infrastructure dependency that is only justified when zone servers are actually separated.

## Anti-Patterns

**Flat broadcast past 50 players.** Broadcasting all actions to all players is simple and correct at low scale but collapses bandwidth past ~50 concurrent users. Add AoI before you hit the wall, not after players report lag.

**Trusting the client's zone.** The client should tell the server "I want to enter zone X," never "I am now in zone X." The server determines when a transfer is complete and valid, and assigns the canonical zone ID.

**Instance cleanup on a schedule.** Polling all instances on a timer to check if they're empty is wasteful. Trigger cleanup from the disconnect handler — it already knows exactly when the last player left.

**State loss on disconnect during transfer.** If the server crashes between issuing the transfer token and the client connecting to the new zone, the character state is lost. Persist before issuing the token. Treat token issuance as the commit point.

**Leaking entity state across AoI boundaries.** If a player receives no despawn message when an entity leaves their neighborhood, their client retains a ghost entity. Always generate enter/leave events from neighborhood diffs, not just from connect/disconnect events.

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `mmo-action-relay` | Action relay model, broadcast patterns, combat networking |
| `gamedev-server-architecture` | Tick rate, binary protocol, `Channel<T>` usage |
| `crystal-magica-architecture` | `MapHub`, `ConnectedUser`, wire types in the live codebase |
| `gamedev-mmo-persistence` | Persisting character state across zone transitions |
| `gamedev-multiplayer` | Client-side zone transition handling in Godot |
