---

## CrystalMagica Workflows

### Project Context

CrystalMagica is a Godot 4.6.1 MMO 2D platformer using C# 14 / .NET 10. It follows MVVM: Views (nodes) bind to ViewModels via Rx. The `[Export]` attribute wires scene references.

Key files:
- `res://Scenes/Main.tscn` -- root scene with World, Player, RemoteCharacters, Enemies, HUD
- `res://Scenes/Enemy.tscn` -- CharacterBody3D with EnemyNode.cs, SphereMesh, CollisionShape3D
- `res://Views/EnemyNode.cs` -- extends PlayerNode, implements IBindable, Rx subscriptions

### Workflow: Verify Scene Wiring After Changes

After modifying `.tscn` or C# scripts, verify that `[Export]` properties are correctly wired:

```
1. bindings_audit  scene="res://Scenes/Enemy.tscn"
   -> checks EnemyNode.cs [Export] Mesh matches the "EnemyMesh" node path

2. bindings_audit  script="res://Views/EnemyNode.cs"
   -> checks all exports/signals have valid scene references

3. scene_analyze  scene="res://Scenes/Main.tscn"
   -> verify node count, script attachments, signal bindings
```

### Workflow: Reading Scene Tree Programmatically

To inspect the Enemy.tscn structure:

```
1. scene management  action="open"  path="res://Scenes/Enemy.tscn"
2. scene hierarchy   action="get_tree"  depth=3

Expected result:
  Enemy (CharacterBody3D) [script: EnemyNode.cs]
    EnemyMesh (MeshInstance3D)
    EnemyCollission (CollisionShape3D)
```

### Workflow: Inspecting Collision Layers

CrystalMagica uses collision layers to separate player vs enemy vs environment:

```
1. node property  action="get"  path="Enemy"  property="collision_layer"
2. node property  action="get"  path="Enemy"  property="collision_mask"
3. physics physics_body  action="get_info"  path="Enemy"
```

### Workflow: Verifying Export Properties

The EnemyNode has `[Export] public MeshInstance3D Mesh` wired to `NodePath("EnemyMesh")`:

```
1. script exports  path="res://Views/EnemyNode.cs"
   -> returns: Mesh (MeshInstance3D)

2. bindings_audit  script="res://Views/EnemyNode.cs"
   -> verifies NodePath("EnemyMesh") resolves to an actual MeshInstance3D node

3. node property  action="get"  path="Enemy"  property="Mesh"
   -> should return NodePath("EnemyMesh")
```

### Workflow: Diagnosing Runtime Issues

When the game throws errors during testing:

```
1. scene run  action="play_main"
   -> launches the game

2. debug runtime_bridge  action="get_errors"
   -> read runtime errors with context

3. intelligence runtime_diagnose  include_compile_errors=true  tail=20
   -> full error report with stacktraces

4. debug dotnet  action="build"
   -> verify .NET compilation succeeds

5. scene run  action="stop"
```

### Workflow: Loop Implementation Cycle

During CrystalMagica development loops (e.g., Loop 02 -- Server Spawned Entity):

```
1. intelligence project_state
   -> baseline: are there existing errors?

2. intelligence project_advise  goal="add_feature"
   -> get recommendations

3. script script_analyze  script="res://Views/EnemyNode.cs"
   -> understand current class structure before modifying

4. [Make code changes via normal file editing]

5. debug dotnet  action="build"
   -> verify compilation

6. bindings_audit  scene="res://Scenes/Enemy.tscn"
   -> verify [Export] wiring after changes

7. scene run  action="play_main"
   -> test

8. intelligence runtime_diagnose
   -> check for runtime errors

9. scene run  action="stop"
```

### Workflow: Adding a New Node to an Existing Scene

To add a node to Main.tscn (e.g., adding the Enemies ItemsNode):

```
1. scene management  action="open"  path="res://Scenes/Main.tscn"

2. scene_patch  scene="res://Scenes/Main.tscn"  dry_run=true  ops=[
     {"op": "add_node", "parent": "World", "name": "Enemies", "type": "Node3D"}
   ]
   -> preview the change

3. scene_patch  scene="res://Scenes/Main.tscn"  dry_run=false  ops=[
     {"op": "add_node", "parent": "World", "name": "Enemies", "type": "Node3D"},
     {"op": "attach_script", "path": "World/Enemies", "script": "res://Views/ItemsNode.cs"}
   ]
   -> apply the change

4. scene management  action="save"
```

