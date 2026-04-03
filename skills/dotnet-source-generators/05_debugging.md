# 05 — Debugging Source Generators (macOS / Rider / .NET 10)

For pipeline concepts and caching theory, see `01_concepts.md`. This file covers practical debugging workflows.

## 1. Live Debugging in Rider

Rider can attach to the compiler process and hit breakpoints inside generator code.

1. **Run/Debug Configurations** > Add **.NET Project**
2. Set **Project** to the generator project
3. Set **Target project** to the consumer project
4. Set breakpoints in `Initialize`, transform lambdas, or emission code
5. Hit **Debug**

**Caveats:**
- `Debugger.Launch()` does not work on macOS — use the Rider run configuration instead
- Incremental caching may skip breakpoints if inputs haven't changed — edit a relevant source file to force re-execution
- After changing generator code, restart the debug session (hot reload doesn't apply to generators)

---

## 2. Inspecting Generated Output

Add to the consumer `.csproj` or `Directory.Build.props`:

```xml
<PropertyGroup>
  <EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>
  <CompilerGeneratedFilesOutputPath>.generated</CompilerGeneratedFilesOutputPath>
</PropertyGroup>
```

Files appear at `.generated/<GeneratorAssembly>/<GeneratorType>/`. Also visible in Rider under **Dependencies > Analyzers**.

---

## 3. MSBuild Binary Logs

```bash
dotnet build -bl
```

View the resulting `msbuild.binlog` at [msbuildlog.com](https://msbuildlog.com) or in [MSBuild Structured Log Viewer](https://github.com/KirillOsenkov/MSBuildStructuredLog) (`brew install --cask msbuild-structured-log-viewer`).

Search for the generator assembly name to find: execution time, generated file list, load failures, and input files.

---

## 4. Diagnosing Cache Misses

When a user reports a generator re-running on every keystroke, check their data model first.

### Step tracking test pattern

```csharp
var options = new GeneratorDriverOptions(
    IncrementalGeneratorOutputKind.None,
    trackIncrementalGeneratorSteps: true);

var driver = CSharpGeneratorDriver.Create(
    new[] { generator.AsSourceGenerator() },
    driverOptions: options);

// Run 1: populate cache
driver = driver.RunGenerators(compilation);

// Run 2: unrelated edit
var comp2 = compilation.AddSyntaxTrees(
    CSharpSyntaxTree.ParseText("class Unrelated { }"));
driver = driver.RunGenerators(comp2);

// Assert stages were cached
var step = driver.GetRunResult().Results[0]
    .TrackedSteps["MyStage"].Single();
Assert.AreEqual(IncrementalStepRunReason.Cached, step.Outputs[0].Reason);
```

Requires `WithTrackingName("MyStage")` on pipeline stages in the generator.

### What the step reasons mean

| Reason | Meaning |
|--------|---------|
| `Cached` | Input unchanged, output reused |
| `Unchanged` | Step ran, produced same output |
| `Modified` | Step ran, produced different output |
| `New` | First run |
| `Removed` | Item no longer exists |

`Modified` when you expected `Cached` = broken equality on the model flowing into that stage.

---

## 5. Logging from Generators

No console access inside the compiler. Options:

- **Debug file**: `spc.AddSource("_debug.g.cs", $"// count: {models.Length}")` — check `.generated/` after build
- **Diagnostic warning**: `spc.ReportDiagnostic(...)` — shows in IDE error list. Remove before committing.
- **File I/O** (last resort): `File.WriteAllText("/tmp/gen-debug.txt", ...)` — working directory may surprise you

---

## 6. Common Failures

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Generator doesn't run | Wrong target framework (`net10.0` instead of `netstandard2.0`) | Fix `.csproj` target |
| Generator doesn't run | Missing `OutputItemType="Analyzer"` on project reference | Add to consumer `.csproj` |
| No output produced | Early return in `Initialize` (assembly name check, null type resolution) | Add debug logging to find exit point |
| Compile errors in generated code | Missing `global::` prefix, namespace mismatch, missing `partial` | See `02_pr_review.md` F5/F6 |
| IDE shows stale output | Cached generator assembly | `dotnet clean && dotnet build`, restart Rider, delete `obj/`+`bin/` |
| Breakpoints not hit | Pipeline cached the result, skipped execution | Edit a relevant source file to invalidate cache |

---

## 7. Reference Guide

Full debugging guide with extended examples: [`docs/reference/source-generator-debugging.md`](../../../docs/reference/source-generator-debugging.md)
