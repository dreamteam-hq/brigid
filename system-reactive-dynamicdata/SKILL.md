---
name: system-reactive-dynamicdata
description: >
  System.Reactive and DynamicData patterns for .NET 10 game clients — Subject,
  SourceCache, observable pipelines, collection binding with Godot nodes.
  Load when working with ViewModels, reactive bindings, SourceCache,
  IObservable, Subject, or DynamicData.
  Triggers: System.Reactive, DynamicData, SourceCache, Subject, BehaviorSubject,
  IObservable, reactive, Rx, ValueSubject, observable, Subscribe, Bind.
quality: draft
scope: parameterized
lifecycle:
  status: active
  created: 2026-04-05
---

# System.Reactive and DynamicData

## Quick Reference

### Subject Types — When to Use Which

| Type | Has Current Value | Replays on Subscribe | Use When |
|------|:-:|:-:|----------|
| `Subject<T>` | No | No | Fire-and-forget event stream (network messages, input actions) |
| `BehaviorSubject<T>` | Yes (`.Value`) | Last value | State that always has a value; new subscribers need current state |
| `ReplaySubject<T>` | No | Last N values | Late subscribers need history (chat log, audit trail) |
| `ValueSubject<T>` | Yes (`.Value` get/set) | Last value | CrystalMagica wrapper — get/set syntax over `BehaviorSubject` |

### Essential Operators

| Operator | Purpose | Example |
|----------|---------|---------|
| `Select` | Transform each element | `.Select(x => x.Position)` |
| `Where` | Filter elements | `.Where(x => x is not null)` |
| `StartWith` | Emit initial value before source | `.StartWith(data.Position)` |
| `Subscribe` | Terminal — attach observer | `.Subscribe(x => Position = x)` |
| `CombineLatest` | Merge latest from N streams | `a.CombineLatest(b, (x, y) => ...)` |
| `Merge` | Flatten multiple streams into one | `Observable.Merge(stream1, stream2)` |
| `DistinctUntilChanged` | Suppress consecutive duplicates | `.DistinctUntilChanged()` |
| `Throttle` | Rate-limit emissions | `.Throttle(TimeSpan.FromMs(16))` |
| `ObserveOn` | Switch scheduler | `.ObserveOn(SynchronizationContext.Current)` |
| `Catch` | Handle error, continue with fallback | `.Catch<T, Exception>(ex => fallback)` |
| `Retry` | Resubscribe on error | `.Retry(3)` |

### DynamicData — SourceCache Cheat Sheet

| Operation | Method | Notes |
|-----------|--------|-------|
| Add or update | `cache.AddOrUpdate(item)` | Upsert by key |
| Remove by key | `cache.Remove(key)` | |
| Lookup by key | `cache.Lookup(key)` | Returns `Optional<T>` — check `.HasValue` |
| Observe changes | `cache.Connect()` | Returns `IObservable<IChangeSet<T, K>>` |
| Bind to collection | `.Bind(out var list)` | Produces `ReadOnlyObservableCollection<T>` |
| Full pipeline | `.Connect().Bind(out var list).Subscribe()` | The canonical pattern |

---

## Core Patterns

### 1. Subject for Event Streams

Use `Subject<T>` when the stream has no meaningful "current value" — it represents discrete events. `RemoteCharacterVM.Updates` is a `Subject<CharacterAction>` because character actions are events, not state.

```csharp
public Subject<CharacterAction> Updates { get; set; } = new();

// Producer pushes events
Updates.OnNext(action);

// Consumer subscribes
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

### 2. Deriving State from Events

Chain operators to transform an event stream into a state stream. `StartWith` provides the initial value so the derived observable behaves like a `BehaviorSubject` without needing one.

```csharp
Position = Updates
    .Select(x => x.Position)
    .StartWith(data.Position);
```

Subscribers receive the spawn position immediately, then every subsequent position from actions.

### 3. ValueSubject — BehaviorSubject Wrapper

<!-- [DT-INTERNAL]: ValueSubject is CrystalMagica-specific. Other projects use BehaviorSubject directly or ReactiveUI's ReactiveProperty. -->

`ValueSubject<T>` wraps `BehaviorSubject<T>` to expose `.Value` with get/set semantics. Setting `.Value` calls `OnNext()` internally. Implements `ISubject<T>`.

```csharp
public ValueSubject<string> Status { get; set; } = new();
public ValueSubject<LocalPlayerCharacterVM> Player { get; set; } = new();

Status.Value = "Connecting...";   // property set -> OnNext
Status.OnNext("Connected");      // direct OnNext also works

_ = viewModel.Player.Where(x => x is not null).Subscribe(Player.Bind);
```

**When to use ValueSubject vs Subject:**

| Scenario | Choice |
|----------|--------|
| State with a current value | `ValueSubject<T>` |
| Event stream (no "current" concept) | `Subject<T>` |
| Need `.Value` for imperative reads | `ValueSubject<T>` |
| Derived from another stream | `IObservable<T>` via operators |

### 4. SourceCache — Reactive Collections

`SourceCache<TObject, TKey>` is a keyed reactive collection. The canonical pipeline connects the cache, binds to a `ReadOnlyObservableCollection`, and subscribes to activate.

```csharp
private SourceCache<RemoteCharacterVM, Guid> RemoteCharacters { get; set; } = new(x => x.Id);
public ReadOnlyObservableCollection<RemoteCharacterVM> RemoteCharacterList { get; }

