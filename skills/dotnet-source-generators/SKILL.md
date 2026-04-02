---
name: dotnet-source-generators
description: >
  Expert-level knowledge of C# Incremental Source Generators (Roslyn, .NET 10),
  PR review for generator code, and Godot 4.x C# integration with custom generators.
---

# Skill: C# Source Generators (.NET 10 / Godot 4)

## What This Skill Covers

This skill set gives an AI agent expert-level knowledge of:

1. **C# Incremental Source Generators** (Roslyn, .NET 10, Roslyn 4.14+)
2. **PR review** of source generator code — correctness, performance, and .NET 10 idioms
3. **Godot 4.x C# integration** — how Godot uses generators internally and how to author custom generators for Godot game projects

## Skill Files

| File | Purpose |
|------|---------|
| `SKILL.md` (this file) | Entry point — background, mental model, trigger patterns |
| `01_concepts.md` | Core Roslyn/Generator architecture reference (pipeline, caching, FAWMN, interface-driven patterns, cross-assembly discovery) |
| `02_pr_review.md` | PR review checklist and failure modes (F1-F9 hard failures, W1-W11 warnings) |
| `03_godot_integration.md` | Godot 4 C# generator patterns and recipes |
| `04_dotnet10_features.md` | .NET 10 / Roslyn 4.14 new APIs relevant to generators |
| `05_debugging.md` | Debugging workflows: Rider attach, binlog, step tracking, cache miss diagnosis (macOS-focused) |

---

## Trigger Patterns — When to Load This Skill

Load the **full skill set** when any of the following appear in the task:

- Files referencing `IIncrementalGenerator`, `ISourceGenerator`, `Microsoft.CodeAnalysis`
- `.csproj` with `<OutputItemType>Analyzer</OutputItemType>` or `<IsRoslynComponent>true</IsRoslynComponent>`
- A PR that touches any project under an `Analyzers/`, `Generators/`, or `CodeGen/` folder
- Godot game project using `Godot.NET.Sdk` with custom generator NuGet packages
- Phrases: "source generator", "incremental generator", "code gen", "Roslyn analyzer", "partial class generation", "Godot boilerplate", "AOT Godot", "debug generator", "generator not running", "cache miss", "binlog"

---

## Mental Model (Read First)

```
  USER CODE  ──(compile)──▶  ROSLYN COMPILER
                                    │
                          IncrementalGeneratorDriver
                                    │
                        ┌───────────▼────────────┐
                        │  Initialize() — called  │
                        │  exactly ONCE per host  │
                        └───────────┬────────────┘
                                    │ defines pipeline
                     ┌──────────────▼──────────────┐
                     │  IncrementalValuesProvider<T> │
                     │  (immutable, cached stages)   │
                     └──────────────┬──────────────┘
                                    │ Register outputs
                     ┌──────────────▼──────────────┐
                     │  RegisterSourceOutput()       │
                     │  spc.AddSource(name, text)    │
                     └─────────────────────────────┘
```

**The golden rule**: every stage of the pipeline must produce a **value-equatable** model object. If the model hasn't changed since the last keystroke, the engine short-circuits and skips generation entirely. This is what keeps the IDE fast.

---

## Quick-Reference: API Surface

```csharp
// Project skeleton
[Generator]
public sealed class MyGenerator : IIncrementalGenerator
{
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        // 1. Register constant / post-init output (marker attributes, etc.)
        context.RegisterPostInitializationOutput(ctx =>
            ctx.AddSource("MyAttr.g.cs", ATTRIBUTE_SOURCE));

        // 2. Build pipeline — prefer ForAttributeWithMetadataName (99x faster)
        IncrementalValuesProvider<MyModel?> models = context.SyntaxProvider
            .ForAttributeWithMetadataName(
                "MyNamespace.MyAttribute",
                predicate: static (node, _) => node is ClassDeclarationSyntax,
                transform: static (ctx, _) => BuildModel(ctx))
            .Where(static m => m is not null);

        // 3. Emit source
        context.RegisterSourceOutput(models,
            static (spc, model) => Emit(spc, model!));
    }
}
```

See `01_concepts.md` for the full reference.
