---
name: CrystalMagica Architecture
description: CrystalMagica project reference — solution structure, MVVM pattern, movement protocol, source generators, key types and their relationships
triggers:
  - CrystalMagica
  - crystal magica
  - project architecture
  - solution structure
  - game architecture
category: gamedev
---

# CrystalMagica Architecture Reference

## Solution structure

| Project | Role | Target |
|---|---|---|
| `CrystalMagica` | Shared library (models, networking, buffers, pool, reactive) | net10.0 |
| `CrystalMagica.Game` | Godot 4.6 client (views, view-models, socket manager) | net10.0 (Godot.NET.Sdk/4.6.1) |
| `CrystalMagica.Server` | ASP.NET WebSocket server (hubs, services) | net10.0 |
| `CrystalMagica.Tests` | MSTest unit tests (serialization, buffers, pool) | net10.0 |
| `CrystalMagica.Generator` | Roslyn incremental source generators + analyzers | netstandard2.0 |

## MVVM pattern

Views are Godot nodes; ViewModels are plain C# classes. Binding is manual, not framework-driven.

- **Views** — `PlayerNode` (CharacterBody3D, implements `IInputAction`), `LocalPlayerNode` (extends PlayerNode), `RemotePlayerNode` (extends PlayerNode, implements `IBindable`), `ItemsNode` (Node3D, collection binding via `INotifyCollectionChanged`).
- **ViewModels** — `LocalPlayerCharacterVM` (holds player data, sends actions via `ServerClient`), `RemoteCharacterVM` (Rx `Subject<CharacterAction>` for updates, `IObservable<Vector2>` for position), `MainViewModel` (owns `SourceCache<RemoteCharacterVM, Guid>`, processes incoming messages, implements `ISocketContext`).
- **IBindable** — defined in `ItemsNode.cs`. Single method `Bind(object viewModel)`. `ItemsNode` instantiates `PackedScene` templates, casts to `IBindable`, calls `Bind`.

## Movement protocol

Action-based, not position-streaming. Clients send discrete action messages; the server relays them to other clients. Each client simulates movement locally from the received actions.

- **CharacterActions enum** — `Jump`, `Move`, `Stop`.
- **CharacterAction** (partial class) — `Action`, `CharacterId`, `Position`. Static `Rent(IPoolService, IReadBuffer)` / `Remit(CharacterAction, IPoolService)` for object pooling.
- **MoveBegin** (extends CharacterAction) — adds `FaceDirection` and `IsRunning`.
- Flow: `LocalPlayerNode` reads Godot input, calls `PlayerNode.MoveBegin/Jump/StopMoving` locally, then calls `LocalPlayerCharacterVM.SendAction` which writes to `ServerClient.Map.RelayCharacterAction`. Server `MapHub.RelayCharacterAction` overwrites `CharacterId` from the authoritative `ConnectedUser`, then relays to all other users via `GameClient.Map.ReceiveCharacterAction`. `MainViewModel` deserializes the action and pushes it to `RemoteCharacterVM.Updates`. `RemotePlayerNode` subscribes and replays the action on its `PlayerNode`.

## Source generators

All in `CrystalMagica.Generator`, all `IIncrementalGenerator`:

| Generator | Emits |
|---|---|
| `ModelSerializationGenerator` | `Serialize` / `Deserialize` methods on partial model classes |
| `HubClientGenerator` | `ServerClient` (wraps `ClientHubs.Server.IMapHub`) and `GameClient` (wraps `ClientHubs.Game.IMapHub`) |
| `MessageRouterGenerator` | `IMessageRouter` / `MessageRouter` — routes incoming bytes to the correct hub method |
| `MessageTypeGenerator` | `ServerMessageType` / `GameMessageType` enums from IClientHub interface method names |
| `ReceiverHubInterfaceGenerator` | `IMapHub` receiver interface for the server (from `ClientHubs.Server.IMapHub`) |

**Trigger**: adding a method to `IClientHub`-derived interfaces (`ClientHubs.Server.IMapHub` or `ClientHubs.Game.IMapHub`) triggers codegen for clients, routers, message types, and receiver interfaces.

Three companion analyzers enforce conventions: `ClientHubInterfaceMustInheritIClientHubAnalyzer`, `ReceiverHubInterfaceMustHaveImplementationAnalyzer`, `ReceiverHubMustImplementInterfaceAnalyzer`.

## Key types

| Type | Location | Purpose |
|---|---|---|
| `CharacterData` | Shared/Models | `Id`, `Color`, `Position`, `Velocity`, `Direction` |
| `CharacterAction` | Shared/Models | Base action with `Action`, `CharacterId`, `Position`; pooled via `Rent`/`Remit` |
| `MoveBegin` | Shared/Models | Extends `CharacterAction` with `FaceDirection`, `IsRunning` |
| `FaceDirection` | Shared/Models | Enum: `Left`, `Right` |
| `CharacterState` | Shared/Models | Enum: `Idle`, `Walking`, `Jumping`, `Falling` |
| `JoinMapResponse` | Shared/Models | `YourCharacter` + `ExistingCharacters` list |
| `Color` | Shared/Models | `R`, `G`, `B` bytes (not Godot.Color) |
| `ConnectedUser` | Server/WebSockets | `SessionId`, `Character`, `GameClient`, outgoing `Channel<Rented<IWriteBuffer>>` |
| `IClientHub` | Shared/ClientHubs | Marker interface; all hub interfaces inherit from it |

## Server architecture

- **WebSocket endpoint** at `/ws`. Raw binary frames, not SignalR.
- `SocketHandler.ProcessSocket` accepts the socket, creates a `ConnectedUser` via `ConnectionService`, runs parallel `ReceiveLoop` / `SendLoop` tasks.
- `ReceiveLoop` parses message type from first byte(s), deserializes payload via `ReadBuffer`, calls `IMessageRouter.RouteMessage`.
- `MapHub` is the only hub. Owns `ConcurrentDictionary<Guid, ConnectedUser> ConnectedUsers`. `JoinRequest` assigns a `CharacterData` with random color, relays spawn to others. `RelayCharacterAction` overwrites `CharacterId` (server-authoritative), relays to all other users.
- `ConnectionService` creates/tears down connections. On disconnect, removes from `MapHub.ConnectedUsers` and broadcasts `CharacterDespawned`.
- No game logic on the server — pure relay with authoritative identity.

## Constraints

- Never push to KervanaLLC repos.
- No AI attribution in committed code.
- `.editorconfig` is law.
- Zero net-new warnings.
