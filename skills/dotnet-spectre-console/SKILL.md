---
name: dotnet-spectre-console
description: Covers Spectre.Console markup escaping, IRenderable namespace, CommandApp Execute signature, live display initialization, and Layout structure. Load when building CLI output, TUI dashboards, or Spectre.Console.Cli command definitions.
triggers:
  - Spectre.Console
  - CLI output
  - TUI dashboard
  - CommandApp
  - IRenderable
  - markup escaping
  - Live display
  - Layout
  - AnsiConsole
version: "1.0.0"
---

# Spectre.Console Patterns

Patterns for Spectre.Console (rendering) and Spectre.Console.Cli (CLI framework), used in `scripts/diag.cs`.

## Package versions (as of 2026-03)

- `Spectre.Console@0.54.0` — rendering (Panel, Table, BarChart, Layout, Live, Markup)
- `Spectre.Console.Cli@0.53.1` — CLI framework (CommandApp, Command<T>). Separate repo, versioned independently.

## Markup escaping

Spectre markup uses `[style]text[/]` syntax. Literal square brackets must be doubled:

```csharp
// WRONG — Spectre tries to parse "x" as a color
cols.Add($"[bold red]{cursor}[{check}][/]");

// RIGHT — renders literal [x] or [ ]
cols.Add($"[bold red]{cursor}[/][[{check}]]");
```

## IRenderable namespace

`IRenderable` is in `Spectre.Console.Rendering`, not `Spectre.Console`. Add the using when returning renderables from helper methods:

```csharp
using Spectre.Console.Rendering;
```

## Command<T>.Execute signature

In Spectre.Console.Cli 0.53.1, the `Execute` override requires three parameters:

```csharp
public override int Execute(CommandContext context, TSettings settings, CancellationToken ct)
```

The two-parameter overload no longer compiles.

## Live display — avoid first-frame flash

Populate the Layout with real data before calling `AnsiConsole.Live(layout).Start()`. If you initialize with placeholder Markup ("Loading..."), it flashes for one frame.

```csharp
// Populate BEFORE entering Live
RefreshDisplay(layout, cpuSampler, killMode);

AnsiConsole.Live(layout)
    .AutoClear(true)
    .Start(ctx => { /* loop */ });
```

## Layout structure

`Layout` divides terminal space using `Ratio()`. Use `SplitRows` for vertical and `SplitColumns` for horizontal division. Access children by name:

```csharp
var layout = new Layout("Root")
    .SplitRows(
        new Layout("Header").Ratio(1),
        new Layout("Content").Ratio(4));

layout["Header"].Update(new Panel(...));
```
