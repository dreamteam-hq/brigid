# Scene Integration — Current State vs Proposed Extensions

This reference shows the actual CrystalMagica source files as they exist today, then
describes the proposed additions for health bar and damage number support.

## Current State (as of Loop 02)

### Enemy.tscn — Actual Scene Tree

```
[gd_scene format=3 uid="uid://bog24184n2bt6"]

[ext_resource type="Script" uid="uid://dwbyx5sq624ur" path="res://Views/EnemyNode.cs" id="1_m1htj"]

[sub_resource type="SphereMesh" id="SphereMesh_7fd37"]

[sub_resource type="SphereShape3D" id="SphereShape3D_7fd37"]
radius = 0.50563383

[node name="Enemy" type="CharacterBody3D" unique_id=1877245998 node_paths=PackedStringArray("Mesh")]
script = ExtResource("1_m1htj")
Mesh = NodePath("EnemyMesh")

[node name="EnemyMesh" type="MeshInstance3D" parent="." unique_id=412624744]
mesh = SubResource("SphereMesh_7fd37")

[node name="EnemyCollission" type="CollisionShape3D" parent="." unique_id=378821896]
shape = SubResource("SphereShape3D_7fd37")
```

Scene tree (3 nodes):

```
Enemy (CharacterBody3D) — script: EnemyNode.cs
  +-- EnemyMesh (MeshInstance3D) — SphereMesh
  +-- EnemyCollission (CollisionShape3D) — SphereShape3D (note: typo in actual file)
```

### EnemyNode.cs — Actual Implementation

```csharp
using CrystalMagica.Game.Extensions;
using System.Reactive.Linq;
using Godot;
using System;
using CrystalMagica.Game.ViewModels;
using CrystalMagica.Models;

namespace CrystalMagica.Game.Views
{

    public partial class EnemyNode : PlayerNode, IBindable
    {

        [Export] public MeshInstance3D Mesh { get; set; }

        public void Bind(RemoteCharacterVM viewModel)
        {
            var material = new StandardMaterial3D
            {
                AlbedoColor = viewModel.Color
            };

            Mesh.SetSurfaceOverrideMaterial(0, material);

            _ = viewModel.Position.Subscribe(x => Position = x.ToGodot3D());

            _ = viewModel.Updates.Subscribe(x => {

                if(x.Action is CharacterActions.Jump)
                {
                    Jump();
                }
                else if(x.Action is CharacterActions.Stop)
                {
                    StopMoving();
                }
                else if(x is MoveBegin moveBegin)
                {
                    MoveBegin(moveBegin);
                }

            });

        }

        public void Bind(object viewModel)
        {
            if(viewModel is not RemoteCharacterVM typedVM)
            {
                throw new Exception("You bound the wrong thing");
            }

            Bind(typedVM);
        }
    }
}
```

**Key facts about the current implementation:**
- Single `[Export]` property: `Mesh` (MeshInstance3D)
- No `HealthBar` property
- No health subscription — `Bind()` handles color, position, and action updates only
- Error message in `Bind(object)` uses `new Exception("You bound the wrong thing")`
- No `_Process` override — all updates are Rx-push via subscriptions

### RemoteCharacterVM.cs — Actual Implementation

```csharp
using System;
using System.Numerics;
using System.Reactive.Linq;
using System.Reactive.Subjects;
using CrystalMagica.Game.Extensions;
using CrystalMagica.Models;

namespace CrystalMagica.Game.ViewModels
{
    public class RemoteCharacterVM
    {
        public Guid Id { get; set; }
        public Godot.Color Color { get; set; }
        public IObservable<Vector2> Position { get; set; }

        public Subject<CharacterAction> Updates { get; set; } = new();

        public RemoteCharacterVM(CharacterData data)
        {
            Id = data.Id;
            Color = data.Color.ToGodot();

            Position = Updates
                .Select(x => x.Position)
                .StartWith(data.Position)
                ;
        }
    }

}
```

