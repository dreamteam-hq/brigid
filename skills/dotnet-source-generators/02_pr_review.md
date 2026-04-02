# 02 — PR Review Checklist: C# Source Generators

When reviewing any PR that introduces or modifies source generator code, apply every check below. **Fail the PR** (request changes) on any RED item. Warn / suggest on YELLOW items.

---

## HARD FAILURES — Request Changes

### F1 — Wrong Target Framework
**Check**: Does the generator `.csproj` target `netstandard2.0`?
```xml
<!-- Required -->
<TargetFramework>netstandard2.0</TargetFramework>

<!-- Will fail to load in Visual Studio / older SDK hosts -->
<TargetFramework>net10.0</TargetFramework>
```
**Why**: The Roslyn compiler host inside Visual Studio is .NET Framework 4.7.2. A `net10.0` DLL will be silently ignored or cause a load failure.

---

### F2 — Roslyn Objects Leaked into Pipeline Stages
**Check**: Inspect the model types produced by `CreateSyntaxProvider` / `ForAttributeWithMetadataName` transform lambdas. Do they capture any of:
- `SyntaxNode` or any `*Syntax` subtype
- `ISymbol`, `ITypeSymbol`, `INamedTypeSymbol`, `IMethodSymbol`, etc.
- `SemanticModel`
- `Compilation`
- `Location`

```csharp
// FAIL — symbol has reference equality, breaks all caching
transform: (ctx, _) => ctx.SemanticModel.GetDeclaredSymbol(ctx.TargetNode)

// PASS — extract strings/primitives into a value-equatable record
transform: static (ctx, _) =>
{
    var symbol = (INamedTypeSymbol)ctx.TargetSymbol;
    return new ClassModel(
        Namespace: symbol.ContainingNamespace.ToDisplayString(),
        ClassName: symbol.Name,
        IsPartial: ctx.TargetNode is ClassDeclarationSyntax c
                   && c.Modifiers.Any(SyntaxKind.PartialKeyword));
}
```
**Why**: The incremental engine compares pipeline outputs between runs using `Equals()`. `ITypeSymbol` always returns false for cross-compilation equality, causing every pipeline stage to re-execute on every keystroke → severe IDE lag.

---

### F3 — Using `ISourceGenerator` Instead of `IIncrementalGenerator`
**Check**: Any class implementing `ISourceGenerator` should be rejected outright in new code.
```csharp
// Deprecated — blocked by Roslyn 4.10+ / .NET 9+ SDK
public class OldGenerator : ISourceGenerator { ... }

// Required
public class NewGenerator : IIncrementalGenerator { ... }
```
**Why**: `ISourceGenerator` was formally deprecated with Roslyn 4.10 (.NET 9 SDK). It runs on every compilation without any caching.

---

### F4 — `CreateSyntaxProvider` When a Marker Attribute Exists
**Check**: If the generator reacts to a custom attribute (which is overwhelmingly common), look at how it finds candidate nodes:
```csharp
// FAIL — scans every node in the compilation
context.SyntaxProvider.CreateSyntaxProvider(
    predicate: (node, _) => node is ClassDeclarationSyntax c
                             && c.AttributeLists.Any(al => al.Attributes.Any(a =>
                                  a.Name.ToString() == "MyAttr")),
    ...);

// PASS — pre-indexed, 99x faster
context.SyntaxProvider.ForAttributeWithMetadataName(
    "MyNamespace.MyAttribute",
    predicate: static (node, _) => node is ClassDeclarationSyntax,
    ...);
```
**Why**: The `ForAttributeWithMetadataName` path uses a Roslyn pre-index; it never touches files that don't reference the attribute at all.

---

### F5 — Generated Code Lacks `global::` Qualification
**Check**: Does generated C# code reference external types without `global::` prefix?
```csharp
// FAIL — ambiguous if consumer has a conflicting `System.Collections` namespace
$"private List<string> _items = new();"

// PASS — unambiguous regardless of consumer's usings
$"private global::System.Collections.Generic.List<string> _items = new();"
```

---

### F6 — Missing `partial` Enforcement Check
**Check**: If the generator emits code into an existing user class, does it validate that the class is declared `partial`? If not, does it report a diagnostic?
```csharp
// In the transform stage
if (!classDecl.Modifiers.Any(SyntaxKind.PartialKeyword))
{
    spc.ReportDiagnostic(Diagnostic.Create(MissingPartialDiagnostic,
        classDecl.GetLocation(), classDecl.Identifier.Text));
    return;
}
```
**Why**: Without `partial`, the emitted partial class will cause a compile error in the consumer with a cryptic message. A diagnostic is far better.

