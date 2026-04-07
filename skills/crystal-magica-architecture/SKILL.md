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
version: "1.0.0"
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
| `CharacterData` | Shared/Models | `Id`, `EntityType`, `Color`, `Position`, `Velocity`, `Direction`, `Health`, `MaxHealth` |
| `CharacterAction` | Shared/Models | Base action with `Action`, `CharacterId`, `Position`; pooled via `Rent`/`Remit` |
| `MoveBegin` | Shared/Models | Extends `CharacterAction` with `FaceDirection`, `IsRunning` |
| `AttackAction` | Shared/Models | Extends `CharacterAction` with `FaceDirection Direction`; attack intent sent client→server |
| `EnemyDamaged` | Shared/Models | `Guid EnemyId`, `int NewHealth`, `int Damage`; health update sent server→client |
| `FaceDirection` | Shared/Models | Enum: `Left`, `Right` |
| `CharacterState` | Shared/Models | Enum: `Idle`, `Walking`, `Jumping`, `Falling` |
| `EntityType` | Shared/Models | Enum: `Player`, `Enemy` |
| `JoinMapResponse` | Shared/Models | `YourCharacter` + `ExistingCharacters` list |
| `Color` | Shared/Models | `R`, `G`, `B` bytes (not Godot.Color) |
| `ConnectedUser` | Server/WebSockets | `SessionId`, `Character`, `GameClient`, outgoing `Channel<Rented<IWriteBuffer>>` |
| `IClientHub` | Shared/ClientHubs | Marker interface; all hub interfaces inherit from it |

## Server architecture

- **WebSocket endpoint** at `/ws`. Raw binary frames, not SignalR.
- `SocketHandler.ProcessSocket` accepts the socket, creates a `ConnectedUser` via `ConnectionService`, runs parallel `ReceiveLoop` / `SendLoop` tasks.
- `ReceiveLoop` parses message type from first byte(s), deserializes payload via `ReadBuffer`, calls `IMessageRouter.RouteMessage`.
- `MapHub` is the only hub. Owns `ConcurrentDictionary<Guid, ConnectedUser> ConnectedUsers`. `JoinRequest` assigns a `CharacterData` with random color, relays spawn to others. `RelayCharacterAction` overwrites `CharacterId` (server-authoritative), relays to all other users. `PerformAttack` receives attack intents from clients, validates, and delegates to `AttackService`.
- `ConnectionService` creates/tears down connections. On disconnect, removes from `MapHub.ConnectedUsers` and broadcasts `CharacterDespawned`.
- **Server is stateful and authoritative for combat (Loop 5+).** The server transitioned from pure relay to authoritative game logic at Loop 5. Clients send intents ("I attacked at position P facing direction D"); the server decides what got hit.

### Combat services (added Loop 5)

- **`AttackService`** — hitbox computation (rectangular region in front of attacker based on `FaceDirection`), collision checks against all enemy positions in `EnemyRegistry`, damage application (1 damage per hit), per-attack dedup (same enemy hit at most once per attack activation), continuous collision checking for the 1s attack duration so enemies walking into an active hitbox are also hit.
- **`EnemyRegistry`** — singleton `ConcurrentDictionary<Guid, CharacterData>` shared between `EnemyControllerService` and `AttackService`. Provides a consistent view of enemy positions to both services.
- **`EnemyControllerService`** — `BackgroundService`. Spawns enemies with health (`Health = 5`, `MaxHealth = 5`). Patrol loop (MoveBegin right → delay → update position → MoveBegin left → delay). Each enemy has its own `CancellationTokenSource` so it can be cancelled individually on death (Loop 6).

### Hub methods added in Loop 5

| Method | Direction | Purpose |
|---|---|---|
| `MapHub.PerformAttack(AttackAction)` | Client → Server | Client sends attack intent; server resolves damage |
| `EnemyHealthUpdated(EnemyDamaged)` | Server → Client | Broadcasts new enemy health after damage is applied |

### Models added in Loop 5

| Type | Fields | Purpose |
|---|---|---|
| `AttackAction` | extends `CharacterAction`, adds `FaceDirection Direction` | Wire format for attack intent (client→server) |
| `EnemyDamaged` | `Guid EnemyId`, `int NewHealth`, `int Damage` | Wire format for health update notification (server→client) |

`AttackService` also maintains an internal list of active attacks for the 1s duration window. Each entry tracks attacker position, facing direction, start time, and the set of already-hit enemy IDs (for per-attack dedup). These are internal implementation details, not shared wire types.

## Constraints

- Never push to KervanaLLC repos.
- No AI attribution in committed code.
- `.editorconfig` is law.
- Zero net-new warnings.
