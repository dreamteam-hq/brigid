# 01 — Core Concepts: C# Incremental Source Generators

## 1. Project Setup

### `.csproj` Template (Generator Project)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <!-- MUST be netstandard2.0 — the compiler host (VS, Rider) runs on .NET Framework 4.7.2 -->
    <TargetFramework>netstandard2.0</TargetFramework>

    <!-- Use latest C# language features in the generator code itself -->
    <LangVersion>latest</LangVersion>

    <!-- Mark this as a Roslyn component, not a regular library -->
    <IsRoslynComponent>true</IsRoslynComponent>
    <!-- Equivalent to the pair: OutputItemType=Analyzer + IncludeBuildOutput=false -->

    <!-- Emit generated files to disk for inspection during development -->
    <EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>
    <CompilerGeneratedFilesOutputPath>.generated</CompilerGeneratedFilesOutputPath>
  </PropertyGroup>

  <ItemGroup>
    <!-- Roslyn 4.14 = .NET 10 SDK. Use 4.4+ minimum for ForAttributeWithMetadataName -->
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.14.0"
                      PrivateAssets="all" />
    <PackageReference Include="Microsoft.CodeAnalysis.Analyzers" Version="3.11.0"
                      PrivateAssets="all" />
  </ItemGroup>
</Project>
```

### Consumer `.csproj` (the project that uses the generator)

```xml
<ItemGroup>
  <ProjectReference Include="../MyGenerator/MyGenerator.csproj"
                    OutputItemType="Analyzers"
                    ReferenceOutputAssembly="false" />
</ItemGroup>
```

---

## 2. The IncrementalGeneratorInitializationContext Providers

| Provider | Type | Use |
|----------|------|-----|
| `context.SyntaxProvider` | `SyntaxValueProvider` | Access syntax tree nodes |
| `context.CompilationProvider` | `IncrementalValueProvider<Compilation>` | Access the full compilation (rarely; causes broad invalidation) |
| `context.AdditionalTextsProvider` | `IncrementalValuesProvider<AdditionalText>` | Read non-C# files (`.tscn`, `.json`, `project.godot`) |
| `context.AnalyzerConfigOptionsProvider` | `IncrementalValueProvider<AnalyzerConfigOptionsProvider>` | Read `.editorconfig` / `globalconfig` options |
| `context.MetadataReferencesProvider` | `IncrementalValuesProvider<MetadataReference>` | Inspect referenced assemblies |
| `context.ParseOptionsProvider` | `IncrementalValueProvider<ParseOptions>` | Read parse options / language version |

---

## 3. Pipeline Operators

```
IncrementalValuesProvider<T>  (multi-value)
IncrementalValueProvider<T>   (single-value)
```

| Operator | Signature | Notes |
|----------|-----------|-------|
| `Select` | `(T, CancellationToken) → R` | Map one value to another |
| `SelectMany` | `(T, CancellationToken) → IEnumerable<R>` | Flatten |
| `Where` | `(T) → bool` | Filter (must be pure) |
| `Collect` | — | Aggregates all values into `ImmutableArray<T>` |
| `Combine` | `provider.Combine(other)` | Zips two providers: `(T, U)` |
| `WithTrackingName` | `(string)` | Labels a stage — required for cacheability unit tests |
| `WithComparer` | `IEqualityComparer<T>` | Override equality for custom types |

---

## 4. The Two SyntaxProvider Methods

### `CreateSyntaxProvider` (avoid unless necessary)
```csharp
context.SyntaxProvider.CreateSyntaxProvider(
    predicate: static (node, _) => node is ClassDeclarationSyntax cds
                                   && cds.AttributeLists.Count > 0,
    transform: static (ctx, _) => ExtractModel(ctx));
