---
name: gamedev-multiplayer
description: Multiplayer game networking patterns — architecture models, state synchronization, lag compensation, matchmaking, lobby systems, and Godot 4 multiplayer API. Load when designing or implementing networked multiplayer features.
---

# Multiplayer Game Networking

## Architecture Models

### Client-Server Authoritative

The server is the single source of truth. Clients send inputs; the server simulates and broadcasts results.

- Server validates all state transitions
- Clients predict locally, reconcile with server corrections
- Gold standard for competitive multiplayer
- Higher server compute cost, requires dedicated infrastructure

### Client-Server with Client Authority

Clients own certain state (typically their own movement) and the server relays it.

- Lower latency feel — no waiting for server confirmation
- Vulnerable to cheating (speed hacks, teleportation)
- Acceptable for co-op PvE or casual games where cheating risk is low
- Hybrid approach: client-authoritative movement, server-authoritative combat

### Peer-to-Peer (Mesh)

Every client connects to every other client. No central server.

- All peers must agree on state (lockstep or rollback)
- NAT traversal is the primary pain point (STUN/TURN, hole punching)
- Bandwidth scales O(n^2) with player count — impractical above 8-16 players
- Best for: fighting games, RTS (lockstep), small-lobby co-op

### Relay Server

P2P-style game logic but traffic routes through a central relay. Steam Networking, Epic Online Services, and Photon all offer this.

- Solves NAT traversal without full dedicated server cost
- Relay adds latency vs direct P2P (but guarantees connectivity)
- Game logic still runs on clients — same trust model as P2P
- Good middle ground for indie multiplayer

### Dedicated vs Listen Servers

| Aspect | Dedicated Server | Listen Server |
|--------|-----------------|---------------|
| Hosting | Separate process/machine | One player's machine hosts |
| Performance | Consistent, controllable | Depends on host's hardware/connection |
| Fairness | Equal latency for all | Host has zero latency advantage |
| Cost | Infrastructure cost | Free (player hosts) |
| Availability | Always on | Gone when host leaves (unless host migration) |
| Best for | Competitive, persistent worlds | Casual co-op, LAN parties |

### Decision Matrix

| Game Type | Recommended Model | Why |
|-----------|-------------------|-----|
| Competitive FPS/TPS | Client-server authoritative + dedicated | Anti-cheat, fair latency, server-side hit detection |
| Fighting game | P2P with rollback netcode | Frame precision, 2-player, rollback hides latency |
| Co-op PvE (2-4 players) | Listen server or relay | Low cheat risk, no infra cost |
| MMO / persistent world | Dedicated server cluster | Scale, persistence, authority |
| Battle royale (64-100 players) | Dedicated server, aggressive interest management | Bandwidth, fairness, scale |
| Mobile casual (8-16 players) | Relay server | NAT traversal solved, low infra cost |
| RTS (2-8 players) | P2P lockstep or rollback | Deterministic simulation, minimal bandwidth |
| Turn-based | Client-server (lightweight) | Simple state sync, no latency sensitivity |

## State Synchronization

### Snapshot Interpolation

Server sends full world snapshots at a fixed tick rate. Clients buffer snapshots and interpolate between them for smooth rendering.

```
Server tick 10: [Player A at (10, 0), Player B at (5, 3)]
Server tick 11: [Player A at (11, 0), Player B at (5, 4)]

Client renders between tick 10 and 11 at render time,
interpolating positions smoothly.
```

- Simple to implement, easy to debug
- High bandwidth — sending everything every tick
- Typical interpolation buffer: 2-3 ticks (adds visual latency)
- Works well for small player counts or when combined with delta compression

### State Delta Compression

Only transmit what changed since the last acknowledged snapshot.

```
Full snapshot:  { pos: (10,0), health: 100, ammo: 30, armor: 50 }
Delta (tick+1): { pos: (11,0) }  # only position changed
```

- Dramatically reduces bandwidth
- Requires reliable acknowledgment tracking per client
- Combine with bitwise dirty flags for efficient change detection
- Quake 3 pioneered this approach — still the standard

### Interest Management / Relevancy