**Key facts about the current implementation:**
- Properties: `Id`, `Color`, `Position`, `Updates`
- No `HealthRatio` observable
- No `DamageEvents` subject
- No `HealthUpdate` type — `CharacterData` has no `CurrentHp`/`MaxHp`

---

## PROPOSED FOR LOOP 4 — Health Bar Integration

> Everything below describes additions that do NOT exist in CrystalMagica today.
> These are design targets for when the health/damage system is implemented.

### Proposed Enemy.tscn Changes

Add a `HealthBar` MeshInstance3D child and update `node_paths` to export it:

```
Enemy (CharacterBody3D) — script: EnemyNode.cs
  +-- EnemyMesh (MeshInstance3D) — SphereMesh
  +-- EnemyCollission (CollisionShape3D) — SphereShape3D
  +-- HealthBar (MeshInstance3D) — QuadMesh + ShaderMaterial   <-- NEW
```

Scene file additions:

```
[ext_resource type="Shader" path="res://Shaders/HealthBar3D.gdshader" id="2"]

[sub_resource type="QuadMesh" id="QuadMesh_1"]
size = Vector2(0.8, 0.08)

[sub_resource type="ShaderMaterial" id="ShaderMaterial_1"]
shader = ExtResource("2")
shader_parameter/fill_color = Color(0.2, 0.8, 0.2, 1)
shader_parameter/damage_color = Color(0.8, 0.2, 0.2, 1)
shader_parameter/background_color = Color(0.1, 0.1, 0.1, 0.6)
shader_parameter/border_width = 0.02

[node name="Enemy" type="CharacterBody3D" node_paths=PackedStringArray("Mesh", "HealthBar")]
HealthBar = NodePath("HealthBar")

[node name="HealthBar" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.2, 0)
mesh = SubResource("QuadMesh_1")
surface_material_override/0 = SubResource("ShaderMaterial_1")
```

### Proposed EnemyNode.cs Additions

```csharp
// PROPOSED additions to EnemyNode — does NOT exist today
[Export] public MeshInstance3D HealthBar { get; set; }

// Add to Bind(RemoteCharacterVM viewModel):
_ = viewModel.HealthRatio.Subscribe(ratio =>
{
    if (IsInstanceValid(this))
        HealthBar.SetInstanceShaderParameter("health", ratio);
});
```

### Proposed RemoteCharacterVM.cs Additions

```csharp
// PROPOSED additions — does NOT exist today
// Requires: HealthUpdate type, CurrentHp/MaxHp on CharacterData

public IObservable<float> HealthRatio { get; set; }

// In constructor, after Position setup:
HealthRatio = Updates
    .Where(x => x is HealthUpdate)
    .Cast<HealthUpdate>()
    .Select(x => (float)x.CurrentHp / x.MaxHp)
    .StartWith(data.CurrentHp / (float)data.MaxHp);
```

### Proposed New Types

```csharp
// PROPOSED: new types — do not exist in CrystalMagica today

// Health update message from server
public record HealthUpdate(int CurrentHp, int MaxHp) : CharacterAction;

// Damage event for floating numbers
public record DamageEvent(int Amount, bool IsCrit);
```

### Proposed Nameplate Addition

```csharp
// PROPOSED: Nameplate class — does not exist today
// Requires: Name and IsHostile properties on RemoteCharacterVM
public partial class Nameplate : Label3D
{
    public void Bind(RemoteCharacterVM viewModel)
    {
        Text = viewModel.Name;
        Billboard = BaseMaterial3D.BillboardModeEnum.Enabled;
        FixedSize = true;
        FontSize = 24;
        OutlineSize = 4;
        PixelSize = 0.005f;
        Modulate = viewModel.IsHostile ? Colors.Red : Colors.LightGreen;
    }
}
```

Scene tree with all proposed additions:

```
Enemy (CharacterBody3D) — script: EnemyNode.cs
  +-- EnemyMesh (MeshInstance3D)
  +-- EnemyCollission (CollisionShape3D)
  +-- HealthBar (MeshInstance3D)      y = 1.2   <-- PROPOSED
  +-- Nameplate (Label3D)             y = 1.4   <-- PROPOSED
```
