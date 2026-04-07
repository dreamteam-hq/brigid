---
name: dotnet-editorconfig
description: >
  Ship the canonical dt-dotnet .editorconfig template and document naming conventions,
  diagnostic severities, and framework-specific suppressions. Load when setting up C# code style,
  adding .editorconfig, reviewing diagnostic errors, or when the user mentions "editorconfig",
  "C# linting", "code style", "naming conventions", "dotnet diagnostics", "CA rules", "IDE rules".

metadata:
  category: reference
  tags:
    domain: [dotnet]
    depth: foundational
    pipeline: source

scope: consumer
triggers:
  - editorconfig
  - C# linting
  - code style
  - naming conventions
  - dotnet diagnostics
  - CA rules
  - IDE rules
  - diagnostic severity
  - .editorconfig
version: "1.0.0"
---

# dotnet-editorconfig

Provides the canonical `.editorconfig` template for C# projects in the dt-dotnet ecosystem.
This reference skill ships a battle-tested rule set covering code style enforcement, naming
conventions (including the non-obvious `_depcase` pattern for dependency injection and `T`
prefix for type parameters), and Godot-specific diagnostic suppressions. Use this when
establishing code standards, enforcing style rules across a team, or debugging diagnostic errors.

## When to Use

- When setting up or reviewing `.editorconfig` in a C# project
- When adding code style rules to enforce naming conventions (interfaces, public members, DI fields)
- When reviewing or suppressing `CA` (Code Analysis) or `IDE` diagnostics
- When the user mentions "editorconfig", "C# linting", "code style", "naming conventions", or specific rule IDs like CA1051, CA1822, IDE0005
- When setting up Godot projects that need to suppress framework-specific diagnostics

## Quick Reference

| Convention | Rule | Example |
|------------|------|---------|
| DI / readonly private fields | `_depcase` (`_` + camelCase) | `_socketManager`, `_logger` |
| Type parameters | `T` prefix + PascalCase | `TContext`, `TMessageType` |
| Interfaces | `I` prefix + PascalCase | `ILoggerProvider` |
| Public members (properties, methods, events) | PascalCase | `SendPositionUpdate`, `ConnectionTimeout` |
| Local vars / params | camelCase | `delta`, `position` |
| Private/internal fields | camelCase | `result`, `cache` |

### Key Diagnostic Severities

| Severity | When to Use | Examples |
|----------|-----------|----------|
| `error` | Non-negotiable rules (style enforcement, code quality) | IDE0001, CA1825, IDE0051, CA1806 |
| `warning` | Important but more flexible (e.g., unused parameters in overrides) | CA1822 (unused method params) |
| `none` | Disabled by design (e.g., IDE0040 for local function accessibility) | IDE0040 |

### Godot Framework Suppressions

```csharp
// Godot projects — add to files using Godot base classes
#pragma warning disable CA1501  // Godot class hierarchy exceeds CA depth limit
#pragma warning disable CA1051  // [Export] fields must be public for Godot inspector
```

---

## The .editorconfig Template

Copy this entire block and save as `.editorconfig` at your project root. Modify diagnostic
severities and naming styles to match your team's preferences.