// Constructor — wire the pipeline once
_ = RemoteCharacters.Connect().Bind(out var list).Subscribe();
RemoteCharacterList = list;
```

**Mutations go through the SourceCache, never the bound collection:**

```csharp
RemoteCharacters.AddOrUpdate(remoteVM);      // add/update
RemoteCharacters.Remove(despawnedId);         // remove by key

var target = RemoteCharacters.Lookup(action.CharacterId);  // Optional<T>
if (target.HasValue)
    target.Value.Updates.OnNext(action);
```

### 5. Collection Binding with Godot Nodes (ItemsNode)

<!-- [DT-INTERNAL]: ItemsNode is CrystalMagica-specific. The pattern (INotifyCollectionChanged driving scene instantiation) is portable. -->

`ReadOnlyObservableCollection` from `Bind()` implements `INotifyCollectionChanged`. `ItemsNode` subscribes to `CollectionChanged` and manages child scene instances:

- **Add** — instantiate `PackedScene`, cast to `IBindable`, call `Bind(viewModel)`, `AddChild`
- **Remove** — lookup node by VM reference, `QueueFree()`
- **Reset** — despawn all, re-create from current items

```csharp
// Main._Ready()
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

Views implement `IBindable` to receive their ViewModel:

```csharp
public interface IBindable { void Bind(object viewModel); }

public void Bind(RemoteCharacterVM viewModel)
{
    _ = viewModel.Position.Subscribe(x => Position = x.ToGodot3D());
    _ = viewModel.Updates.Subscribe(x => { /* dispatch actions */ });
}
```

### 6. ObservableDictionary — Reusable SourceCache Wrapper

<!-- [DT-INTERNAL]: ObservableDictionary is CrystalMagica-specific. -->

Wraps SourceCache with Connect/Bind and forwards `INotifyCollectionChanged`.

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
        (Values as INotifyCollectionChanged).CollectionChanged += (s, e) =>
            CollectionChanged?.Invoke(s, e);
    }

    public TValue this[TKey key]
    {
        get => dictionary.Lookup(key).Value;
        set => dictionary.AddOrUpdate(value);
    }
}
```

### 7. Label Binding Extension

```csharp
public static IDisposable Bind(this Label label, IObservable<string> observable)
    => observable.Subscribe(value => label.Text = value);

// Usage: _ = StatusLabel.Bind(viewModel.Status);
```

Generalizes to any Godot node property — write a `Bind` extension that subscribes and sets the property.

---

## Subscription Lifecycle

### Thread Model

All Rx subscriptions fire on the main thread:

1. `SocketManager.Run()` reads WebSocket frames on a background task
2. Frames go into `Channel<MemoryStream>` (thread-safe producer/consumer)
3. `MainViewModel.Process()` drains the channel in `_Process()` (main thread)
4. `OnNext()` calls happen inside `Process()` — subscribers always run on main thread

**No `ObserveOn` needed** — the channel decouples the background socket from the main-thread Rx pipeline.

### Disposal Rules

| Scenario | Strategy |
|----------|----------|
| Subscription lives for node's lifetime | `_ =` — disposed when node exits tree |
| Subscription outlives data source | Store `IDisposable`, dispose in `_ExitTree()` |
| Multiple subscriptions on one node | `CompositeDisposable` — dispose all at once |
| SourceCache pipeline | `_ = cache.Connect().Bind(...).Subscribe()` |

**When you need explicit disposal:**

```csharp
private readonly CompositeDisposable _subscriptions = new();

public void Bind(RemoteCharacterVM viewModel)
{
    viewModel.Position.Subscribe(x => Position = x.ToGodot3D()).DisposeWith(_subscriptions);
    viewModel.Updates.Subscribe(HandleAction).DisposeWith(_subscriptions);
}

public override void _ExitTree() => _subscriptions.Dispose();
```

### Avoiding Leaks

- Never subscribe in `_Process()` — creates a new subscription every frame
- SourceCache pipelines (`Connect().Bind().Subscribe()`) go in the constructor, once
- Guard freed nodes with `IsInstanceValid(this)` in subscription callbacks
- `Subject<T>` holds subscriber references — complete or dispose to break the cycle

---

## Advanced Patterns

### Combining Streams

```csharp
// CombineLatest — recompute when either changes
var healthBar = health.CombineLatest(maxHealth, (cur, max) => (float)cur / max);

// Merge — flatten independent event streams
var allActions = Observable.Merge(
    localActions.Select(a => (Source: "local", Action: a)),
    remoteActions.Select(a => (Source: "remote", Action: a)));
```

### Async/Rx Interop

```csharp
// Task -> Observable
IObservable<JoinMapResponse> response = Observable.FromAsync(() => JoinMapAsync());

