---
name: roslyn-analyzers
description: >
  Roslyn diagnostic analyzers, code fix providers, and refactoring providers for .NET 10.
  Load when implementing custom analyzers, code fixes, or refactoring actions, reviewing
  analyzer code, or when the user mentions "DiagnosticAnalyzer", "CodeFixProvider",
  "CodeRefactoringProvider", "analyzer testing", ".editorconfig severity", or "diagnostic descriptor".
---

# Roslyn Analyzers (.NET 10)

## When to Load

Load this skill when any of the following appear in the task:

- Files referencing `DiagnosticAnalyzer`, `CodeFixProvider`, `CodeRefactoringProvider`
- `.csproj` with `<EnforceExtendedAnalyzerRules>true</EnforceExtendedAnalyzerRules>`
- `.editorconfig` or `.globalconfig` with `dotnet_diagnostic.` severity entries
- Phrases: "roslyn analyzer", "diagnostic analyzer", "code fix", "code refactoring", "analyzer testing", "diagnostic descriptor", "analyzer NuGet", "suppress diagnostic"

## Analyzers vs. Source Generators

Both share the Roslyn compiler platform and ship as analyzer assemblies, but serve different purposes. Analyzers report diagnostics and offer fixes (`DiagnosticAnalyzer` + `CodeFixProvider`). Source generators emit new source files (`IIncrementalGenerator`). A single NuGet package can contain both. See `dotnet-source-generators` for generator patterns.

---

## Mental Model

```
  USER CODE ──(compile)──▶ ROSLYN COMPILER
                                │
                    Analyzer Driver loads assemblies
                                │
                 ┌──────────────▼──────────────┐
                 │  DiagnosticAnalyzer          │
                 │  Initialize(AnalysisContext)  │
                 │  ├─ RegisterSyntaxNodeAction  │
                 │  ├─ RegisterSymbolAction       │
                 │  ├─ RegisterOperationAction    │
                 │  └─ RegisterSemanticModelAction │
                 └──────────────┬──────────────┘
                                │ reports Diagnostic
                 ┌──────────────▼──────────────┐
                 │  CodeFixProvider              │
                 │  RegisterCodeFixesAsync()      │
                 │  └─ offers fix for diagnostic  │
                 └──────────────┬──────────────┘
                                │ applies document changes
                 ┌──────────────▼──────────────┐
                 │  Fixed source code            │
                 └─────────────────────────────┘
```

**Golden rule**: analyzers run on every keystroke in the IDE. They must be fast. Avoid allocations in hot paths, prefer syntax checks before semantic analysis, never block.

---

## Project Structure

```
MyAnalyzers/
├── MyAnalyzers/
│   ├── MyAnalyzers.csproj           # Analyzer library (netstandard2.0)
│   ├── DiagnosticIds.cs             # Centralized diagnostic IDs
│   ├── NamingAnalyzer.cs            # DiagnosticAnalyzer implementation
│   └── NamingCodeFixProvider.cs     # Paired code fix
├── MyAnalyzers.Tests/
│   ├── MyAnalyzers.Tests.csproj     # Test project (net10.0)
│   └── NamingAnalyzerTests.cs       # Verifier tests
└── MyAnalyzers.Package/
    └── MyAnalyzers.Package.csproj   # NuGet packaging project
```

### Analyzer .csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <EnforceExtendedAnalyzerRules>true</EnforceExtendedAnalyzerRules>
    <IsRoslynComponent>true</IsRoslynComponent>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.Analyzers" Version="3.11.0">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.14.0" />
  </ItemGroup>
</Project>
```

**Key constraints**: target `netstandard2.0` (analyzers load into .NET Framework in VS). `EnforceExtendedAnalyzerRules` catches authoring mistakes at compile time. `IsRoslynComponent` enables the Roslyn build pipeline.

---

## Diagnostic Analyzer Implementation

### Diagnostic Descriptor

Centralize IDs to avoid collisions. Every diagnostic needs a descriptor:

```csharp
public static class DiagnosticIds
{
    public const string FieldNaming = "MY001";
    public const string AsyncSuffix = "MY002";
}