Only send a client data they can perceive or that affects them.

| Strategy | Description | Best For |
|----------|-------------|----------|
| Distance-based | Entities beyond radius are culled | Open world, MMO |
| Area of Interest (AOI) | Grid/cell-based regions | Large maps, battle royale |
| Team-based | Only send teammate data + visible enemies | Team shooters |
| Priority-based | Closer/more important entities update more frequently | Bandwidth-constrained |
| Visibility-based | Ray/frustum checks against world geometry | High-fidelity shooters |

### Tick Rate vs Frame Rate

| Concept | Typical Values | Purpose |
|---------|---------------|---------|
| Server tick rate | 20-128 Hz | Physics simulation, state authority |
| Client send rate | 20-64 Hz | Input transmission to server |
| Client frame rate | 60-240 Hz | Rendering (interpolation fills gaps) |
| Snapshot send rate | 10-30 Hz | State broadcast to clients |

- Decouple simulation from rendering — physics at fixed tick, rendering at variable frame rate
- Higher tick rates improve responsiveness but cost server CPU and bandwidth
- 20 Hz is common for casual games; 64-128 Hz for competitive shooters
- Godot: use `_physics_process()` for networked simulation, `_process()` for visual interpolation

### Bandwidth Budget

Rule of thumb for a 20-tick server with 16 players:

```
Per-entity update:  ~40-80 bytes (position, rotation, velocity, state flags)
Per-tick upstream:  ~20-40 bytes (input only)
Per-tick downstream: entities_in_relevance * bytes_per_entity * tick_rate

Example: 16 players, 64 bytes/entity, 20 ticks/sec
  = 16 * 64 * 20 = 20,480 bytes/sec = ~20 KB/s per client downstream
```

- Mobile target: < 50 KB/s per client
- PC target: < 200 KB/s per client
- Delta compression typically reduces bandwidth by 60-80%

## Lag Compensation

### Client-Side Prediction

The client immediately applies its own input locally without waiting for server confirmation.

```gdscript
# Client predicts own movement immediately
func _physics_process(delta):
    var input = gather_input()
    save_input_to_buffer(input, current_tick)
    apply_movement(input, delta)  # predict locally
    send_input_to_server(input, current_tick)
```

- Movement feels instant to the player
- Must reconcile when server state arrives and disagrees
- Only predict actions the client controls (own movement, not other players)

### Server Reconciliation

When the server corrects the client, rewind to the corrected state and replay all unacknowledged inputs.

```gdscript
func on_server_state_received(server_state, server_tick):
    # Compare server state to what we predicted at that tick
    var predicted = get_predicted_state(server_tick)
    if not states_match(predicted, server_state):
        # Snap to server state
        position = server_state.position
        velocity = server_state.velocity
        # Replay all inputs from server_tick+1 to current_tick
        for tick in range(server_tick + 1, current_tick + 1):
            var buffered_input = get_buffered_input(tick)
            apply_movement(buffered_input, tick_delta)
```

- Keep a circular buffer of recent inputs (128-256 ticks)
- Replay must be deterministic — same input produces same result
- Threshold the correction: small errors can be smoothed, large errors snap

### Entity Interpolation

Render other players (and server-authoritative entities) between received snapshots rather than at their latest known position.

```gdscript
# Interpolate remote players between two server snapshots
func interpolate_remote_entity(entity, render_time):
    var t0 = entity.snapshot_buffer[-2]  # older snapshot
    var t1 = entity.snapshot_buffer[-1]  # newer snapshot
    var alpha = (render_time - t0.time) / (t1.time - t0.time)
    alpha = clamp(alpha, 0.0, 1.0)
    entity.visual_position = t0.position.lerp(t1.position, alpha)
    entity.visual_rotation = t0.rotation.slerp(t1.rotation, alpha)
```

- Remote entities render in the "past" by one interpolation buffer period
- Eliminates jitter from network variance
- Extrapolation (predicting forward) as fallback when snapshots are late — but cap it to avoid rubber-banding

### Input Buffering and Jitter Compensation

Network jitter means inputs arrive at irregular intervals. Buffer inputs server-side to smooth processing.

