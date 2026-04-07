---
name: system-reactive-dynamicdata
description: >
  System.Reactive and DynamicData patterns for .NET 10 game clients. Covers
  Subject, BehaviorSubject, ValueSubject, IObservable operators, SourceCache,
  collection binding, and Godot node lifecycle integration. Load when working
  with reactive pipelines, ViewModel bindings, SourceCache, DynamicData,
  IObservable, Subject, Subscribe, Bind, or INotifyCollectionChanged in C# 14.
category: reference
tags:
  domain: [dotnet, gamedev]
  depth: specialized
triggers:
  - System.Reactive
  - DynamicData
  - SourceCache
  - IObservable
  - Subject
  - BehaviorSubject
  - reactive pipeline
  - Subscribe
  - INotifyCollectionChanged
version: "1.0.0"
---

# System.Reactive and DynamicData for .NET 10 Game Clients

## MVVM in CrystalMagica

CrystalMagica uses MVVM as a backend architecture pattern for its Godot 4.6 game client. This is NOT WPF/MAUI MVVM.

- **Models** live in the shared `CrystalMagica` library (`CrystalMagica.Models`). These are wire types like `CharacterData`, `CharacterAction`, and `MoveBegin` used by both client and server.
- **ViewModels** live in `CrystalMagica.Game/ViewModels/`. They are client-side only and driven by System.Reactive. `MainViewModel`, `RemoteCharacterVM`, `LocalPlayerCharacterVM`.
- **Views** are Godot nodes in `CrystalMagica.Game/Views/`. `PlayerNode` (base CharacterBody3D), `RemotePlayerNode`, `ItemsNode`.
- The server has no ViewModels. MapHub owns models directly.

### LocalPlayerCharacterVM vs RemoteCharacterVM

- **LocalPlayerCharacterVM** holds plain properties (`Position` as `Godot.Vector3`, `Color`). It captures local input and sends actions to the server via `serverClient.Map.RelayCharacterAction()`. No Rx observables — the local view reads its properties directly.
- **RemoteCharacterVM** is Rx-driven. It exposes `Subject<CharacterAction> Updates` and derives `IObservable<Vector2> Position`. The view subscribes to these streams to replicate remote player state.
- Both feed `PlayerNode` (the shared `CharacterBody3D` base with physics, gravity, and `IInputAction` methods) but through different paths: local drives it from input, remote drives it from Rx subscriptions.

## Subject Types

Three subject types serve distinct roles. Choosing the wrong one produces subtle bugs.

| Type | Has `.Value` | Replays to Late Subscribers | Use For |
|------|:-:|:-:|---------|
| `Subject<T>` | No | No | Discrete events: network messages, input actions |
| `BehaviorSubject<T>` | Yes (read-only) | Last value | State that always has a current value |
| `ValueSubject<T>` | Yes (read/write) | Last value | CrystalMagica wrapper over `BehaviorSubject<T>` with get/set `.Value` |

### Subject\<T\> — Event Streams

Use when there is no meaningful "current value." Character actions are events, not state.

```csharp
// Declaration
public Subject<CharacterAction> Updates { get; set; } = new();

// Producer pushes events (MainViewModel.HandleMessage)
target.Value.Updates.OnNext(action);

// Consumer subscribes (RemotePlayerNode.Bind)
_ = viewModel.Updates.Subscribe(x =>
{
    if (x.Action is CharacterActions.Jump)
        Jump();
    else if (x.Action is CharacterActions.Stop)
        StopMoving();
    else if (x is MoveBegin moveBegin)
        MoveBegin(moveBegin);
});
```

### ValueSubject\<T\> — Mutable State with Notifications

Wraps `BehaviorSubject<T>`. Setting `.Value` calls `OnNext()` internally. Implements `ISubject<T>`, so it is both an observable and an observer.

```csharp
// CrystalMagica.Reactive.ValueSubject<T>
public class ValueSubject<T> : ISubject<T>
{
    private BehaviorSubject<T> subject;

    public T Value
    {
        get => subject.Value;
        set => subject.OnNext(value); // set triggers OnNext
    }

    public ValueSubject(T value = default)
    {
        subject = new BehaviorSubject<T>(value);
    }
    // ISubject<T> delegation: Subscribe, OnNext, OnError, OnCompleted
}
```