private static readonly DiagnosticDescriptor Rule = new(
    id: DiagnosticIds.FieldNaming,
    title: "Private field should use underscore prefix",
    messageFormat: "Field '{0}' should start with '_'",
    category: "Naming",
    defaultSeverity: DiagnosticSeverity.Warning,
    isEnabledByDefault: true,
    helpLinkUri: "https://docs.myorg.com/analyzers/MY001");
```

Use standard categories: `Naming`, `Design`, `Usage`, `Performance`, `Reliability`, `Security`, `Maintainability`.

### Complete Analyzer Example

```csharp
[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class FieldNamingAnalyzer : DiagnosticAnalyzer
{
    private static readonly DiagnosticDescriptor Rule = new(
        id: "MY001",
        title: "Private field naming",
        messageFormat: "Private field '{0}' should start with '_'",
        category: "Naming",
        defaultSeverity: DiagnosticSeverity.Warning,
        isEnabledByDefault: true);

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics => [Rule];

    public override void Initialize(AnalysisContext context)
    {
        // Required: always call both of these
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();

        context.RegisterSymbolAction(AnalyzeField, SymbolKind.Field);
    }

    private static void AnalyzeField(SymbolAnalysisContext context)
    {
        var field = (IFieldSymbol)context.Symbol;
        if (field.DeclaredAccessibility != Accessibility.Private) return;
        if (field.IsConst || field.IsStatic) return;
        if (field.Name.StartsWith("_")) return;

        context.ReportDiagnostic(Diagnostic.Create(Rule, field.Locations[0], field.Name));
    }
}
```

### Registration Actions — Choose the Right One

| Action | When to use | Cost |
|--------|-------------|------|
| `RegisterSyntaxNodeAction` | Syntax-only checks (naming, structure) | Cheapest |
| `RegisterSymbolAction` | Symbol checks (accessibility, type hierarchy) | Low |
| `RegisterOperationAction` | Control/data flow, expression semantics | Medium |
| `RegisterSemanticModelAction` | Whole-file semantic analysis | High |
| `RegisterCompilationStartAction` | Cross-file analysis, per-compilation state | Varies |

Prefer syntax analysis when possible — it avoids loading the semantic model:

```csharp
// GOOD: Syntax-only — fast
context.RegisterSyntaxNodeAction(ctx =>
{
    var invocation = (InvocationExpressionSyntax)ctx.Node;
    if (invocation.Expression is IdentifierNameSyntax { Identifier.Text: "Dispose" })
    { /* report */ }
}, SyntaxKind.InvocationExpression);

// OK: Semantic — needed when syntax is ambiguous
context.RegisterSymbolAction(ctx =>
{
    var method = (IMethodSymbol)ctx.Symbol;
    if (method.ReturnType.AllInterfaces.Any(i =>
        i.ToDisplayString() == "System.IDisposable"))
    { /* report */ }
}, SymbolKind.Method);
```

---

## Code Fix Provider

```csharp
[ExportCodeFixProvider(LanguageNames.CSharp, Name = nameof(FieldNamingCodeFixProvider))]
[Shared]
public sealed class FieldNamingCodeFixProvider : CodeFixProvider
{
    public override ImmutableArray<string> FixableDiagnosticIds =>
        [DiagnosticIds.FieldNaming];

    // Always implement — users expect batch-fix across a solution
    public override FixAllProvider? GetFixAllProvider() =>
        WellKnownFixAllProviders.BatchFixer;

    public override async Task RegisterCodeFixesAsync(CodeFixContext context)
    {
        var root = await context.Document.GetSyntaxRootAsync(context.CancellationToken);
        if (root is null) return;

        var diagnostic = context.Diagnostics[0];
        var token = root.FindToken(diagnostic.Location.SourceSpan.Start);
        if (token.Parent is not VariableDeclaratorSyntax declarator) return;

        var newName = "_" + char.ToLowerInvariant(declarator.Identifier.Text[0])
                          + declarator.Identifier.Text[1..];

        context.RegisterCodeFix(
            CodeAction.Create(
                title: $"Rename to '{newName}'",
                createChangedSolution: ct => RenameFieldAsync(
                    context.Document, declarator, newName, ct),
                equivalenceKey: DiagnosticIds.FieldNaming),
            diagnostic);
    }

    private static async Task<Solution> RenameFieldAsync(
        Document document, VariableDeclaratorSyntax declarator,
        string newName, CancellationToken ct)
    {
        var semanticModel = await document.GetSemanticModelAsync(ct);
        var symbol = semanticModel!.GetDeclaredSymbol(declarator, ct);
        if (symbol is null) return document.Project.Solution;

        return await Renamer.RenameSymbolAsync(
            document.Project.Solution, symbol, new SymbolRenameOptions(), newName, ct);
    }
}
```

**Code fix patterns**: `Renamer.RenameSymbolAsync` for renames (handles all references), `SyntaxEditor` for multi-change edits, `root.ReplaceNode()` for simple single-node replacement.

---

## Code Refactoring Provider

Refactorings appear in the lightbulb menu without requiring a diagnostic:

```csharp
[ExportCodeRefactoringProvider(LanguageNames.CSharp,
    Name = nameof(ExtractInterfaceRefactoring))]
[Shared]
public sealed class ExtractInterfaceRefactoring : CodeRefactoringProvider
{
    public override async Task ComputeRefactoringsAsync(CodeRefactoringContext context)
    {
        var root = await context.Document.GetSyntaxRootAsync(context.CancellationToken);
        if (root?.FindNode(context.Span) is not ClassDeclarationSyntax classDecl) return;

        var publicMethods = classDecl.Members
            .OfType<MethodDeclarationSyntax>()
            .Where(m => m.Modifiers.Any(SyntaxKind.PublicKeyword))
            .ToList();
        if (publicMethods.Count == 0) return;

        context.RegisterRefactoring(
            CodeAction.Create(
                title: $"Extract interface from '{classDecl.Identifier.Text}'",
                createChangedSolution: ct =>
                    ExtractInterfaceAsync(context.Document, classDecl, publicMethods, ct),
                equivalenceKey: "ExtractInterface"));
    }
}
```

---

## Configuration

### .editorconfig Severity Overrides

```ini
[*.cs]
dotnet_diagnostic.MY001.severity = error
dotnet_diagnostic.MY002.severity = none         # disable rule
dotnet_diagnostic.CA1822.severity = suggestion   # built-in analyzer
```

### .globalconfig (Repository-Wide)

```ini
is_global = true
dotnet_analyzer_diagnostic.category-Naming.severity = warning
dotnet_analyzer_diagnostic.category-Performance.severity = error
dotnet_diagnostic.MY001.severity = error
```

### Suppression

```csharp
// Attribute suppression
[SuppressMessage("Naming", "MY001", Justification = "Matches serialization contract")]
private string Name;

// Pragma suppression
#pragma warning disable MY001
private string Name;
#pragma warning restore MY001
```

---

## Testing Analyzers

### Test Project Setup

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp.Analyzer.Testing" Version="1.1.2" />
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp.CodeFix.Testing" Version="1.1.2" />
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp.CodeRefactoring.Testing" Version="1.1.2" />
    <PackageReference Include="xunit" Version="2.9.3" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\MyAnalyzers\MyAnalyzers.csproj" />
  </ItemGroup>
</Project>
```

### Analyzer Verifier Tests

Use `{|DiagnosticId:text|}` markup to mark expected diagnostic locations:

```csharp
using Verify = Microsoft.CodeAnalysis.CSharp.Testing.CSharpAnalyzerVerifier<
    MyAnalyzers.FieldNamingAnalyzer,
    Microsoft.CodeAnalysis.Testing.DefaultVerifier>;

public class FieldNamingAnalyzerTests
{
    [Fact]
    public async Task PrivateField_WithoutUnderscore_ReportsDiagnostic()
    {
        var source = """
            public class MyClass
            {
                private int {|MY001:count|};
            }
            """;
        await Verify.VerifyAnalyzerAsync(source);
    }

    [Fact]
    public async Task PrivateField_WithUnderscore_NoDiagnostic()
    {
        var source = """
            public class MyClass
            {
                private int _count;
            }
            """;
        await Verify.VerifyAnalyzerAsync(source);
    }
}
```

### Code Fix Verifier Tests

```csharp
using Verify = Microsoft.CodeAnalysis.CSharp.Testing.CSharpCodeFixVerifier<
    MyAnalyzers.FieldNamingAnalyzer,
    MyAnalyzers.FieldNamingCodeFixProvider,
    Microsoft.CodeAnalysis.Testing.DefaultVerifier>;

[Fact]
public async Task CodeFix_RenamesField()
{
    var source = """
        public class MyClass { private int {|MY001:count|}; }
        """;
    var fixedSource = """
        public class MyClass { private int _count; }
        """;
    await Verify.VerifyCodeFixAsync(source, fixedSource);
}
```

When analyzers check external types, add reference assemblies:

```csharp
var test = new Verify.Test
{
    TestCode = source,
    ReferenceAssemblies = ReferenceAssemblies.Net.Net90
        .AddPackages([new PackageIdentity("Newtonsoft.Json", "13.0.3")]),
};
await test.RunAsync();
```

---

## NuGet Analyzer Packaging

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <SuppressDependenciesWhenPacking>true</SuppressDependenciesWhenPacking>
    <GeneratePackageOnBuild>true</GeneratePackageOnBuild>
    <PackageId>MyOrg.Analyzers</PackageId>
    <DevelopmentDependency>true</DevelopmentDependency>
  </PropertyGroup>
  <ItemGroup>
    <None Include="$(OutputPath)\$(AssemblyName).dll"
          Pack="true" PackagePath="analyzers/dotnet/cs" Visible="false" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\MyAnalyzers\MyAnalyzers.csproj" />
  </ItemGroup>
</Project>
```

Consumers reference as a development dependency with `<PrivateAssets>all</PrivateAssets>`. Apply org-wide via `Directory.Build.props`.

---

## CI Integration

```yaml
# Treat analyzer warnings as errors in CI
- run: dotnet build --no-restore /p:TreatWarningsAsErrors=true
- run: dotnet test MyAnalyzers.Tests/ --no-build --verbosity normal
```

Or in `Directory.Build.props`:

```xml
<PropertyGroup Condition="'$(CI)' == 'true'">
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

---

## Anti-Patterns

| Anti-pattern | Problem | Fix |
|-------------|---------|-----|
| Missing `EnableConcurrentExecution()` | Single-threaded, blocks IDE | Always enable in `Initialize()` |
| Not calling `ConfigureGeneratedCodeAnalysis` | Wastes time on generated code | Always configure — usually `None` |
| Mutable state on analyzer class | Race conditions under concurrent execution | Use `CompilationStartAction` for per-compilation state |
| Throwing exceptions in callbacks | Crashes analyzer driver, disables all analyzers | Let the driver's fault tolerance handle it |
| `string` comparison for type names | Breaks with aliases, nested types | Use `SymbolEqualityComparer` |
| Missing `GetFixAllProvider()` | Users can't batch-fix | Return `BatchFixer` for independent fixes |
| Targeting `net8.0` instead of `netstandard2.0` | Won't load in Visual Studio | Always target `netstandard2.0` |
| Heavy work in `Initialize()` | Blocks IDE startup | Keep lightweight; defer to action callbacks |

## Performance Checklist

- Call `EnableConcurrentExecution()` and `ConfigureGeneratedCodeAnalysis(None)` in every analyzer
- Use `RegisterSyntaxNodeAction` before `RegisterSymbolAction` — syntax is cheaper
- Filter with `SyntaxKind` parameters — the engine pre-filters, reducing callbacks
- Avoid LINQ in hot analyzer paths — allocates enumerator objects per call
- Use `SymbolEqualityComparer.Default` for symbol comparisons
- Cache `SemanticModel` lookups — avoid `GetSymbolInfo()` in loops
- Use `ImmutableArray.Create()` not `new[] { }.ToImmutableArray()`

## Cross-References

- **dotnet-source-generators** — complementary skill for Roslyn source generators; shared project structure and packaging
- **dotnet-testing** — general .NET testing patterns; analyzer tests use the same xUnit infrastructure
- **dotnet-architecture** — design patterns that analyzers can enforce
