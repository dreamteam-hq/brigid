# Advanced Patterns: Disposal, Error Handling, and Testing

> These are **recommended patterns** — not yet implemented in CrystalMagica.
> The codebase currently uses `_ =` discard universally. The patterns here
> represent best-practice guidance for when subscription lifecycle management
> becomes more complex.

## Disposal Strategies in Depth

### Current State: `_ =` Discard

CrystalMagica's codebase uses the simplest disposal strategy — discard the `IDisposable` returned by `Subscribe()`:

```csharp
_ = viewModel.Position.Subscribe(x => Position = x.ToGodot3D());
_ = viewModel.Updates.Subscribe(HandleAction);
_ = cache.Connect().Bind(out var list).Subscribe();
```

This works when:
- The subscription lives for the full lifetime of the subscribing node
- The source observable completes or is GC'd alongside the subscriber
- There is no need to cut a subscription short

### Recommended: CompositeDisposable + DisposeWith

When a node subscribes to multiple observables, `CompositeDisposable` provides deterministic cleanup:

```csharp
using System.Reactive.Disposables;

private readonly CompositeDisposable _subscriptions = new();

public void Bind(RemoteCharacterVM viewModel)
{
    viewModel.Position
        .Subscribe(x => Position = x.ToGodot3D())
        .DisposeWith(_subscriptions);

    viewModel.Updates
        .Subscribe(HandleAction)
        .DisposeWith(_subscriptions);
}

public override void _ExitTree() => _subscriptions.Dispose();
```

`DisposeWith` is an extension method from `System.Reactive.Disposables` that adds the `IDisposable` to a `CompositeDisposable`. When the composite is disposed, every subscription it holds is unsubscribed at once.

### Recommended: SerialDisposable

When a subscription is replaced over time (e.g., rebinding to a new ViewModel):

```csharp
private readonly SerialDisposable _positionSub = new();

public void Bind(RemoteCharacterVM viewModel)
{
    // Automatically disposes the previous subscription
    _positionSub.Disposable = viewModel.Position
        .Subscribe(x => Position = x.ToGodot3D());
}

public override void _ExitTree() => _positionSub.Dispose();
```

`SerialDisposable` disposes the previously-held `IDisposable` whenever a new one is assigned — ideal for rebind scenarios where a view can be recycled.

### Godot Node Lifecycle and Disposal

Understanding Godot's node lifecycle is critical for correct Rx disposal:

```
_EnterTree()     Node added to scene tree
    |
_Ready()         Node and all children are in tree (called once, unless re-entering)
    |
_Process()       Called every frame while in tree
    |
_ExitTree()      Node removed from scene tree
    |
[GC / QueueFree] Object freed
```

#### Key lifecycle rules for Rx subscriptions:

1. **Subscribe in `_Ready()` or `Bind()`** — These run once when the node is prepared. Never subscribe in `_Process()` (creates a new subscription every frame).

2. **Dispose in `_ExitTree()`** — This fires when a node is removed from the tree, whether by `QueueFree()`, reparenting, or scene change. This is the correct teardown point.

3. **`_ExitTree()` fires before GC** — If you rely on GC to clean up subscriptions, there is a window between tree removal and actual collection where callbacks can still fire on a detached node. Accessing Godot properties on a freed node crashes.

4. **`QueueFree()` is deferred** — When `ItemsNode` handles a `Remove` event and calls `QueueFree()`, the node is not freed immediately. It is freed at the end of the current frame. Subscriptions can still fire during this window.

5. **Re-entering the tree** — If a node is removed and re-added (without `QueueFree`), `_ExitTree()` fires on removal and `_EnterTree()` fires on re-add. But `_Ready()` does NOT fire again unless `RequestReady()` was called. If subscriptions were disposed in `_ExitTree()`, they must be re-created in `_EnterTree()` for nodes that can re-enter.

#### Disposal pattern for re-entrant nodes:

```csharp
private CompositeDisposable _subscriptions;

public override void _EnterTree()
{
    _subscriptions = new CompositeDisposable();
    // Re-subscribe if ViewModel is already bound
    if (_viewModel is not null)
        BindSubscriptions(_viewModel);
}

public override void _ExitTree()
{
    _subscriptions?.Dispose();
    _subscriptions = null;
}

private void BindSubscriptions(RemoteCharacterVM viewModel)
{
    viewModel.Position
        .Subscribe(x => Position = x.ToGodot3D())
        .DisposeWith(_subscriptions);
}
```