Usage in MainViewModel:

```csharp
public ValueSubject<string> Status { get; set; } = new();
public ValueSubject<LocalPlayerCharacterVM> Player { get; set; } = new();

// Property-style write triggers OnNext
Status.Value = "Connecting...";

// Direct OnNext also works
Status.OnNext("Connected");

// Subscribe to observe changes
_ = viewModel.Player
    .Where(x => x is not null)
    .Subscribe(Player.Bind);
```

**Decision rule:** Use `ValueSubject<T>` when you need imperative read/write access to current state AND reactive notifications. Use `Subject<T>` when there is no "current value" concept.

## IObservable Operators

### Deriving State from Event Streams

Chain operators to transform events into state. `StartWith` provides the initial value so subscribers receive a value immediately on subscription.

```csharp
// RemoteCharacterVM constructor
Position = Updates
    .Select(x => x.Position)
    .StartWith(data.Position);
```

The resulting `IObservable<Vector2>` emits the spawn position first, then every subsequent position from incoming actions.

### Operator Reference

| Operator | What It Does | When to Use |
|----------|-------------|-------------|
| `.Select(x => ...)` | Transform each element | Extract a field from a composite event |
| `.Where(x => ...)` | Filter elements | Skip nulls, filter by type |
| `.StartWith(value)` | Emit an initial value before the source | Derived state that needs a starting value |
| `.Subscribe(onNext)` | Terminal — attach an observer | Wire the pipeline to a side effect |
| `.CombineLatest(other, (a, b) => ...)` | Merge latest values from two streams | Derived state from multiple inputs |
| `.Merge(other)` | Interleave two streams into one | Flatten independent event sources |
| `.DistinctUntilChanged()` | Suppress consecutive duplicates | Avoid redundant updates |
| `.Throttle(TimeSpan)` | Rate-limit emissions | Prevent flooding downstream |

**Async interop:** `Observable.FromAsync(() => TaskMethod())` converts a `Task<T>` to `IObservable<T>`. `await observable.FirstAsync()` converts back.

## DynamicData SourceCache

`SourceCache<TObject, TKey>` is a keyed reactive collection from DynamicData. All mutations flow through the cache; bound collections update automatically.

### The Canonical Pipeline

```csharp
// Declare cache and bound collection
private SourceCache<RemoteCharacterVM, Guid> RemoteCharacters { get; set; }
    = new(x => x.Id);
public ReadOnlyObservableCollection<RemoteCharacterVM> RemoteCharacterList { get; }

// Wire once in constructor
_ = RemoteCharacters
    .Connect()
    .Bind(out var list)
    .Subscribe();

RemoteCharacterList = list;
```

`Connect()` returns `IObservable<IChangeSet<T, K>>`. `Bind(out var list)` materializes the changeset stream into a `ReadOnlyObservableCollection<T>`. `Subscribe()` activates the pipeline.

### SourceCache Operations

| Operation | Code | Notes |
|-----------|------|-------|
| Add or update | `cache.AddOrUpdate(item)` | Upsert by key selector |
| Remove by key | `cache.Remove(key)` | |
| Lookup by key | `cache.Lookup(key)` | Returns `Optional<T>` — check `.HasValue` |
| Observe changes | `cache.Connect()` | Returns changeset stream |

### Lookup Pattern

`Lookup` returns `Optional<T>`, not a nullable. Always check `.HasValue`:

```csharp
var target = RemoteCharacters.Lookup(action.CharacterId);

if (!target.HasValue)
{
    target = Enemies.Lookup(action.CharacterId);
}

if (target.HasValue)
{
    target.Value.Updates.OnNext(action);
}
```

### Multiple Caches with Different Views

Use separate `SourceCache` instances when entities have different lifecycles or routing:

```csharp
private SourceCache<RemoteCharacterVM, Guid> RemoteCharacters { get; set; }
    = new(x => x.Id);
private SourceCache<RemoteCharacterVM, Guid> Enemies { get; set; }
    = new(x => x.Id);

// Each gets its own pipeline
_ = RemoteCharacters.Connect().Bind(out var list).Subscribe();
RemoteCharacterList = list;

_ = Enemies.Connect().Bind(out var enemyList).Subscribe();
EnemiesList = enemyList;
```

