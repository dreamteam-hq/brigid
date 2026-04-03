---
name: Godot Input System
description: Input handling architecture for Godot 4.6 C# — InputMap, action-based input, hybrid polling+events, multiplayer input routing
triggers:
  - input
  - InputMap
  - input action
  - input handling
  - keyboard input
  - gamepad input
  - input buffer
category: gamedev
---

# Godot 4.6 C# Input System Reference

## InputMap Fundamentals

All bindings live in Project Settings > Input Map. Code references actions by name, never raw keycodes. Decouples config from logic, supports runtime rebinding.

```csharp
float horizontal = Input.GetAxis("move_left", "move_right"); // -1..1
bool jumping = Input.IsActionJustPressed("jump");             // first frame only
bool holding = Input.IsActionPressed("sprint");               // while held
float trigger = Input.GetActionStrength("accelerate");        // 0..1, analog-aware
```

`GetAxis` composites two actions. `GetActionStrength` respects deadzone curves. Never use `Input.IsKeyPressed(Key.W)` in gameplay code.

## Hybrid Polling + Events

Poll continuous state in `_PhysicsProcess`, handle discrete events in `_UnhandledInput`.

**Polling (continuous)** -- movement, camera look, held triggers. Every physics tick for determinism.

```csharp
public override void _PhysicsProcess(double delta)
{
    var dir = new Vector2(Input.GetAxis("move_left", "move_right"),
                          Input.GetAxis("move_up", "move_down"));
    _velocity = dir * Speed;
}
```

**Events (discrete)** -- jump, interact, menu toggle. Once per event, no missed inputs between ticks.

```csharp
public override void _UnhandledInput(InputEvent ev)
{
    if (ev.IsActionPressed("jump")) { _jumpRequested = true; GetViewport().SetInputAsHandled(); }
}
```

## Input Dispatch Order

Each `InputEvent` flows through the focused viewport:
1. **`_Input`** -- highest priority, raw access. Rarely needed in gameplay.
2. **`_ShortcutInput`** -- `Shortcut` resources on Controls.
3. **`_UnhandledKeyInput`** -- key/joypad events no UI consumed.
4. **`_UnhandledInput`** -- everything not handled above.

UI `Control` nodes process between `_Input` and `_UnhandledKeyInput`. A focused `LineEdit` swallows keystrokes before `_UnhandledInput` sees them. Gameplay input belongs in `_UnhandledInput`.

## CrystalMagica Pattern

Decouple input capture from movement via an interface:

```csharp
public interface IInputState
{
    Vector2 MoveDirection { get; }
    bool JumpPressed { get; }
    bool SprintHeld { get; }
}
```

**InputController** (Node on player scene): `UpdateContinuousState()` polls axes in `_PhysicsProcess`. `_UnhandledInput` captures discrete events, sets one-shot flags. `ConsumeFrame()` resets flags after coordinator reads them. **PlayerNode** (coordinator):

```csharp
public override void _PhysicsProcess(double delta)
{
    _inputController.UpdateContinuousState();
    _movementController.Apply(_inputController, delta);
    _inputController.ConsumeFrame();
}
```

`MovementController.Apply(IInputState, double)` has zero knowledge of Godot input APIs -- pure data in, testable, reusable for AI or network entities.

## Multiplayer Input Authority

Local: `InputController` captures input, serializes `IInputState`, sends via RPC/MessagePack. Remote: `NetworkInputController` implements `IInputState` from deserialized packets. Same `MovementController.Apply()`, same physics.

```
LocalPlayer:  InputController        -> IInputState -> MovementController -> physics
RemotePlayer: NetworkInputController -> IInputState -> MovementController -> physics
```

Authority gate: `GetMultiplayerAuthority() == Multiplayer.GetUniqueId()` controls `InputController` activation.

## Input Buffering

`IsActionJustPressed` has a single-frame window. For platformer-grade responsiveness, buffer explicitly:

```csharp
private readonly float[] _jumpBuffer = new float[6]; // ~100ms at 60fps
private int _bufferIdx;
public void RecordJump(bool pressed, float delta)
{
    _bufferIdx = (_bufferIdx + 1) % _jumpBuffer.Length;
    _jumpBuffer[_bufferIdx] = pressed ? BufferDuration : Math.Max(0, _jumpBuffer[_bufferIdx] - delta);
}
public bool ConsumeBufferedJump()
{
    if (!_jumpBuffer.Any(t => t > 0f)) return false;
    Array.Clear(_jumpBuffer, 0, _jumpBuffer.Length);
    return true;
}
```

4-6 frames (~66-100ms) standard for platformers. Coyote time is the complement -- buffer the ground state, not the input.
