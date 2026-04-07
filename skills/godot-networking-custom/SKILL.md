---
name: Custom Networking for Godot
description: Custom binary protocol networking for Godot 4.6 C# — WebSocket transport, Channel-based threading, action-based movement protocol
triggers:
  - networking
  - custom protocol
  - WebSocket
  - binary protocol
  - netcode
  - client server
  - action relay
category: gamedev
version: "1.0.0"
---

# Custom Networking for Godot 4.6 C# (CrystalMagica Pattern)

This is NOT Godot's built-in MultiplayerAPI. No MCP servers.

## 1. Architecture Overview

WebSocket transport with custom binary serialization. The wire format is fully controlled — no Godot MultiplayerAPI, no RPC, no MultiplayerSpawner/Synchronizer.

**Why custom:**
- Full control over wire format and message framing.
- Source-generated serializers — no reflection, no runtime codegen.
- Works with any .NET server (ASP.NET, bare Kestrel, etc.) — not coupled to Godot's networking stack.
- Same model classes shared between client and server projects.

Messages are length-prefixed binary frames over WebSocket binary messages. Each frame starts with a message type ID (ushort) followed by the serialized payload.

## 2. Threading Model

```
Network thread (WebSocket recv) → Channel<MemoryStream> → Main thread (_Process drains)
```

- **Client channels:** `Channel.CreateBounded<MemoryStream>(capacity)` with `SingleReader = true`, `SingleWriter = true`.
- **Server channels:** `SingleWriter = false` because multiple BackgroundServices may enqueue messages for the same user.
- All Godot node mutations happen on the main thread only. The `_Process(double delta)` loop calls `TryRead` in a while-loop to drain the channel each frame.
- Outbound: main thread writes to an outbound channel; a dedicated send task drains it onto the WebSocket.

## 3. Action-Based Movement

Movement is NOT position-synced. Clients send **actions**, server relays to other clients, remote clients replay through the same physics pipeline.

```csharp
enum CharacterAction : byte { Jump, MoveBegin, MoveEnd, Stop }
```

- `MoveBegin` carries `FaceDirection` (Vector2 as two floats) and `IsRunning` (bool).
- Client presses key → sends `MoveBegin` to server → server broadcasts to other clients in the same map.
- Each remote client feeds the action into the same `CharacterMovementController`, producing deterministic movement through Godot's physics.
- `Stop` includes a final authoritative position snap to correct drift.

## 4. Source-Generated Serialization

Model classes are `partial`. A Roslyn source generator (`ModelSerializationGenerator`) emits `Serialize(BinaryWriter)` and `static Deserialize(BinaryReader)` methods.

- Inheritance: generated code calls `base.Serialize(writer)` first, then writes own fields.
- **Rent/Remit pooling:** `MemoryStream` and `BinaryWriter` instances are rented from a pool on the hot path — zero allocation in steady state.
- Supported field types: primitives, strings (length-prefixed UTF-8), enums (underlying type), `List<T>` (count-prefixed), nested models, `Vector2`/`Vector3` (written as raw floats).

## 5. Hub Pattern

Networking surface is defined by `IClientHub` interfaces. Separate hubs per domain:

```
Server/IMapHub     — server-side handlers for map-related messages
Game/IMapHub       — client-side handlers (what the Godot client receives)
```

- A code generator reads the interface and produces:
  - **Typed send methods** on `ServerClient` / `GameClient` (one method per interface method, serializes args and writes to channel).
  - **MessageRouter** on the server: maps message type ID → handler delegate, calls the correct hub method.
- **Adding a new message type:** add a method to the appropriate `IClientHub` interface. Re-run generators. Implement the handler. Done.

## 6. Thread Safety Checklist

| Concern | Solution |
|---|---|
| User registry (server) | `ConcurrentDictionary<Guid, ConnectedUser>` |
| Cross-thread message passing | `Channel<MemoryStream>` (bounded) |
| Broadcasting to many users | Iterate `ConnectedUsers.Values`, write to each user's outbound channel |
| Shared mutable game state | Avoid. If necessary, use `Channel<T>` to funnel mutations to a single consumer |
| Locks | Not needed if you follow the Channel pattern consistently |

`BackgroundService` instances can safely read `ConnectedUsers.Values` and write to individual user channels without locking because `ConcurrentDictionary` iteration is snapshot-safe and channel writes are thread-safe.

## 7. Join Protocol

```
Client                          Server
  |  -- JoinRequest -->           |
  |                               |  creates CharacterData
  |                               |  registers in map
  |  <-- JoinMapResponse --       |  (includes ExistingCharacters[])
  |                               |
  |                               |  -- CharacterSpawned --> (broadcast to others)
```

- `JoinMapResponse` contains the player's own `CharacterData` plus a list of all other characters already on the map.
- Other connected clients receive `CharacterSpawned` and instantiate the new remote character.
- On disconnect, server broadcasts `CharacterDespawned` with the leaving character's ID.
