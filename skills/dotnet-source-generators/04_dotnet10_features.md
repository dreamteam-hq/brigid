# 04 — .NET 10 / Roslyn 4.14 New Features for Source Generators

## Overview

.NET 10 ships with Roslyn 4.14. This release added several APIs that directly improve the source generator authoring experience and resolve long-standing pain points.

| Feature | Roslyn Version | .NET SDK Minimum |
|---------|----------------|------------------|
| `AddEmbeddedAttributeDefinition()` | 4.14 | 9.0.300 / .NET 10 preview 4 |
| `[EmbeddedAttribute]` manual definition | 4.14 | 9.0.300 |
| `partial` properties | C# 13 / .NET 9 | .NET 9 SDK |
| `partial` constructors, indexers, events | C# 14 / .NET 10 | .NET 10 SDK |
| Interceptors (non-experimental) | C# 14 | .NET 10 SDK |

---

## 1. Solving the Marker Attribute Problem (Roslyn 4.14)

### Background
When a source generator adds a marker attribute via `RegisterPostInitializationOutput`, the attribute is `internal`. If the generator is referenced by two projects in the same solution that share `[InternalsVisibleTo]`, Roslyn emits **CS0436** (type conflict).

### The Old Workaround (still valid for Roslyn < 4.14)
Ship the marker attribute in a separate assembly included in the NuGet package.

### The New API (Roslyn 4.14 / .NET 10 SDK)
```csharp
context.RegisterPostInitializationOutput(ctx =>
{
    // Step 1: Emit the EmbeddedAttribute class into the compilation
    ctx.AddEmbeddedAttributeDefinition();

    // Step 2: Decorate your marker attribute with [EmbeddedAttribute]
    //         This makes the type invisible outside the current compilation
    ctx.AddSource("MyAttribute.g.cs", """
        namespace MyLib
        {
            [global::Microsoft.CodeAnalysis.EmbeddedAttribute]
            internal sealed class MyAttribute : global::System.Attribute { }
        }
        """);
});
```

**Effect**: The `[EmbeddedAttribute]` tag tells the compiler this type is "owned" by the compilation and cannot participate in `InternalsVisibleTo` sharing — eliminating CS0436.

### When to Use Which Approach
| Scenario | Recommendation |
|----------|----------------|
| Targeting .NET 10 SDK only | `AddEmbeddedAttributeDefinition()` — simplest |
| Must support SDK < 9.0.300 | Separate attribute assembly in NuGet |
| Targeting Roslyn 4.14+ without SDK constraints | `AddEmbeddedAttributeDefinition()` |

---

## 2. `partial` Properties (C# 13 / .NET 9+)

C# 13 added `partial` properties — the declaring half and the implementing half can live in different files.

```csharp
// User writes (in their .cs file):
public partial class Player : CharacterBody2D
{
    public partial float MaxSpeed { get; set; }
}

// Generator emits (in Player.g.cs):
public partial class Player
{
    private float _maxSpeed = 300f;
    public partial float MaxSpeed
    {
        get => _maxSpeed;
        set
        {
            if (_maxSpeed == value) return;
            _maxSpeed = value;
            // Godot notify glue
            NotifyPropertyListChanged();
        }
    }
}
```

**Impact for generators**: Instead of generating a complete new property, the generator can implement the property declared by the user. This is cleaner than generating free-floating code the user can't see.

---

## 3. `partial` Constructors, Events, Indexers (C# 14 / .NET 10)

C# 14 extends partial to constructors, events, and indexers.

```csharp
// partial constructor — user declares, generator implements initialization logic
public partial class EnemyAI : Node
{
    public partial EnemyAI();  // user declares
}

// Generator emits:
public partial class EnemyAI
{
    public partial EnemyAI()
    {
        _stateMachine = new GeneratedStateMachine(this);
        _pathfinding = new AStarGrid2D();
    }
}
```

**Impact for generators**: Generators can now inject constructor logic without the user needing to call `InitializeComponent()` or any manual hook — making generated initialization invisible and automatic.