```ini
# Remove the line below if you want to inherit .editorconfig settings from higher directories
root = true

[*.{cs}]

#### Core EditorConfig Options ####

# Indentation and spacing
indent_size = 4
indent_style = space
tab_width = 4

# New line preferences
end_of_line = crlf
insert_final_newline = false

#### .NET Coding Conventions ####

# Organize usings
dotnet_separate_import_directive_groups = false:error
dotnet_sort_system_directives_first = false:error

# this. and Me. preferences
dotnet_style_qualification_for_event = false:error
dotnet_style_qualification_for_field = false:error
dotnet_style_qualification_for_method = false:error
dotnet_style_qualification_for_property = false:error

# Language keywords vs BCL types preferences
dotnet_style_predefined_type_for_locals_parameters_members = true:error
dotnet_style_predefined_type_for_member_access = true:error

# Parentheses preferences
dotnet_style_parentheses_in_arithmetic_binary_operators = never_if_unnecessary:error
dotnet_style_parentheses_in_other_binary_operators = always_for_clarity:error
dotnet_style_parentheses_in_other_operators = never_if_unnecessary:error
dotnet_style_parentheses_in_relational_binary_operators = always_for_clarity:error

# Modifier preferences
dotnet_style_require_accessibility_modifiers = always:error

# Expression-level preferences
dotnet_style_coalesce_expression = true:error
dotnet_style_collection_initializer = true:error
dotnet_style_explicit_tuple_names = true:error
dotnet_style_namespace_match_folder = true:error
dotnet_style_null_propagation = true:error
dotnet_style_object_initializer = true:error
dotnet_style_prefer_auto_properties = true:error
dotnet_style_prefer_compound_assignment = true:error
dotnet_style_prefer_conditional_expression_over_assignment = true:error
dotnet_style_prefer_conditional_expression_over_return = true:error
dotnet_style_prefer_is_null_check_over_reference_equality_method = true:error
dotnet_style_prefer_simplified_boolean_expressions = true:error
dotnet_style_prefer_simplified_interpolation = true:error
dotnet_style_readonly_field = false:error
dotnet_code_quality_unused_parameters = all:error
dotnet_style_allow_statement_immediately_after_block_experimental = false:error

#### C# Coding Conventions ####

# var preferences
csharp_style_var_elsewhere = true:error
csharp_style_var_for_built_in_types = true:error
csharp_style_var_when_type_is_apparent = true:error

# Expression-bodied members
csharp_style_expression_bodied_accessors = true:error
csharp_style_expression_bodied_constructors = false:error
csharp_style_expression_bodied_methods = false:error
csharp_style_expression_bodied_properties = when_on_single_line:error

# Pattern matching preferences
csharp_style_pattern_matching_over_as_with_null_check = true:error
csharp_style_pattern_matching_over_is_with_cast_check = true:error
csharp_style_prefer_extended_property_pattern = true:error
csharp_style_prefer_not_pattern = true:error
csharp_style_prefer_switch_expression = true:error

# Modifier preferences
csharp_preferred_modifier_order = public,private,protected,internal,static,extern,new,virtual,abstract,sealed,override,readonly,unsafe,required,volatile,async

# Code-block preferences
csharp_prefer_braces = true:error
csharp_prefer_simple_using_statement = true:error
csharp_style_namespace_declarations = block_scoped:error

# Expression-level preferences
csharp_prefer_simple_default_expression = true:error
csharp_style_implicit_object_creation_when_type_is_apparent = true:error
csharp_style_inlined_variable_declaration = true:error
csharp_style_prefer_index_operator = true:error
csharp_style_prefer_null_check_over_type_check = true:error
csharp_style_prefer_range_operator = true:error

# 'using' directive preferences
csharp_using_directive_placement = outside_namespace:error

#### Naming styles ####

dotnet_naming_rule.interface_should_be_begins_with_i.severity = error
dotnet_naming_rule.interface_should_be_begins_with_i.symbols = interface
dotnet_naming_rule.interface_should_be_begins_with_i.style = begins_with_i

dotnet_naming_rule.types_should_be_pascal_case.severity = error
dotnet_naming_rule.types_should_be_pascal_case.symbols = types
dotnet_naming_rule.types_should_be_pascal_case.style = pascal_case

dotnet_naming_rule.public_member_should_be_pascal_case.severity = error
dotnet_naming_rule.public_member_should_be_pascal_case.symbols = public_member
dotnet_naming_rule.public_member_should_be_pascal_case.style = pascal_case

dotnet_naming_rule.dependency_should_be__depcase.severity = error
dotnet_naming_rule.dependency_should_be__depcase.symbols = dependency
dotnet_naming_rule.dependency_should_be__depcase.style = _depcase

dotnet_naming_rule.private_or_internal_field_should_be_camelcase.severity = error
dotnet_naming_rule.private_or_internal_field_should_be_camelcase.symbols = private_or_internal_field
dotnet_naming_rule.private_or_internal_field_should_be_camelcase.style = camelcase

dotnet_naming_rule.variables_should_be_camelcase.severity = error
dotnet_naming_rule.variables_should_be_camelcase.symbols = variables
dotnet_naming_rule.variables_should_be_camelcase.style = camelcase

dotnet_naming_rule.type_parameters_should_have_T_prefix.severity = error
dotnet_naming_rule.type_parameters_should_have_T_prefix.symbols = type_parameters
dotnet_naming_rule.type_parameters_should_have_T_prefix.style = type_parameter_style

dotnet_naming_symbols.interface.applicable_kinds = interface
dotnet_naming_symbols.interface.applicable_accessibilities = public, internal, private, protected, protected_internal, private_protected
dotnet_naming_symbols.interface.required_modifiers =

dotnet_naming_symbols.private_or_internal_field.applicable_kinds = field
dotnet_naming_symbols.private_or_internal_field.applicable_accessibilities = internal, private, private_protected
dotnet_naming_symbols.private_or_internal_field.required_modifiers =

dotnet_naming_symbols.types.applicable_kinds = namespace, class, struct, interface, enum
dotnet_naming_symbols.types.applicable_accessibilities = public, internal, private, protected, protected_internal, private_protected
dotnet_naming_symbols.types.required_modifiers =

dotnet_naming_symbols.public_member.applicable_kinds = property, field, event, delegate, method
dotnet_naming_symbols.public_member.applicable_accessibilities = public
dotnet_naming_symbols.public_member.required_modifiers =

dotnet_naming_symbols.dependency.applicable_kinds = field
dotnet_naming_symbols.dependency.applicable_accessibilities = private
dotnet_naming_symbols.dependency.required_modifiers = readonly

dotnet_naming_symbols.variables.applicable_kinds = parameter, local, local_function
dotnet_naming_symbols.variables.applicable_accessibilities = local
dotnet_naming_symbols.variables.required_modifiers =

dotnet_naming_symbols.type_parameters.applicable_kinds = type_parameter
dotnet_naming_symbols.type_parameters.applicable_accessibilities = public, internal, private, protected, protected_internal, private_protected
dotnet_naming_symbols.type_parameters.required_modifiers =

dotnet_naming_style.pascal_case.capitalization = pascal_case
dotnet_naming_style.begins_with_i.required_prefix = I
dotnet_naming_style.begins_with_i.capitalization = pascal_case
dotnet_naming_style._depcase.required_prefix = _
dotnet_naming_style._depcase.capitalization = camel_case
dotnet_naming_style.camelcase.capitalization = camel_case
dotnet_naming_style.type_parameter_style.required_prefix = T
dotnet_naming_style.type_parameter_style.capitalization = pascal_case

#### Code Quality — Key diagnostics at :error ####
dotnet_diagnostic.CA1051.severity = error
dotnet_diagnostic.CA1501.severity = error
dotnet_diagnostic.CA1507.severity = error
dotnet_diagnostic.CA1508.severity = error
dotnet_diagnostic.CA1700.severity = error
dotnet_diagnostic.CA1710.severity = error
dotnet_diagnostic.CA1716.severity = error
dotnet_diagnostic.CA1802.severity = error
dotnet_diagnostic.CA1806.severity = error
dotnet_diagnostic.CA1822.severity = warning
dotnet_diagnostic.CA1825.severity = error
dotnet_diagnostic.CA2200.severity = error
dotnet_diagnostic.CA2214.severity = error
dotnet_diagnostic.IDE0001.severity = error
dotnet_diagnostic.IDE0005.severity = error
dotnet_diagnostic.IDE0040.severity = none
dotnet_diagnostic.IDE0051.severity = error
dotnet_diagnostic.IDE0059.severity = error
dotnet_diagnostic.IDE0060.severity = error
```