#### Disposal pattern for SourceCache pipelines:

SourceCache pipelines in ViewModels typically live for the ViewModel's entire lifetime. They do not need per-node disposal. The ViewModel should implement `IDisposable` if it owns a `SourceCache`:

```csharp
public class MainViewModel : IDisposable
{
    private readonly CompositeDisposable _cleanup = new();
    private SourceCache<RemoteCharacterVM, Guid> RemoteCharacters { get; set; }
        = new(x => x.Id);

    public MainViewModel()
    {
        RemoteCharacters.Connect()
            .Bind(out var list)
            .Subscribe()
            .DisposeWith(_cleanup);

        RemoteCharacterList = list;
    }

    public void Dispose() => _cleanup.Dispose();
}
```

#### When `_ =` discard is safe vs. when it is not:

| Scenario | `_ =` Safe? | Why |
|----------|:-----------:|-----|
| SourceCache pipeline in ViewModel ctor | Yes | Lives for ViewModel lifetime |
| Subscribe in `_Ready()`, node never removed | Yes | GC handles both |
| Subscribe in `Bind()`, node is `QueueFree`'d on remove | Risky | Callbacks fire on freed node during deferred-free window |
| Subscribe to a long-lived Subject from a short-lived node | No | Subscription keeps node alive, memory leak |
| Subscribe in `_EnterTree()`, node re-enters tree | No | Old subscriptions accumulate on each re-entry |

### CancellationToken Interop

For bridging `IDisposable` subscriptions with `async`/`await` cancellation:

```csharp
private CancellationTokenSource _cts = new();

public override void _Ready()
{
    _ = viewModel.Position
        .TakeUntil(Observable.Create<Unit>(observer =>
            new CancellationDisposable(_cts)))
        .Subscribe(x => Position = x.ToGodot3D());
}

public override void _ExitTree() => _cts.Cancel();
```

The simpler approach — use `TakeUntil` with a signal observable:

```csharp
private readonly Subject<Unit> _destroyed = new();

public override void _ExitTree()
{
    _destroyed.OnNext(Unit.Default);
    _destroyed.OnCompleted();
}

// All subscriptions auto-complete when node exits tree
_ = viewModel.Position
    .TakeUntil(_destroyed)
    .Subscribe(x => Position = x.ToGodot3D());
```

This is analogous to Angular's `takeUntilDestroyed` or RxJava's `autoDispose` pattern. Every subscription using `TakeUntil(_destroyed)` will complete and unsubscribe when `_ExitTree()` fires.

## Error Handling in Pipelines

> **Recommended guidance** — CrystalMagica currently has no error handling in Rx
> pipelines. No `Catch`, `Retry`, or `onError` handlers are used. The patterns
> below represent best practices for production resilience.

### The Problem: Silent Death

An unhandled `OnError` terminates the subscription permanently. The default `Subscribe(onNext)` overload throws on error, but the exception may surface at an unexpected point in the callstack — or in Godot, may crash the game.

```csharp
// Dangerous: error kills the subscription silently
viewModel.Position.Subscribe(x => Position = x.ToGodot3D());

// If Position observable errors, subscription dies.
// Node stops updating. No log. No recovery.
```

### Recommended: Always Pass onError

At minimum, log the error:

```csharp
viewModel.Position.Subscribe(
    onNext: x => Position = x.ToGodot3D(),
    onError: ex => GD.PrintErr($"Position subscription error: {ex.Message}"));
```

### Recommended: Catch with Fallback

`Catch` replaces the errored observable with a fallback. The subscription continues with the fallback values:

```csharp
viewModel.Position
    .Catch<Vector2, Exception>(ex =>
    {
        GD.PrintErr($"Position error: {ex.Message}");
        return Observable.Return(Vector2.Zero);
    })
    .Subscribe(x => Position = x.ToGodot3D());
```

For pipelines that should resume from the original source after an error:

```csharp
viewModel.Position
    .Catch<Vector2, Exception>(ex =>
    {
        GD.PrintErr($"Recovering: {ex.Message}");
        return viewModel.Position; // re-subscribe to original
    })
    .Subscribe(x => Position = x.ToGodot3D());
```

**Caution:** Re-subscribing to the original creates infinite retry if the error is persistent. Use with `Retry(count)` for bounded retries.

### Recommended: Retry for Transient Failures

`Retry(n)` re-subscribes up to `n` times on error. Useful for network-sourced observables:

```csharp
connectionStatus
    .Retry(3)
    .Subscribe(
        onNext: status => UpdateUI(status),
        onError: ex => GD.PrintErr($"Failed after 3 retries: {ex.Message}"));
```

With exponential backoff (requires `System.Reactive`):

```csharp
connectionStatus
    .RetryWhen(errors => errors
        .Select((error, attempt) => (error, attempt))
        .SelectMany(x =>
            x.attempt < 3
                ? Observable.Timer(TimeSpan.FromSeconds(Math.Pow(2, x.attempt)))
                : Observable.Throw<long>(x.error)))
    .Subscribe(
        onNext: status => UpdateUI(status),
        onError: ex => GD.PrintErr($"Exhausted retries: {ex.Message}"));
```

### Error Handling in DynamicData Pipelines

SourceCache pipelines should also be protected. An error in a `Transform` or `Filter` lambda will kill the entire pipeline:

```csharp
// Defensive Transform
RemoteCharacters.Connect()
    .Transform(vm =>
    {
        try { return new MinimapBlip(vm.Id, vm.Position); }
        catch (Exception ex)
        {
            GD.PrintErr($"Transform error for {vm.Id}: {ex.Message}");
            return MinimapBlip.Empty; // sentinel value
        }
    })
    .Filter(blip => blip != MinimapBlip.Empty)
    .Bind(out var blips)
    .Subscribe(
        _ => { },
        ex => GD.PrintErr($"Pipeline error: {ex.Message}"));
```

### Error Isolation Strategy

For complex applications, isolate error domains so one failing pipeline does not cascade:

```csharp
// Each pipeline is independent — error in one does not affect others
_subscriptions.Add(
    viewModel.Position
        .Catch<Vector2, Exception>(ex =>
        {
            GD.PrintErr($"Position: {ex.Message}");
            return Observable.Empty<Vector2>();
        })
        .Subscribe(x => Position = x.ToGodot3D()));

_subscriptions.Add(
    viewModel.Updates
        .Catch<CharacterAction, Exception>(ex =>
        {
            GD.PrintErr($"Updates: {ex.Message}");
            return Observable.Empty<CharacterAction>();
        })
        .Subscribe(HandleAction));
```

## Testing Rx Code

> **Recommended approach** — no Rx tests currently exist in CrystalMagica.
> The patterns below show how to test reactive pipelines effectively.

### Synchronous Testing (No Scheduler Needed)

`StartWith` and `Subject.OnNext` emit inline (synchronously). For most ViewModel tests, you do not need a `TestScheduler`:

```csharp
[TestMethod]
public void Position_StartsWithSpawnPosition()
{
    var data = new CharacterData
        { Position = new Vector2(10, 20) };
    var vm = new RemoteCharacterVM(data);

    Vector2? received = null;
    vm.Position.Subscribe(p => received = p);

    Assert.AreEqual(new Vector2(10, 20), received);
}
```

```csharp
[TestMethod]
public void Position_UpdatesOnAction()
{
    var data = new CharacterData { Position = Vector2.Zero };
    var vm = new RemoteCharacterVM(data);

    var positions = new List<Vector2>();
    vm.Position.Subscribe(p => positions.Add(p));

    vm.Updates.OnNext(
        new CharacterAction { Position = new Vector2(5, 5) });

    // StartWith + one action = 2 emissions
    Assert.AreEqual(2, positions.Count);
    Assert.AreEqual(new Vector2(5, 5), positions[1]);
}
```

### TestScheduler for Time-Dependent Pipelines

When testing `Throttle`, `Delay`, `Timeout`, or `Buffer`, use `Microsoft.Reactive.Testing.TestScheduler` to control virtual time:

```csharp
[TestMethod]
public void ThrottledPosition_EmitsAfterQuietPeriod()
{
    var scheduler = new TestScheduler();
    var subject = new Subject<Vector2>();
    var results = new List<Vector2>();

    subject
        .Throttle(TimeSpan.FromMilliseconds(100), scheduler)
        .Subscribe(p => results.Add(p));

    // Emit rapidly
    scheduler.ScheduleAbsolute(10, () =>
        subject.OnNext(new Vector2(1, 1)));
    scheduler.ScheduleAbsolute(20, () =>
        subject.OnNext(new Vector2(2, 2)));
    scheduler.ScheduleAbsolute(30, () =>
        subject.OnNext(new Vector2(3, 3)));

    // Advance past the throttle window
    scheduler.AdvanceTo(130);

    // Only the last value within the window emits
    Assert.AreEqual(1, results.Count);
    Assert.AreEqual(new Vector2(3, 3), results[0]);
}
```

### Testing SourceCache Pipelines

Verify that SourceCache operations produce the expected bound collection state:

```csharp
[TestMethod]
public void AddOrUpdate_AppearsInBoundCollection()
{
    var cache = new SourceCache<RemoteCharacterVM, Guid>(x => x.Id);
    _ = cache.Connect()
        .Bind(out var list)
        .Subscribe();

    var id = Guid.NewGuid();
    var vm = new RemoteCharacterVM(
        new CharacterData { Id = id, Position = Vector2.Zero });

    cache.AddOrUpdate(vm);

    Assert.AreEqual(1, list.Count);
    Assert.AreEqual(id, list[0].Id);
}

[TestMethod]
public void Remove_DisappearsFromBoundCollection()
{
    var cache = new SourceCache<RemoteCharacterVM, Guid>(x => x.Id);
    _ = cache.Connect()
        .Bind(out var list)
        .Subscribe();

    var id = Guid.NewGuid();
    cache.AddOrUpdate(new RemoteCharacterVM(
        new CharacterData { Id = id }));
    cache.Remove(id);

    Assert.AreEqual(0, list.Count);
}
```

### Testing Filtered Views

```csharp
[TestMethod]
public void FilteredView_ExcludesDeadCharacters()
{
    var cache = new SourceCache<RemoteCharacterVM, Guid>(x => x.Id);
    _ = cache.Connect()
        .AutoRefresh(x => x.IsAlive)
        .Filter(x => x.IsAlive)
        .Bind(out var alive)
        .Subscribe();

    var vm = new RemoteCharacterVM(
        new CharacterData { Id = Guid.NewGuid() })
        { IsAlive = true };

    cache.AddOrUpdate(vm);
    Assert.AreEqual(1, alive.Count);

    vm.IsAlive = false;
    // AutoRefresh triggers re-evaluation
    Assert.AreEqual(0, alive.Count);
}
```

### Testing Error Recovery

```csharp
[TestMethod]
public void Catch_ProvidesFallbackOnError()
{
    var subject = new Subject<Vector2>();
    Vector2? last = null;

    subject
        .Catch<Vector2, Exception>(
            ex => Observable.Return(Vector2.Zero))
        .Subscribe(p => last = p);

    subject.OnNext(new Vector2(1, 1));
    Assert.AreEqual(new Vector2(1, 1), last);

    subject.OnError(new Exception("boom"));
    Assert.AreEqual(Vector2.Zero, last);
}
```

### Test Organization

Structure Rx tests by the class under test, then by the observable property:

```
Tests/
  ViewModels/
    RemoteCharacterVMTests.cs
      Position_StartsWithSpawnPosition()
      Position_UpdatesOnAction()
      Position_IgnoresNonMoveActions()
    MainViewModelTests.cs
      RemoteCharacterList_PopulatesOnAddOrUpdate()
      RemoteCharacterList_RemovesOnDisconnect()
      EnemiesList_RoutesEnemyTypes()
  Reactive/
    ValueSubjectTests.cs
      Value_Set_TriggersOnNext()
      Subscribe_ReceivesCurrentValue()
    ObservableDictionaryTests.cs
      Indexer_AddsToSourceCache()
      CollectionChanged_FiresOnAdd()
```