```
Without buffer:  tick 10 (input arrives), tick 11 (no input!), tick 12 (2 inputs arrive)
With buffer (2): tick 10 (buffered), tick 11 (buffered), tick 12 (buffered) — smooth
```

- Server holds inputs for a small buffer (1-3 ticks) before processing
- Adds latency equal to buffer size but eliminates stutter
- Adaptive jitter buffer: dynamically size based on measured network variance
- Client timestamps inputs; server uses timestamps to detect drift

### Lag Compensation for Hit Detection (Server Rewind)

The server rewinds the world to the time the shooting client saw it, then performs the hit check.

```
Client shoots at tick 50 (sees enemy at position X due to interpolation delay)
Server receives shot at tick 53
Server rewinds enemy positions to tick 50 - interpolation_buffer
Server performs raycast against historical positions
If hit: apply damage at current tick
```

- Requires the server to store position history (ring buffer per entity)
- Favors the shooter's experience ("what you see is what you hit")
- Cap rewind window (e.g., 200ms max) to prevent extreme abuse on high-latency connections
- Trade-off: players with low ping can get "shot around corners" by high-ping players

### Rollback Netcode

Primarily used in fighting games and other frame-precise genres. Each client runs the simulation, rolling back and replaying when remote inputs arrive late.

```
Local frame 10: Predict remote player repeats last input
Frame 11: Remote input for frame 10 arrives — it was different!
Rollback to frame 10, apply correct input, fast-forward to frame 11
If visual state changed: correction is visible but brief
```

- GGPO is the canonical implementation (now open-source)
- Works best for 2-player games with small state
- Rollback window typically 1-8 frames; beyond that, force a pause
- Requires fully deterministic simulation (floating point consistency matters)
- State must be serializable and restorable efficiently (snapshot + restore per frame)

## Godot 4 Multiplayer API

### Core Classes

| Class | Role |
|-------|------|
| `MultiplayerAPI` | Abstract API — manages peers, RPCs, object replication |
| `SceneMultiplayer` | Default implementation of MultiplayerAPI for scene trees |
| `MultiplayerPeer` | Abstract transport layer — swap implementations |
| `ENetMultiplayerPeer` | UDP-based transport (reliable + unreliable channels) |
| `WebSocketMultiplayerPeer` | WebSocket transport (for HTML5 exports) |
| `MultiplayerSpawner` | Auto-spawn nodes across peers |
| `MultiplayerSynchronizer` | Auto-sync properties across peers |

### Setting Up a Server/Client

```gdscript
# Server
func start_server(port: int = 9999, max_clients: int = 16):
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(port, max_clients)
    if error != OK:
        push_error("Failed to create server: %s" % error)
        return
    multiplayer.multiplayer_peer = peer
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# Client
func connect_to_server(address: String = "127.0.0.1", port: int = 9999):
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_client(address, port)
    if error != OK:
        push_error("Failed to connect: %s" % error)
        return
    multiplayer.multiplayer_peer = peer
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)
```

### RPC System

```gdscript
# Define RPCs with @rpc annotation
# Modes: any_peer, authority (only multiplayer authority can call)
# Sync: call_local, call_remote (default)
# Transfer: unreliable, unreliable_ordered, reliable

@rpc("any_peer", "call_local", "reliable")
func send_chat_message(message: String):
    # Runs on all peers when called with .rpc()
    chat_display.add_message(message)

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_position(pos: Vector2, vel: Vector2):
    position = pos
    velocity = vel

# Calling RPCs
send_chat_message.rpc("Hello everyone!")              # Call on ALL peers
sync_position.rpc_id(target_peer_id, pos, vel)        # Call on specific peer
```

### RPC Transfer Modes

| Mode | Guaranteed Delivery | Ordered | Use For |
|------|-------------------|---------|---------|
| `reliable` | Yes | Yes | Chat, damage, spawning, game events |
| `unreliable` | No | No | Position updates (stale data is useless) |
| `unreliable_ordered` | No | Yes | Frequent state sync (latest matters, skip stale) |

### MultiplayerSpawner

Automatically replicates node creation across peers.