```
- Predicate runs on **every syntax node** in the compilation on every change.
- Use only when there is no marker attribute to target.

### `ForAttributeWithMetadataName` (strongly preferred)
```csharp
context.SyntaxProvider.ForAttributeWithMetadataName(
    "MyLib.MyAttribute",          // fully-qualified metadata name
    predicate: static (node, _) => node is ClassDeclarationSyntax,
    transform: static (ctx, _) => ExtractModel(ctx));
```
- **At least 99x more efficient** than `CreateSyntaxProvider` for attribute-driven generators.
- Available in `Microsoft.CodeAnalysis.CSharp` >= 4.4.0 (requires .NET 7+ SDK).
- The Roslyn engine pre-indexes attribute usages; only files containing the attribute are ever visited.

### When `CreateSyntaxProvider` Is the Right Choice

Not all generators are attribute-driven. Some discover targets by **base interface inheritance**, **namespace conventions**, or **structural patterns**. In these cases, `ForAttributeWithMetadataName` can't be used. Best practices for `CreateSyntaxProvider`:

1. **Make the predicate as tight as possible** — filter on structural markers before the semantic model is consulted:
   ```csharp
   // Too broad — runs semantic model on every interface in the compilation
   predicate: static (node, _) => node is InterfaceDeclarationSyntax

   // Tighter — only interfaces with base lists (reduces candidates significantly)
   predicate: static (node, _) =>
       node is InterfaceDeclarationSyntax ids
       && ids.BaseList is not null
       && ids.BaseList.Types.Count > 0
   ```

2. **Extract into equatable models immediately** in the transform lambda — never let `ISymbol` flow downstream.

3. **Consider introducing a marker attribute** — emitting `[MyMarker]` via `RegisterPostInitializationOutput` and having users apply it converts a `CreateSyntaxProvider` generator into a FAWMN generator, with ~99x better performance.

### Cross-Assembly Type Discovery

Some generators need to discover types defined in **referenced assemblies**, not just the current compilation's source. This requires walking `compilation.SourceModule.ReferencedAssemblySymbols`.

```csharp
// Walk referenced assemblies to find types in a specific namespace
private static IEnumerable<INamedTypeSymbol> FindTypesInNamespace(
    Compilation compilation, string targetNamespace)
{
    foreach (var asm in compilation.SourceModule.ReferencedAssemblySymbols)
    {
        var ns = FindNamespace(asm.GlobalNamespace, targetNamespace.Split('.'));
        if (ns is not null)
        {
            foreach (var type in ns.GetTypeMembers())
                yield return type;
        }
    }
}
```

**Critical**: This pattern requires `CompilationProvider`, which invalidates on every change. Always extract the discovered types into equatable models via `.Select()` so the output stage can cache properly. Never pass `CompilationProvider` or its contents directly to `RegisterSourceOutput`.

---

## 5. The Immutable Model Contract

The pipeline caches based on **value equality**. You must ensure every object passed between pipeline stages satisfies this:

```csharp
// CORRECT — record provides structural equality automatically
internal record ClassModel(
    string Namespace,
    string ClassName,
    EquatableArray<PropertyModel> Properties  // custom wrapper for ImmutableArray
);

internal record PropertyModel(string Name, string TypeFqn, bool IsNullable);