// Observable -> Task
JoinMapResponse result = await response.FirstAsync();

// Periodic polling
IObservable<ServerStatus> status = Observable.Interval(TimeSpan.FromSeconds(5))
    .SelectMany(_ => Observable.FromAsync(() => PollStatusAsync()));
```

### Error Handling

An unhandled `OnError` terminates the subscription. Protect long-lived pipelines:

```csharp
// Catch — fallback on error
viewModel.Position
    .Catch<Vector2, Exception>(ex => Observable.Return(Vector2.Zero))
    .Subscribe(x => Position = x.ToGodot3D());

// Retry — resubscribe on error
connectionStatus.Retry(3).Subscribe(
    onNext: status => UpdateUI(status),
    onError: ex => GD.PrintErr($"Failed after 3 retries: {ex.Message}"));

// Do — log errors without consuming them
updates.Do(onError: ex => GD.PrintErr($"Error: {ex.Message}"))
    .Retry().Subscribe(HandleUpdate);
```

### DynamicData — Filtered and Sorted Views

```csharp
// Filter + Sort
_ = RemoteCharacters.Connect()
    .Filter(x => x.IsAlive)
    .Sort(SortExpressionComparer<RemoteCharacterVM>.Ascending(x => x.Id))
    .Bind(out var sortedAlive).Subscribe();

// Transform — project to a different type
_ = RemoteCharacters.Connect()
    .Transform(vm => new MinimapBlip(vm.Id, vm.Position))
    .Bind(out var blips).Subscribe();

// AutoRefresh — re-evaluate when a property changes
_ = RemoteCharacters.Connect()
    .AutoRefresh(x => x.IsAlive).Filter(x => x.IsAlive)
    .Bind(out var aliveOnly).Subscribe();
```

### Testing Rx Code

Use `TestScheduler` from `Microsoft.Reactive.Testing` for deterministic time:

```csharp
[TestMethod]
public void Position_StartsWithSpawnPosition()
{
    var data = new CharacterData { Position = new Vector2(10, 20) };
    var vm = new RemoteCharacterVM(data);
    Vector2? received = null;
    vm.Position.Subscribe(p => received = p);
    Assert.AreEqual(new Vector2(10, 20), received);
}

[TestMethod]
public void Position_UpdatesOnAction()
{
    var data = new CharacterData { Position = Vector2.Zero };
    var vm = new RemoteCharacterVM(data);
    var positions = new List<Vector2>();
    vm.Position.Subscribe(p => positions.Add(p));
    vm.Updates.OnNext(new CharacterAction { Position = new Vector2(5, 5) });
    Assert.AreEqual(2, positions.Count);  // StartWith + action
    Assert.AreEqual(new Vector2(5, 5), positions[1]);
}

[TestMethod]
public void Throttled_Position_SkipsRapidUpdates()
{
    var scheduler = new TestScheduler();
    var subject = new Subject<Vector2>();
    var results = new List<Vector2>();
    subject.Throttle(TimeSpan.FromTicks(100), scheduler).Subscribe(p => results.Add(p));
    subject.OnNext(new Vector2(1, 1));
    scheduler.AdvanceTo(50);
    subject.OnNext(new Vector2(2, 2));
    scheduler.AdvanceTo(150);
    Assert.AreEqual(new Vector2(2, 2), results[0]);
}
```

---

## Anti-Patterns

### Subscribing in _Process()

```csharp
// BAD — new subscription every frame
public override void _Process(double delta)
{
    viewModel.Position.Subscribe(x => Position = x.ToGodot3D());
}
// GOOD — subscribe once in Bind() or _Ready()
```

### Using Subject When IObservable Suffices

```csharp
// BAD — unnecessary Subject for derived state
public Subject<Vector2> Position { get; set; } = new();
Updates.Subscribe(x => Position.OnNext(x.Position));

// GOOD — derive directly with operators
public IObservable<Vector2> Position { get; set; }
Position = Updates.Select(x => x.Position).StartWith(data.Position);
```

Subjects are "mutable variables" of Rx. Use at edges only (network, user input). Derive everything else.

### Forgetting StartWith

```csharp
// BAD — no value until first event; node spawns at origin
Position = Updates.Select(x => x.Position);
// GOOD
Position = Updates.Select(x => x.Position).StartWith(data.Position);
```

### Swallowing Errors

```csharp
// BAD — error kills subscription silently
.Subscribe(x => HandleUpdate(x));
// GOOD — log the error
.Subscribe(onNext: HandleUpdate, onError: ex => GD.PrintErr(ex.Message));
```

### Duplicate Pipelines on Same Cache

```csharp
// BAD — two identical views of same data
_ = cache.Connect().Bind(out var list1).Subscribe();
_ = cache.Connect().Bind(out var list2).Subscribe();
// GOOD — multiple Connect() only when applying different operators
_ = cache.Connect().Bind(out var all).Subscribe();
_ = cache.Connect().Filter(x => x.IsEnemy).Bind(out var enemies).Subscribe();
```