```gdscript
# In the scene tree:
# Game
#   ├── MultiplayerSpawner (spawn_path = Players, auto_spawn_list = [player_scene])
#   └── Players/

# Server spawns — all clients automatically get the node
func spawn_player(peer_id: int):
    var player = player_scene.instantiate()
    player.name = str(peer_id)
    $Players.add_child(player)
    # MultiplayerSpawner handles replication to other peers
```

### MultiplayerSynchronizer

Automatically replicates property changes from authority to other peers.

```gdscript
# Attach MultiplayerSynchronizer as child of the node to sync
# Configure synced properties in the inspector or via code:

# In the scene tree:
# Player (authority = peer_id)
#   ├── MultiplayerSynchronizer
#   │     replication_config:
#   │       position → always (unreliable)
#   │       health → on_change (reliable)
#   │       animation_state → always (unreliable_ordered)
#   └── Sprite2D
```

Replication modes:
- **Always**: Send every tick (position, rotation)
- **On Change**: Send only when value changes (health, inventory)

### Authority Model

```gdscript
# Server assigns authority over player nodes
func _on_peer_connected(peer_id: int):
    var player = spawn_player(peer_id)
    player.set_multiplayer_authority(peer_id)
    # Now peer_id owns this node — their RPCs with "authority" mode work

# Check authority in game logic
func _physics_process(delta):
    if not is_multiplayer_authority():
        return  # only the authority processes input for this node
    var input = gather_input()
    apply_movement(input, delta)
```

### WebSocket Peer (HTML5 Export)

```gdscript
# Same API, different transport — swap ENet for WebSocket
func start_websocket_server(port: int = 9999):
    var peer = WebSocketMultiplayerPeer.new()
    peer.create_server(port)
    multiplayer.multiplayer_peer = peer

# Client
func connect_websocket(url: String = "ws://127.0.0.1:9999"):
    var peer = WebSocketMultiplayerPeer.new()
    peer.create_client(url)
    multiplayer.multiplayer_peer = peer
```

- Required for web exports (browsers cannot use raw UDP/ENet)
- Higher latency than ENet — TCP-based under the hood
- No unreliable channel — all messages are reliable/ordered
- Consider WebRTC for unreliable channels in browser contexts

## Lobby and Matchmaking

### Lobby Lifecycle

```
CREATE → WAITING → READY_CHECK → COUNTDOWN → IN_GAME → POST_GAME → DISSOLVE
                                                              ↓
                                                         RETURN_TO_LOBBY
```

1. **Create**: Host creates lobby, sets game mode, map, max players, visibility (public/private/friends)
2. **Waiting**: Players join via matchmaker, invite, or lobby browser
3. **Ready check**: All players confirm readiness
4. **Countdown**: Short countdown for late readiness toggles
5. **In-game**: Lobby state frozen, game begins
6. **Post-game**: Results screen, option to rematch or return to lobby

### Matchmaking Strategies

| Strategy | Algorithm | Best For |
|----------|-----------|----------|
| Skill-based (ELO) | Simple: win = +K, lose = -K, scaled by opponent rating | 1v1 games, chess-like |
| Skill-based (Glicko-2) | Adds rating deviation and volatility | Games with irregular play frequency |
| Skill-based (TrueSkill) | Bayesian, supports teams | Team-based competitive |
| Region-based | Route to nearest datacenter | Latency-sensitive, global player base |
| Latency-based | Measure RTT, group low-latency peers | P2P games, fighting games |
| Hybrid | Skill + region + latency constraints | Most production multiplayer games |

### Matchmaking implementation notes

- Widen skill range over time if no match found (expansion windows)
- Prioritize match quality for ranked, speed for casual
- Track wait times — alert if median exceeds 60 seconds
- Backfill: allow joining in-progress matches for casual modes

### Host Migration

When the host disconnects in a listen-server model:

1. Detect host disconnect (timeout or explicit disconnect signal)
2. Elect new host (lowest peer ID, best connection, or pre-assigned backup)
3. New host assumes server role — recreates authoritative state from its local copy
4. Remaining clients reconnect to new host
5. State reconciliation — brief pause while world state synchronizes

