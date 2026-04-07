---
name: dotnet-scripts
description: Covers patterns and gotchas for .NET script files with shebang headers, including package references, the --help interception limitation, and interactive console guards. Load when authoring or modifying scripts in the scripts/ directory.
triggers:
  - dotnet script
  - shebang
  - .cs script
  - script file
  - scripts directory
  - package references script
  - interactive console
  - dotnet run
version: "1.0.0"
---

# .NET Script Files (dotnet script.cs)

Patterns and gotchas for `.cs` files with `#!/usr/bin/env dotnet` shebang, used in `scripts/`.

## Package references

```csharp
#:package Spectre.Console@0.54.0
#:package Spectre.Console.Cli@0.53.1
```

These go at the top of the file, after the shebang. They're restored automatically on first run.

## --help is intercepted by the SDK

`dotnet scripts/foo.cs --help` shows `dotnet run` help, not the script's help. This is a known .NET SDK limitation. Subcommand help works fine: `dotnet scripts/foo.cs kill --help`.

There is no workaround from script code. Document this limitation when relevant.

## Interactive console guard

`Console.KeyAvailable` throws `InvalidOperationException` when stdin is redirected (CI, piped commands, tool execution). Any interactive TUI must:

1. Guard entry with `Console.IsInputRedirected`
2. Wrap the key-polling loop in try/catch for mid-session detach

```csharp
if(Console.IsInputRedirected)
{
    AnsiConsole.MarkupLine("[red]Requires an interactive terminal.[/]");
    return;
}
```

## Top-level statements + classes

In .NET script files, define classes after the top-level statements. All types are in the global namespace. `CommandApp<T>` from Spectre.Console.Cli works fine with this pattern.

## Always verify compilation

After writing or modifying a script, run it immediately to catch compile errors. Don't declare done until it executes successfully.