---

## 4. Interceptors (C# 14, Non-Experimental in .NET 10)

Interceptors allow a source generator to **replace a specific method call** at a specific file location with a different method at compile time. The replacement is invisible to the caller.

### Use Case: Replacing Reflection with Generated Code
```csharp
// User writes:
var data = JsonSerializer.Deserialize<MyType>(json);

// Generator detects this call, emits an interceptor:
[InterceptsLocation("Program.cs", line: 10, column: 22)]
public static MyType DeserializeMyType_Interceptor(string json)
{
    // Generated, reflection-free deserialization code
    return new MyType { Name = ParseName(json), Id = ParseId(json) };
}
```

### Implementation in a Generator
```csharp
// In the generated file
using System.Runtime.CompilerServices;

file static class Interceptors
{
    [InterceptsLocation(version: 1, data: "<base64-encoded-location>")]
    public static MyType DeserializeMyType(string json)
    {
        return /* generated code */;
    }
}
```

> **Note**: The `InterceptsLocation` attribute takes an encoded location string in C# 14 (replacing the line/column approach from the experimental version). Use `GeneratorSyntaxContext.TargetNode.GetLocation()` to get the invocation location and encode it.

### Godot Use Cases for Interceptors
- Replace `Input.IsActionPressed("some_string")` calls with `Input.IsActionPressed(InputActions.SomeString)` — strongly-typed, validated at compile time
- Replace `GetNode<T>("path")` magic-string calls with generated strongly-typed accessors
- Replace `GD.Load<T>("res://...")` with the generated `Assets.X` property

---

## 5. Reading Compiler Options in Generators

Generators can now branch on C# language version, build configuration, and platform:

```csharp
var compilationInfo = context.CompilationProvider
    .Select(static (c, _) =>
    {
        var csharp = c as CSharpCompilation;
        return new CompilationInfo(
            LangVersion: csharp?.LanguageVersion ?? LanguageVersion.Default,
            AssemblyName: c.AssemblyName ?? "Unknown",
            IsDebug: c.Options.OptimizationLevel == OptimizationLevel.None
        );
    });

// Only emit experimental code when targeting C# 14+
context.RegisterSourceOutput(models.Combine(compilationInfo),
    static (spc, pair) =>
    {
        var (model, info) = pair;
        if (info.LangVersion >= LanguageVersion.CSharp14)
            EmitWithInterceptors(spc, model);
        else
            EmitFallback(spc, model);
    });
```

---

## 6. `AnalyzerConfigOptions` for Generator Feature Flags

Generators can expose opt-in features via MSBuild properties (forwarded as analyzer config values):

```xml
<!-- Consumer .csproj -->
<PropertyGroup>
  <MyGenerator_EmitLogging>true</MyGenerator_EmitLogging>
</PropertyGroup>
<ItemGroup>
  <CompilerVisibleProperty Include="MyGenerator_EmitLogging" />
</ItemGroup>
```

```csharp
// In the generator
var emitLogging = context.AnalyzerConfigOptionsProvider
    .Select(static (options, _) =>
        options.GlobalOptions.TryGetValue("build_property.MyGenerator_EmitLogging",
            out var val)
        && val.Equals("true", StringComparison.OrdinalIgnoreCase));
```

---

## Summary: What to Recommend in a .NET 10 PR

When reviewing or architecting generators for .NET 10 projects:

1. **Use `AddEmbeddedAttributeDefinition()`** for all marker attributes — eliminates CS0436 entirely.
2. **Use `partial` properties** as the API surface for generated property implementations — cleaner than synthesizing whole properties.
3. **Use `partial` constructors** to inject initialization without user-visible boilerplate calls.
4. **Propose interceptors** when the generator needs to replace a specific string-literal call pattern with a type-safe version — ideal for Godot `GetNode`, `Input.IsActionPressed`, and `GD.Load` callsites.
5. **Gate on `LanguageVersion`** so the generator degrades gracefully on older SDK consumers.