---

## Workflow

### Step 1 — Add .editorconfig to Your Project

Copy the template from the "Quick Reference" section above to `.editorconfig` at your project root
(same directory as `*.csproj`). Commit this file to version control so all team members enforce
the same rules.

EditorConfig is hierarchical — if you have subdirectories that need different rules, you can create
additional `.editorconfig` files in those directories with `root = false` and add overrides.
The most specific `.editorconfig` (closest to the file) wins.

### Step 2 — Apply Naming Convention Rules to Your Codebase

The template defines six naming rules:

1. **Interfaces**: `IFoo` (required prefix `I`)
2. **Types** (classes, structs, enums): `PascalCase`
3. **Public members**: `PascalCase`
4. **DI fields**: `_depCase` (readonly private fields, the non-obvious one)
5. **Local vars/params**: `camelCase`
6. **Type parameters**: `TFoo` (required prefix `T`)

When you first enable this `.editorconfig` in Visual Studio or an IDE, it will show
squiggly lines under naming violations. Fix them in batches — IDEs often support batch
renaming via "Quick Actions".

The **`_depcase` rule for DI fields** is particularly important: it signals at a glance
that `_logger`, `_repository`, etc. are framework-injected dependencies, not internal state.
This convention helps code reviewers quickly understand the object's dependencies.