- Complex to implement correctly; dedicated servers avoid this entirely
- Must handle partial state — what if the new host was slightly behind?
- Test extensively with forced disconnects at every game state

### Reconnection Handling

- Assign persistent session IDs (not peer IDs, which change on reconnect)
- Server keeps disconnected player state for a grace period (30-120 seconds)
- On reconnect: authenticate, map session ID to stored state, send full snapshot
- Game design decision: AI takes over during disconnect, player is invulnerable, or character stands still

## Network Protocol Design

### Channel Types

| Channel | Delivery | Ordering | Use Case |
|---------|----------|----------|----------|
| Reliable ordered | Guaranteed | In-order | Chat, game events, inventory changes |
| Reliable unordered | Guaranteed | Any order | Asset loading, non-sequential data |
| Unreliable ordered | Best-effort | Skip stale | Position/state sync (drop old, keep latest) |
| Unreliable unordered | Best-effort | Any order | VoIP, particle effects, cosmetic events |

### Message Structure

```
# Binary message format — NOT JSON
[Header: 2 bytes]
  ├── Message type (1 byte, up to 256 message types)
  └── Flags (1 byte: compressed, fragmented, priority)
[Sequence number: 2 bytes]
[Payload: variable]
  └── Tightly packed fields, not key-value pairs

# Example: position update = 13 bytes total
[type=0x01][flags=0x00][seq=1234][x:float32][y:float32][rotation:uint8]
vs JSON equivalent: {"type":"pos","x":123.45,"y":67.89,"r":180} = 47 bytes
```

### Serialization Rules

- Use binary serialization over the wire — JSON is for debugging only
- Fixed-size fields where possible (float32, int16, uint8)
- Compress rotation to fewer bits when full precision is unnecessary (uint8 = 256 directions, sufficient for most 2D games)
- Quantize position to integer units if sub-pixel precision is unnecessary
- Var-length encoding (like protobuf varints) for IDs and counts

### Protocol Versioning

```
# Include protocol version in handshake
Client → Server: [HANDSHAKE][protocol_version=3][client_version="1.2.0"]
Server → Client: [HANDSHAKE_ACK] or [VERSION_MISMATCH][min_supported=2][current=3]
```

- Server defines minimum and maximum supported protocol versions
- Breaking changes increment the major protocol version
- Maintain backward compatibility for at least one version during rollouts
- Feature flags within the protocol for optional capabilities

### Message Batching and Prioritization

- Batch multiple small messages into a single packet (reduce header overhead)
- Maximum packet size: stay under MTU (typically 1200-1400 bytes for UDP)
- Priority queue: position updates > game events > cosmetic effects > analytics
- Rate-limit low-priority messages when bandwidth is constrained

## Security

### Server Authority as Primary Defense

The most effective anti-cheat is a server that validates everything.

| Principle | Implementation |
|-----------|---------------|
| Never trust the client | Server validates all inputs and state transitions |
| Clients send inputs, not results | "I pressed attack" not "I dealt 50 damage to Player B" |
| Server owns the clock | Server tick is authoritative; reject inputs with impossible timestamps |
| Validate movement | Check speed, acceleration, collision against server-side world |
| Validate actions | Rate-limit attacks, ability usage, item consumption |

### Input Validation Checklist

1. Movement speed within allowed range (account for buffs/abilities)
2. Action cooldowns respected (server tracks cooldown timers)
3. Line-of-sight verified for targeted actions
4. Resource costs checked before allowing actions
5. Sequence validity (cannot attack while dead, cannot cast while stunned)
6. Position delta per tick within physics bounds

### Common Cheats and Mitigations

| Cheat | How It Works | Server-Side Mitigation |
|-------|-------------|----------------------|
| Speed hack | Client modifies movement speed | Server validates position delta per tick |
| Teleport | Client sets arbitrary position | Server rejects position jumps exceeding max velocity |
| Aimbot | Client auto-targets enemies | Server validates aim consistency, impossible reaction times |
| Wallhack | Client renders hidden enemies | Interest management — never send data about enemies the player cannot perceive |
| Damage hack | Client reports inflated damage | Server calculates all damage; clients never report damage values |
| Packet manipulation | Modify packets in transit | Encrypt and authenticate packets; reject tampered messages |
| Replay attack | Re-send valid old packets | Sequence numbers + timestamp windows; reject duplicates |

