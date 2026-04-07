---
name: dotnet-mvvm-backend
description: MVVM architecture for .NET game backends — System.Reactive, DynamicData, SourceCache, ViewModel binding with Godot nodes, ItemsNode collection pattern
triggers:
  - MVVM
  - ViewModel
  - System.Reactive
  - DynamicData
  - SourceCache
  - Bind
  - IObservable
  - Subject
  - reactive
  - ItemsNode
category: dotnet
version: "1.0.0"
---

# .NET MVVM Backend Architecture

## MVVM in CrystalMagica

CrystalMagica uses MVVM as a backend architecture pattern for its Godot 4.6 game client. This is NOT WPF/MAUI MVVM.

- **Models** live in the shared `CrystalMagica` library (`CrystalMagica.Models`). These are wire types like `CharacterData`, `CharacterAction`, and `MoveBegin` used by both client and server.
- **ViewModels** live in `CrystalMagica.Game/ViewModels/`. They are client-side only and driven by System.Reactive. `MainViewModel`, `RemoteCharacterVM`, `LocalPlayerCharacterVM`.
- **Views** are Godot nodes in `CrystalMagica.Game/Views/`. `PlayerNode` (base CharacterBody3D), `RemotePlayerNode`, `ItemsNode`.
- The server has no ViewModels. MapHub owns models directly.

## System.Reactive Patterns

- `Subject<T>` is used for event streams that receive pushes from the network layer. `RemoteCharacterVM.Updates` is a `Subject<CharacterAction>` that receives actions via `OnNext()` from `MainViewModel.HandleMessage()`.
- `IObservable<T>` is used for derived state. `RemoteCharacterVM.Position` is derived from `Updates` via `.Select(x => x.Position).StartWith(data.Position)`, producing a position stream that starts with the spawn position and updates on each action.
- `ValueSubject<T>` wraps `BehaviorSubject<T>` to expose a `.Value` property with get/set semantics. Setting `.Value` calls `OnNext()` internally. Used for `MainViewModel.Status` and `MainViewModel.Player`.

## DynamicData / SourceCache

`MainViewModel` uses `SourceCache<RemoteCharacterVM, Guid>` keyed by `x => x.Id` for the collection of remote players. The connection pipeline:

```csharp
RemoteCharacters.Connect().Bind(out var list).Subscribe();
RemoteCharacterList = list; // ReadOnlyObservableCollection<RemoteCharacterVM>
```

`Bind()` bridges the SourceCache changeset stream into a `ReadOnlyObservableCollection` that implements `INotifyCollectionChanged`. Mutations happen through `AddOrUpdate()` and `Remove()` on the SourceCache; the bound collection updates automatically.

`ObservableDictionary<TValue, TKey>` is a helper that wraps SourceCache with the same Connect/Bind pattern and forwards `CollectionChanged` events from the bound collection.

## ItemsNode Pattern

`ItemsNode` is a generic `Node3D` that observes a ViewModel collection and manages child scene instances:

- Has an `[Export] PackedScene NodeTemplate` set in the Godot editor.
- `Items` property accepts any `INotifyCollectionChanged`. Setting it subscribes to `CollectionChanged`.
- On `Add`: instantiates `NodeTemplate`, casts to `IBindable`, calls `Bind(item)`, then `AddChild(node)`. Tracks in `_nodesByItem` dictionary.
- On `Remove`: looks up the node by VM reference, calls `QueueFree()`, removes from dictionary.
- On `Reset`: despawns all existing nodes (`QueueFree()`), clears dictionary, then re-creates nodes for all current items.

This lets you bind `ItemsNode.Items = mainViewModel.RemoteCharacterList` and have nodes spawn/despawn reactively as the SourceCache changes.

## IBindable Interface

Defined in `ItemsNode.cs`. Views implement `IBindable` to receive their ViewModel:

```csharp
public interface IBindable { void Bind(object viewModel); }
```

`RemotePlayerNode` implements both `IBindable` (untyped, for ItemsNode) and a typed `Bind(RemoteCharacterVM viewModel)` that does the actual wiring. The untyped overload casts and delegates. Inside `Bind()`, Rx subscriptions are set up: subscribing to `Position` to update `Position`, subscribing to `Updates` to dispatch `Jump()`, `StopMoving()`, and `MoveBegin()` on the `PlayerNode` base class.

## LocalPlayerCharacterVM vs RemoteCharacterVM

- **LocalPlayerCharacterVM** holds plain properties (`Position` as `Godot.Vector3`, `Color`). It captures local input and sends actions to the server via `serverClient.Map.RelayCharacterAction()`. No Rx observables -- the local view reads its properties directly.
- **RemoteCharacterVM** is Rx-driven. It exposes `Subject<CharacterAction> Updates` and derives `IObservable<Vector2> Position`. The view subscribes to these streams to replicate remote player state.
- Both feed `PlayerNode` (the shared `CharacterBody3D` base with physics, gravity, and `IInputAction` methods) but through different paths: local drives it from input, remote drives it from Rx subscriptions.

## Thread Safety

All Rx subscriptions fire on the main thread. `MainViewModel.Process()` reads from `socketManager.Incoming.Reader` (a Channel) and calls `OnNext()` on subjects synchronously. `Process()` is called from `_Process()` in the Godot scene tree, which runs on the main thread every frame. Because all `OnNext()` calls originate from `Process()`, subscribers never fire on a background thread. The socket read loop (`socketManager.Run()`) writes to the Channel from a background task, but the Channel decouples it from the main thread consumer.
