---
name: Godot Signals (C#)
description: C# signal patterns in Godot 4.6 — custom signals, typed delegates, signal bus, cross-scene communication, Rx integration
triggers:
  - signal
  - signals
  - event
  - emit signal
  - connect signal
  - signal bus
  - observer pattern
category: gamedev
version: "1.0.0"
---

# Godot 4.6 C# Signal Patterns

## 1. Built-in Signals

Connect in the editor or in code. Disconnect on cleanup to avoid leaks.

```csharp
button.Pressed += OnButtonPressed;   // connect
button.Pressed -= OnButtonPressed;   // disconnect
```

## 2. Custom Signals

```csharp
[Signal]
public delegate void HealthChangedEventHandler(int newHealth);
```

Godot 4.6 generates `EmitSignalHealthChanged()` from the delegate name. Connect from another node with `player.HealthChanged += OnHealthChanged;`.

## 3. Signal vs Direct Call

- **Signals** for loose coupling — UI reacting to game events, decoupled observers.
- **Direct calls** for tight coupling — coordinator calling controller methods.

CrystalMagica uses direct calls within the coordinator pattern and Rx for cross-system events.

## 4. Signal Bus Singleton

An AutoLoad node that centralizes game-wide events. Avoids deep signal chains through the scene tree.

```csharp
public partial class SignalBus : Node
{
    [Signal]
    public delegate void GamePausedEventHandler(bool paused);
    public static SignalBus Instance { get; private set; }
    public override void _Ready() => Instance = this;
}
```

Use sparingly. Too many signals on one bus becomes spaghetti.

## 5. Async Signal Awaiting

```csharp
await ToSignal(animPlayer, AnimationPlayer.SignalName.AnimationFinished);
```

Useful for cutscenes, animation sequences, and one-shot waits.

## 6. Rx Integration

CrystalMagica uses `System.Reactive` `Subject<T>` instead of Godot signals for ViewModel-to-View communication.

```csharp
// In RemoteCharacterVM
public Subject<CharacterAction> Updates { get; } = new();
Updates.OnNext(new CharacterAction.Move(position));

// In View — subscribe
_vm.Updates
    .OfType<CharacterAction.Move>()
    .Subscribe(action => MoveSprite(action.Position));
```

Why Rx over signals:
- Full type safety (no string-based signal names)
- Composability — `Select`, `OfType`, `CombineLatest`, `Throttle`
- Familiar .NET pattern for C# developers

## 7. Thread Safety

Signals fire on the thread that emits them. If `OnNext` is called from the main thread (`_Process` drain loop), subscribers run on main thread. **Never** emit signals or call `OnNext` from a background thread if subscribers touch nodes — Godot scene tree access is main-thread-only.