### Connection Security

- Encrypt game traffic (DTLS for UDP, TLS for WebSocket)
- Authenticate players before joining game sessions (token from auth service)
- Session tokens with expiry — do not use permanent credentials in game traffic
- Rate limit connection attempts to prevent DDoS on game servers

## Scalability

### Player Capacity Planning

| Architecture | Typical Capacity | Bottleneck |
|-------------|-----------------|------------|
| Single server, action game | 16-64 players | CPU (simulation), bandwidth |
| Single server, MMO zone | 200-500 players | Bandwidth, interest management |
| Sharded MMO | 1000-10000+ per shard | Database, cross-shard communication |
| Battle royale | 100 per match | Bandwidth at match start, CPU mid-game |

### Sharding and Instancing

- **Zone-based sharding**: World divided into geographic zones, each on its own server. Players transfer between zones via portals or seamless transition.
- **Room/match instancing**: Each match or dungeon is an independent server instance. Stateless — spin up and tear down per session.
- **Channel-based**: Multiple copies of the same world for overflow (Guild Wars 1 model).
- Cross-shard interaction (trading, chat) requires a separate service layer.

### Cloud Deployment Patterns

| Pattern | When to Use |
|---------|------------|
| Containerized game servers (Docker/K8s) | Standard for dedicated servers; quick scaling |
| Auto-scaling groups | Scale server fleet based on matchmaker queue depth |
| Regional deployment | Deploy close to players; use anycast or region-based routing |
| Spot/preemptible instances | Cost savings for non-ranked matches that can tolerate interruption |
| Agones (K8s game server orchestrator) | Open-source; integrates with K8s for game server lifecycle |

### Database Considerations

- Game state during a match should be in-memory (not database queries per tick)
- Persist on match end: results, stats, progression, replays
- Player profiles and inventory: traditional database (PostgreSQL, etc.)
- Leaderboards: sorted sets (Redis) or purpose-built leaderboard service
- Write-behind pattern: buffer writes, flush periodically — not per-action

## Testing and Debugging

### Local Multi-Instance Testing

```gdscript
# Godot: launch multiple instances from editor
# Project Settings → Run → Multiple Instances → set to 2-4

# Or use OS.execute to launch headless server + client windows
# Command line:
# godot --headless --server       # server instance
# godot --client --connect=127.0.0.1  # client instance(s)
```

- Always test with at least 3 instances: server + 2 clients
- Test asymmetric scenarios: host + client behave differently
- Automate multi-instance launches with scripts for rapid iteration

### Simulated Network Conditions

| Condition | How to Simulate | What It Reveals |
|-----------|----------------|-----------------|
| Latency (50-200ms) | Network emulator (clumsy, tc, Godot debug) | Prediction/interpolation quality |
| Packet loss (1-10%) | Network emulator | Reliability of state sync |
| Jitter (variable latency) | Random delay injection | Jitter buffer adequacy |
| Bandwidth limit | Throttle outbound | Compression and prioritization effectiveness |
| Disconnect/reconnect | Kill and restart client process | Reconnection flow, state recovery |
| Reordered packets | Network emulator | Sequence number handling |

### Network Profiling

- Log bytes sent/received per tick, per message type
- Track RTT per client over time (graph it)
- Count messages per second by type — find the chatty ones
- Monitor server tick duration — if it exceeds tick interval, simulation falls behind
- Godot: use the built-in Multiplayer Profiler (Debugger panel → Multiplayer tab)

### Replay Systems

- Record all inputs with tick numbers — replay by feeding inputs into deterministic simulation
- Alternatively, record full snapshots for non-deterministic games
- Invaluable for debugging "it only happens in multiplayer" bugs
- Store replays server-side for cheat review and player reporting
- Replay format should include protocol version for forward compatibility

### Headless Server Builds