// WRONG — INamedTypeSymbol uses reference equality; breaks caching
internal record BadModel(string Name, INamedTypeSymbol Symbol); // never do this
```

### Equatable collection wrapper pattern
```csharp
internal readonly struct EquatableArray<T>(ImmutableArray<T> arr) : IEquatable<EquatableArray<T>>
    where T : IEquatable<T>
{
    public ImmutableArray<T> AsImmutableArray() => arr;
    public bool Equals(EquatableArray<T> other) => arr.SequenceEqual(other.arr);
    public override bool Equals(object? obj) => obj is EquatableArray<T> o && Equals(o);
    public override int GetHashCode() => arr.Aggregate(0, HashCode.Combine);
}
```

**Objects to NEVER store in the pipeline**:
- `SyntaxNode` / any `*Syntax` type
- `ISymbol` / `ITypeSymbol` / `INamedTypeSymbol` / `IMethodSymbol` / etc.
- `SemanticModel`
- `Compilation`
- `Location` (also reference-equality; extract filepath + line span as strings instead)

---

## 6. Registration Methods

| Method | Called | Use |
|--------|--------|-----|
| `RegisterPostInitializationOutput` | Once, immediately | Inject constant source (e.g., marker attributes) |
| `RegisterSourceOutput` | Each time provider changes | Main code emission |
| `RegisterImplementationSourceOutput` | Like RegisterSourceOutput but skipped during IDE analysis runs | Heavy work not needed for diagnostics |

---

## 7. Diagnostics

**Important**: The Roslyn cookbook recommends **not reporting diagnostics from generators**. Diagnostics from generators complicate the caching model. Instead, write a companion `DiagnosticAnalyzer` for validation rules.

```csharp
// AVOID — reporting diagnostics inside a generator's RegisterSourceOutput
context.RegisterSourceOutput(models, (spc, model) =>
{
    spc.ReportDiagnostic(Diagnostic.Create(...)); // complicates caching
});

// PREFERRED — write a separate analyzer
[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class MissingPartialAnalyzer : DiagnosticAnalyzer
{
    // ... RegisterSymbolAction to check and report
}
```

If you must define diagnostic descriptors (for the rare case of fatal generator errors):

```csharp
// Define once as a static field
private static readonly DiagnosticDescriptor MissingPartialModifier = new(
    id: "MYGEN001",
    title: "Class must be partial",
    messageFormat: "Class '{0}' decorated with [MyAttr] must be declared partial",
    category: "MyGenerator",
    defaultSeverity: DiagnosticSeverity.Error,
    isEnabledByDefault: true);

// Only as a last resort inside RegisterSourceOutput
spc.ReportDiagnostic(Diagnostic.Create(
    MissingPartialModifier,
    location,
    classSymbolName));
```

---

## 8. Code Generation Hygiene

Always emit code with:
- `// <auto-generated />` header comment
- `#nullable enable` at the top
- `global::` prefix for all external type references to avoid namespace conflicts

```csharp
private static string Render(ClassModel model)
{
    return $$"""
        // <auto-generated />
        #nullable enable
        namespace {{model.Namespace}};

        partial class {{model.ClassName}}
        {
            private global::System.Collections.Generic.List<string> _items = new();
        }
        """;
}
```

---

## 9. Testing

### Snapshot Testing (recommended)
```csharp
// Using Verify + Verify.SourceGenerators
[Fact]
public Task GeneratesCorrectOutput()
{
    const string source = """
        [MyAttr]
        public partial class Foo { }
        """;

    var driver = RunGenerator(source);
    return Verify(driver);  // compares against .verified.cs snapshots
}
```

### Cacheability Testing
Use `WithTrackingName()` on each pipeline stage, then verify with a second run after a no-op edit that all stages report `Cached`:

```csharp
var result1 = driver.RunGenerators(compilation).GetRunResult();
// make a trivial edit (e.g., add a comment)
var result2 = driver.RunGenerators(newCompilation).GetRunResult();

// All tracked stages should be Cached, not Rebuilt
Assert.All(result2.Results[0].TrackedSteps["InitialExtraction"],
    step => Assert.Equal(IncrementalStepRunReason.Cached, step.Outputs[0].Reason));
```

---

## 10. Packaging as NuGet

```xml
<!-- In the generator .csproj -->
<PropertyGroup>
  <IsRoslynComponent>true</IsRoslynComponent>
  <GeneratePackageOnBuild>true</GeneratePackageOnBuild>
</PropertyGroup>
```

The Roslyn component build targets automatically place the DLL at:
`analyzers/dotnet/cs/MyGenerator.dll`

For third-party dependencies bundled with the generator, use `ReferenceOutputAssembly="false"` and include them explicitly in the `analyzers/dotnet/cs/` folder via custom MSBuild targets.