### Filtered and Sorted Views

Apply DynamicData operators between `Connect()` and `Bind()`:

```csharp
// Filter
_ = RemoteCharacters.Connect()
    .Filter(x => x.IsAlive)
    .Bind(out var alive).Subscribe();

// Sort
_ = RemoteCharacters.Connect()
    .Sort(SortExpressionComparer<RemoteCharacterVM>
        .Ascending(x => x.Id))
    .Bind(out var sorted).Subscribe();
```

Transform and auto-refresh for property-change-driven re-evaluation:

```csharp
// Transform -- project to a different type
_ = RemoteCharacters.Connect()
    .Transform(vm => new MinimapBlip(vm.Id, vm.Position))
    .Bind(out var blips).Subscribe();

// AutoRefresh -- re-evaluate filter when property changes
_ = RemoteCharacters.Connect()
    .AutoRefresh(x => x.IsAlive)
    .Filter(x => x.IsAlive)
    .Bind(out var aliveOnly).Subscribe();
```

## ObservableDictionary Wrapper

`ObservableDictionary<TValue, TKey>` wraps SourceCache with the Connect/Bind pattern and forwards `INotifyCollectionChanged`:

```csharp
public class ObservableDictionary<TValue, TKey> : INotifyCollectionChanged
{
    private SourceCache<TValue, TKey> dictionary { get; set; }
    public ReadOnlyObservableCollection<TValue> Values { get; }

    public ObservableDictionary(Func<TValue, TKey> keySelector)
    {
        dictionary = new(keySelector);
        _ = dictionary.Connect().Bind(out var values).Subscribe();
        Values = values;
        (Values as INotifyCollectionChanged).CollectionChanged +=
            (s, e) => CollectionChanged?.Invoke(s, e);
    }

    public TValue this[TKey key]
    {
        get => dictionary.Lookup(key).Value;
        set => dictionary.AddOrUpdate(value);
    }
}
```

Use when you need dictionary-style `[]` access AND collection-changed notifications.

## Collection Binding with Godot Nodes

### ItemsNode Pattern

`ItemsNode` is a generic `Node3D` that observes a ViewModel collection and manages child scene instances:

- Has an `[Export] PackedScene NodeTemplate` set in the Godot editor.
- `Items` property accepts any `INotifyCollectionChanged`. Setting it subscribes to `CollectionChanged`.
- **Add** — instantiate `NodeTemplate`, cast to `IBindable`, call `Bind(item)`, then `AddChild(node)`. Tracks in `_nodesByItem` dictionary.
- **Remove** — look up the node by VM reference, call `QueueFree()`, remove from dictionary.
- **Reset** — despawn all existing nodes (`QueueFree()`), clear dictionary, then re-create nodes for all current items.

```csharp
// Main._Ready() -- wire ItemsNodes to ViewModel collections
RemoteCharacters.Items = viewModel.RemoteCharacterList;
Enemies.Items = viewModel.EnemiesList;
```

`ItemsNode.Items` uses the C# 14 `field` keyword for change tracking:

```csharp
public INotifyCollectionChanged Items
{
    get => field;
    set
    {
        field?.CollectionChanged -= HandleCollectionChanged;
        field = value;
        field.CollectionChanged += HandleCollectionChanged;
    }
}
```

### IBindable Interface

Views implement `IBindable` to receive their ViewModel from `ItemsNode`:

```csharp
public interface IBindable { void Bind(object viewModel); }
```

A view provides both the untyped overload (for `ItemsNode`) and a typed overload (for direct wiring). The typed `Bind` sets up all Rx subscriptions:

```csharp
// RemotePlayerNode : PlayerNode, IBindable
public void Bind(RemoteCharacterVM viewModel)
{
    Mesh.SetSurfaceOverrideMaterial(0,
        new StandardMaterial3D { AlbedoColor = viewModel.Color });

    _ = viewModel.Position.Subscribe(
        x => Position = x.ToGodot3D());

    _ = viewModel.Updates.Subscribe(x =>
    {
        if (x.Action is CharacterActions.Jump) Jump();
        else if (x.Action is CharacterActions.Stop) StopMoving();
        else if (x is MoveBegin moveBegin) MoveBegin(moveBegin);
    });
}
```

The untyped overload casts and delegates:

```csharp
public void Bind(object viewModel)
{
    if (viewModel is not RemoteCharacterVM typedVM)
        throw new Exception("You bound the wrong thing");
    Bind(typedVM);
}
```

### Label Binding Extension

```csharp
public static class BindExtensions
{
    public static IDisposable Bind(this Label label,
        IObservable<string> observable)
        => observable.Subscribe(value => label.Text = value);
}

// Usage in Main._Ready()
_ = StatusLabel.Bind(viewModel.Status);
```

This pattern generalizes: write a `Bind` extension for any Godot property that should track an observable.

## Subscription Lifecycle and Disposal

### Threading Model

All Rx subscriptions fire on the main thread. The architecture guarantees this:

1. `SocketManager.Run()` reads WebSocket frames on a background task
2. Frames go into a `Channel<MemoryStream>` (thread-safe)
3. `MainViewModel.Process()` drains the channel inside `_Process()` (main thread)
4. `OnNext()` calls happen inside `Process()` — subscribers always execute on the main thread

**No `ObserveOn` is needed.** The channel decouples the background socket from the main-thread Rx pipeline.

### Disposal Strategies

The codebase currently uses `_ =` discard universally — this is safe when subscriptions live for the node's full lifetime.

| Scenario | Strategy |
|----------|----------|
| Subscription lives for node lifetime | `_ =` discard — GC-safe when source completes |
| Subscription must be cut early | Store `IDisposable`, call `.Dispose()` in `_ExitTree()` |
| Multiple subscriptions per node | **RECOMMENDED:** `CompositeDisposable` — dispose all at once |
| SourceCache pipeline | `_ = cache.Connect().Bind(...).Subscribe()` — lives for VM lifetime |

> **RECOMMENDED patterns** for explicit disposal (`CompositeDisposable`, `DisposeWith`,
> `_ExitTree` teardown), Godot lifecycle integration, error handling (`Catch`, `Retry`),
> and testing Rx code: see [references/advanced-patterns.md](references/advanced-patterns.md).

## Anti-Patterns

### Subscribing in _Process()

Creates a new subscription every frame. Subscriptions accumulate, callbacks multiply.

```csharp
// BAD
public override void _Process(double delta)
{
    viewModel.Position.Subscribe(x => Position = x.ToGodot3D());
}

// GOOD -- subscribe once in Bind() or _Ready()
public override void _Ready()
{
    _ = viewModel.Position.Subscribe(x => Position = x.ToGodot3D());
}
```

### Using Subject When IObservable Suffices

Subjects are mutable variables. Use them at boundaries only (network input, user input). Derive everything else with operators.

```csharp
// BAD -- unnecessary Subject for derived state
public Subject<Vector2> Position { get; set; } = new();
// ... somewhere: Updates.Subscribe(x => Position.OnNext(x.Position));

// GOOD -- derive with operators, no extra Subject
public IObservable<Vector2> Position { get; set; }
Position = Updates.Select(x => x.Position).StartWith(data.Position);
```

### Forgetting StartWith

Without `StartWith`, subscribers receive nothing until the first event. Nodes spawn at origin.

```csharp
// BAD -- no initial value
Position = Updates.Select(x => x.Position);

// GOOD
Position = Updates.Select(x => x.Position).StartWith(data.Position);
```

### Mutating the Bound Collection

`ReadOnlyObservableCollection` from `Bind()` is read-only. All mutations go through `SourceCache`. Never try to add/remove items on the bound collection.

### Duplicate Pipelines on the Same Cache

Multiple `Connect()` calls are fine with different operators. Identical pipelines are waste — bind once, share the result.

### Swallowing Errors

Always pass an `onError` handler to `Subscribe`. Without it, an error silently kills the subscription:

```csharp
// BAD: .Subscribe(HandleUpdate);
// GOOD:
.Subscribe(onNext: HandleUpdate,
    onError: ex => GD.PrintErr(ex.Message));
```

## Testing Rx Code

> **Recommended approach** — no Rx tests currently exist in CrystalMagica.
> Use `Microsoft.Reactive.Testing.TestScheduler` for deterministic time. Subscribe
> synchronously and assert immediately — `StartWith` and `Subject.OnNext` emit inline.
> For examples, see [references/advanced-patterns.md](references/advanced-patterns.md).