```
# Godot: export with --headless flag or use a server export preset
# Disable rendering, audio, and input — server only needs simulation

# Export preset: "Linux Server" with:
#   - Display server: headless
#   - Audio driver: Dummy
#   - Rendering: disabled or minimal
```

- Reduces server resource usage significantly (no GPU needed)
- Same game logic, no visual output
- Deploy to cloud instances without GPU
- Test headless builds in CI to catch rendering-dependency bugs early

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-godot` | Godot engine fundamentals, scene architecture, C# scripting |
| `gamedev-voice-arthur` | Co-developer voice and tone for game project output |
| `dotnet-architecture` | C# server architecture patterns (Clean Architecture, DDD for game servers) |
| `dotnet-error-handling` | Server-side error handling, resilience patterns |

## Quality Gate Checklist

Before shipping a multiplayer feature, verify:

1. **Authority model is defined**: Every piece of game state has a clear owner (server or specific client). No ambiguity about who resolves conflicts.
2. **Client prediction reconciles correctly**: Prediction mismatch triggers smooth correction, not teleportation. Test with 100ms+ simulated latency.
3. **Remote entities interpolate smoothly**: No jitter or teleporting for other players under normal conditions (< 5% packet loss).
4. **Bandwidth is within budget**: Measure per-client downstream at max player count. Delta compression and interest management are active.
5. **Reconnection works end-to-end**: Disconnect during gameplay, reconnect within grace period, resume without data loss.
6. **Server validates all client inputs**: No client-reported outcomes accepted without server verification. Test with intentionally malicious inputs.
7. **Protocol is versioned**: Client/server version mismatch produces a clear error, not silent corruption or crashes.
8. **Tick rate is stable**: Server simulation never consistently exceeds tick interval. Profile at max player count with worst-case game state.
9. **Lobby flow handles edge cases**: Host disconnect, player disconnect during ready check, join during countdown, full lobby rejection — all produce correct behavior.
10. **Network conditions are tested**: Feature works acceptably at 150ms latency, 3% packet loss, and with jitter. Documented minimum network requirements.
11. **Headless server builds work**: Server runs without GPU, rendering, or audio dependencies. Verified in CI or staging environment.
12. **Replay or logging captures enough to debug**: Multiplayer bugs are reproducible from recorded data, not just player reports.

## Anti-Patterns

### 1. Trusting the Client

Letting clients report game outcomes instead of inputs. "I killed Player B" instead of "I fired at position (x, y) at tick N." The server must adjudicate.

### 2. Synchronizing Everything

Sending full world state to every client every tick. Use interest management, delta compression, and priority systems. A player across the map does not need 60Hz updates.

### 3. Using TCP for Real-Time Game State

TCP's head-of-line blocking and guaranteed delivery cause stalls when a packet is lost. Use UDP with selective reliability (ENet does this). TCP is fine for login, chat, and lobby — not for position updates.

### 4. JSON Over the Wire

Serializing game state as JSON wastes 3-5x bandwidth compared to binary encoding. JSON is human-readable — use it for debugging tools and REST APIs, not for 60Hz game state sync.

### 5. Ignoring Jitter

Assuming network latency is constant. Real networks have variable delay. Without a jitter buffer, entity movement stutters even at low average latency. Always buffer incoming data.

### 6. Skipping Simulated Latency Testing

Testing multiplayer only on localhost (0ms latency, 0% packet loss). The game feels perfect locally but breaks at real-world network conditions. Always test with simulated latency and packet loss before shipping.

### 7. Rolling Your Own Crypto

Implementing custom encryption for game traffic instead of using established protocols (DTLS, TLS). Custom crypto will have vulnerabilities. Use proven libraries.

### 8. Single Point of Failure Matchmaking

Running matchmaking on a single server instance. When it goes down, no one can play — even if game servers are healthy. Matchmaking, authentication, and game servers should be independently scalable and deployable.

### 9. Determinism Assumptions Without Verification

Assuming the simulation is deterministic across platforms or builds (required for lockstep/rollback) without continuous verification. Floating-point behavior varies across compilers, platforms, and optimization levels. Test with checksums every frame.