### Step 3 — Set Diagnostic Severities for Your Team

The template assigns diagnostics as `:error` (build-breaking) or `:warning` (advisory).
Most rules are `:error` to enforce consistency. A few are `:warning`:

- **CA1822** (`dotnet_diagnostic.CA1822.severity = warning`): "Method can be made static."
  This is advisory because making a method static breaks virtual dispatch — useful in some
  contexts but not always the right call.

If your team has different preferences (e.g., "naming violations are warnings, not errors"),
update the severity values and commit the change to `.editorconfig`.

### Step 4 — Handle Framework-Specific Suppressions

For Godot projects or other frameworks with special constraints, add pragma directives
at the file or class level:

```csharp
#pragma warning disable CA1501  // Godot class hierarchy exceeds CA depth limit
#pragma warning disable CA1051  // [Export] fields must be public for Godot inspector

public class Player : CharacterBody2D
{
    [Export] public float Speed = 100f;  // CA1051: must be public for [Export]

    public override void _Ready()
    {
        // implementation
    }
}

#pragma warning restore CA1501
#pragma warning restore CA1051
```

Do NOT disable diagnostics globally in `.editorconfig` (e.g., `dotnet_diagnostic.CA1051.severity = none`)
unless the entire project is Godot-based. Framework-specific suppressions should be localized
to the files that need them.

---

## Edge Cases

**IDE vs compiler behavior**: EditorConfig rules are enforced by the IDE (Visual Studio, Rider, VS Code with C# extensions)
at authoring time, not necessarily by `dotnet build`. If you want build-time enforcement,
enable the `EnforceCodeStyleInBuild` property in your `.csproj`:

```xml
<PropertyGroup>
  <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
</PropertyGroup>
```

**Conflicting rules in nested directories**: If you have a `library/` subdirectory with its own `.editorconfig`
(with `root = false`), rules there override the parent. This is useful for code generation tools that produce
code not subject to your naming conventions — put generated code in a subdirectory with relaxed rules.

**Unrecognized diagnostics**: Some diagnostics (especially preview/experimental ones) may not be recognized
in all versions of .NET or Visual Studio. If the IDE shows "unknown diagnostic", safely ignore it or update
the rule for your current .NET version. Preview diagnostics are typically removed or renamed in stable releases.

**Naming rule ambiguity**: The order of naming rules matters. If a symbol matches multiple rules, the first match wins.
The template orders rules from most-specific to least-specific (interface → types → public members → dependencies → variables → type params).
If you add custom rules, follow the same pattern.

---

## Anti-Patterns

**Disabling all diagnostics**: Setting `severity = none` for entire diagnostic categories is tempting but counterproductive.
It defeats the purpose of linting. If a rule conflicts with your team's style, update the rule (e.g., change `csharp_style_var_elsewhere`
from `true` to `false`) rather than disabling it.

**Per-file pragma directives everywhere**: If you're adding `#pragma warning disable CA1051` to half your files, the rule is wrong
for your codebase. Instead, disable it globally in `.editorconfig` or refactor the code to comply. Pragmas are for exceptions,
not the norm.

**Not committing .editorconfig**: Leaving `.editorconfig` out of version control means each developer gets different rules.
Always commit it so the team enforces the same standards.

**Mixing naming conventions**: The template uses `_depcase` for DI fields and `camelCase` for local vars. Don't use `_camelCase`
for all private fields — it obscures the semantic difference between injected dependencies and internal state.

**Ignoring IDE suggestions**: When the IDE highlights a naming violation or offers a quick action, addressing it immediately
is cheaper than letting violations accumulate. Batch fixes are efficient but proactive fixes are better.