---

### F7 — Third-Party Runtime Assemblies Referenced Without Bundling
**Check**: Does the generator `.csproj` contain `<PackageReference>` entries for runtime libraries (e.g., `Newtonsoft.Json`, `System.Text.Json`, custom utilities)?
```xml
<!-- FAIL — Newtonsoft.Json won't be found by the compiler host -->
<PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
```
**Fix**: Either inline the dependency as source, use `PrivateAssets="all"` + a custom MSBuild target to pack it at `analyzers/dotnet/cs/`, or refactor to avoid the dependency.

---

### F8 — Diagnostics Reported from Generators Instead of Analyzers
**Check**: Does the generator's `RegisterSourceOutput` callback call `spc.ReportDiagnostic()`?
```csharp
// FAIL — complicates caching; diagnostic output coupled to code generation
context.RegisterSourceOutput(models, (spc, model) =>
{
    if (!model.IsPartial)
        spc.ReportDiagnostic(Diagnostic.Create(MustBePartial, ...));  // wrong place
    EmitSource(spc, model);
});

// PASS — separate DiagnosticAnalyzer handles validation
[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class MustBePartialAnalyzer : DiagnosticAnalyzer { ... }
```
**Why**: The [Roslyn cookbook](https://github.com/dotnet/roslyn/blob/main/docs/features/incremental-generators.cookbook.md) explicitly states: "Don't report diagnostics from generators." Diagnostics from generators complicate the caching model and create ordering dependencies. Write a companion analyzer instead.

**Exception**: Reporting a diagnostic for a truly fatal internal error (e.g., a required type is missing from the compilation) is acceptable as a last resort, but should be rare.

---

### F9 — `CompilationProvider` Passed Raw to `RegisterSourceOutput`
**Check**: Does the generator register output directly on `context.CompilationProvider` without any filtering pipeline?
```csharp
// FAIL — re-runs on every single source change in the project
context.RegisterSourceOutput(context.CompilationProvider, (spc, compilation) =>
{
    // walk entire compilation looking for types...
});

// PASS — extract only needed data via .Select() first
var assemblyInfo = context.CompilationProvider
    .Select(static (c, _) => new AssemblyModel(c.AssemblyName, FindRelevantTypes(c)));
context.RegisterSourceOutput(assemblyInfo, (spc, model) => { ... });
```
**Why**: `CompilationProvider` changes on every edit to every file. Without extracting into an equatable model via `.Select()`, the output stage re-runs every time, defeating incremental generation entirely.

---

## WARNINGS — Suggest Improvements

### W1 — No `WithTrackingName()` on Pipeline Stages
Pipeline stages without tracking names cannot be unit-tested for cacheability.
```csharp
// Suggest adding
var models = context.SyntaxProvider
    .ForAttributeWithMetadataName(...)
    .WithTrackingName("InitialExtraction");   // add this
```

### W2 — Using `CompilationProvider` Broadly
`CompilationProvider` invalidates on every compilation change. If the generator only needs it to resolve a type name, extract only that:
```csharp
// Broad invalidation — invalidates on every file change
var combined = models.Combine(context.CompilationProvider);

// Narrow — only changes when the assembly name changes
var assemblyName = context.CompilationProvider
    .Select(static (c, _) => c.AssemblyName);
var combined = models.Combine(assemblyName);
```

### W3 — `ImmutableArray<T>` in Model Without Equality Wrapper
`ImmutableArray<T>` uses reference equality by default.
```csharp
// Will break caching when array contents haven't actually changed
record Model(ImmutableArray<string> Names);

// Use a wrapper or SequenceEqual comparer
record Model(EquatableArray<string> Names);
```

### W4 — Generated Files Not Marked `<auto-generated />`
All generated `.cs` files should start with:
```csharp
// <auto-generated />
#nullable enable
```
This suppresses analyzer warnings on generated code and signals to tooling it is machine-generated.

### W5 — No Unit Tests for the Generator
Source generators should have tests. Minimum recommended coverage:
- At least one snapshot/golden-file test verifying the generated output.
- At least one test with an invalid input that verifies the correct diagnostic is emitted.
- Optionally: a cacheability test using `WithTrackingName` + `IncrementalStepRunReason`.

### W6 — `RegisterImplementationSourceOutput` Not Used for Heavy Work
If some output is only needed for the final binary (not IDE analysis), use:
```csharp
// Skipped during IDE analysis passes — faster IDE
context.RegisterImplementationSourceOutput(heavyModels,
    static (spc, model) => EmitHeavyCode(spc, model));
```

### W7 — Hardcoded Assembly Name Guards
Generators that check `compilation.AssemblyName` to decide whether to run are fragile:
```csharp
// Fragile — renaming the assembly silently breaks the generator
if (compilation.AssemblyName != "MyProject.Server") return;

// Better — check for a marker type or marker attribute presence
var markerType = compilation.GetTypeByMetadataName("MyProject.IMyMarker");
if (markerType is null) return;
```
If assembly name checks are unavoidable, extract via `.Select()` so the check is cached:
```csharp
var assemblyName = context.CompilationProvider.Select(static (c, _) => c.AssemblyName);
```

### W8 — Duplicate Helper Methods Across Generators
When multiple generators in the same project share identical private helper methods (type dispatch tables, naming utilities, namespace collectors), extract them into a shared `internal static` utility class. Duplicated type-dispatch tables are especially dangerous — adding support for a new type requires updating every copy.

### W9 — Interface-Driven Generator Without Marker Attribute
When a generator discovers target types by **base interface inheritance** rather than a marker attribute, `ForAttributeWithMetadataName` can't be used. The generator must use `CreateSyntaxProvider`, which is slower. Review guidance:

1. **Can a marker attribute be introduced?** Emitting `[MyHub]` via `RegisterPostInitializationOutput` and requiring users to apply it gives FAWMN compatibility at minimal ergonomic cost.
2. **If not**, ensure the `CreateSyntaxProvider` predicate is as tight as possible:
   ```csharp
   // Scans every interface in the compilation
   predicate: static (node, _) => node is InterfaceDeclarationSyntax

   // Tighter — only interfaces with a base list
   predicate: static (node, _) =>
       node is InterfaceDeclarationSyntax ids
       && ids.BaseList is not null
       && ids.BaseList.Types.Count > 0
   ```
3. **Extract equatable models immediately** in the transform — never pass `ISymbol` downstream.

### W10 — Cross-Assembly Type Discovery Without Caching
Generators that discover types from **referenced assemblies** (not the current compilation's source) need extra care:
```csharp
// Walks entire namespace tree of all referenced assemblies on every change
foreach (var asm in compilation.SourceModule.ReferencedAssemblySymbols)
    WalkNamespace(asm.GlobalNamespace);

// Extract into equatable model — cached when referenced types don't change
var crossAssemblyTypes = context.CompilationProvider
    .Select(static (c, _) => ExtractModelsFromReferences(c))
    .WithComparer(MyModelComparer.Instance);
```

### W11 — Marker Attribute Not Using `.NET 10 EmbeddedAttribute`
If this generator may be referenced by multiple projects in the same solution, the marker attribute must carry `[EmbeddedAttribute]` to avoid CS0436 type-collision errors:
```csharp
// .NET 10 / Roslyn 4.14+ API
context.RegisterPostInitializationOutput(ctx =>
{
    ctx.AddEmbeddedAttributeDefinition();  // emits Microsoft.CodeAnalysis.EmbeddedAttribute
    ctx.AddSource("MyAttr.g.cs", """
        namespace MyLib
        {
            [global::Microsoft.CodeAnalysis.EmbeddedAttribute]
            internal sealed class MyAttribute : global::System.Attribute { }
        }
        """);
});
```
See `04_dotnet10_features.md` for full context.

---

## Reviewer Summary Checklist

```
[ ] F1  TargetFramework = netstandard2.0
[ ] F2  No Roslyn objects (SyntaxNode/ISymbol/SemanticModel) in pipeline models
[ ] F3  No ISourceGenerator implementations
[ ] F4  ForAttributeWithMetadataName used for attribute-driven generators
[ ] F5  global:: prefix on all generated type references
[ ] F6  Diagnostic emitted when consumer class is missing `partial`
[ ] F7  No unpacked third-party runtime assemblies
[ ] F8  Diagnostics reported from analyzers, not generators
[ ] F9  CompilationProvider not passed raw to RegisterSourceOutput

[ ] W1   WithTrackingName on pipeline stages
[ ] W2   CompilationProvider narrowed where possible
[ ] W3   ImmutableArray wrapped for equality
[ ] W4   <auto-generated /> and #nullable enable in output
[ ] W5   Unit tests for output and diagnostics
[ ] W6   RegisterImplementationSourceOutput for heavy-only code
[ ] W7   Hardcoded assembly name guards flagged
[ ] W8   No duplicated helpers across generators
[ ] W9   Interface-driven generators have tight predicates + equatable models
[ ] W10  Cross-assembly discovery extracted into cached models
[ ] W11  EmbeddedAttribute for marker attrs in multi-project solutions
```
