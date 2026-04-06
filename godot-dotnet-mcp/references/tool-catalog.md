
## Scene Tools

Category: `scene` | Domain: `core`

### management

Controls the currently edited scene.

| Action | Description | Parameters |
|--------|-------------|------------|
| `get_current` | Get currently open scene path | -- |
| `open` | Open a scene for editing | `path` |
| `save` | Save current scene | -- |
| `save_as` | Save scene to new path | `path` |
| `create` | Create new scene | `path`, `root_type`, `name` |
| `close` | Close current scene | -- |
| `reload` | Reload from disk | -- |

### hierarchy

Inspect and select nodes in the current scene.

| Action | Description | Parameters |
|--------|-------------|------------|
| `get_tree` | Get scene tree structure | `depth`, `include_internal` |
| `get_selected` | Get currently selected nodes | -- |
| `select` | Select nodes by path | `paths` (array) |

### run

Run or stop scenes for testing.

| Action | Description | Parameters |
|--------|-------------|------------|
| `play_main` | Run the main scene | -- |
| `play_current` | Run the current scene | -- |
| `play_custom` | Run a specific scene | `path` |
| `stop` | Stop the running scene | -- |

### bindings

Analyze exported script members used by a scene.

| Action | Description | Parameters |
|--------|-------------|------------|
| `current` | Analyze current scene | -- |
| `from_path` | Analyze scene at path | `path` |

### audit

Return structured scene issues from exported bindings.

| Action | Description | Parameters |
|--------|-------------|------------|
| `current` | Audit current scene | -- |
| `from_path` | Audit scene at path | `path` |

---

## Node Tools

Category: `node` | Domain: `core`

The workhorse for manipulating individual nodes. 9 tools, approximately 80 actions.

### query

Node discovery and inspection.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `find_by_name` | Find nodes by name | `name` |
| `find_by_type` | Find nodes by type | `type` |
| `find_children` | Find child nodes | `path`, `pattern`, `type` |
| `find_parent` | Find parent matching criteria | `path` |
| `get_info` | Get node metadata | `path` |
| `get_children` | List direct children | `path` |
| `get_path_to` | Get relative path between nodes | `from`, `to` |
| `tree_string` | Debug string of subtree | `path` |

### lifecycle

Node creation, deletion, duplication.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `create` | Create a new node | `type`, `name`, `parent` |
| `delete` | Remove a node | `path` |
| `duplicate` | Copy a node | `path`, `name` |
| `instantiate` | Instantiate a PackedScene | `scene`, `parent`, `name` |
| `replace` | Replace node with another type | `path`, `type` |
| `rename` | Rename a node | `path`, `name` |
| `attach_script` | Attach a script to node | `path`, `script` |
| `request_ready` | Re-trigger _ready() | `path` |

### transform

Position, rotation, scale manipulation.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `set_position` | Set position | `path`, `x`, `y`, `z` |
| `set_rotation` | Set rotation (radians) | `path`, `x`, `y`, `z` |
| `set_rotation_degrees` | Set rotation (degrees) | `path`, `x`, `y`, `z` |
| `set_scale` | Set scale | `path`, `x`, `y`, `z` |
| `get_transform` | Get full transform | `path` |
| `move` | Translate by delta | `path`, `x`, `y`, `z` |
| `rotate` | Rotate by delta | `path`, `axis`, `angle` |
| `look_at` | Point at target | `path`, `target` |
| `reset` | Reset to identity | `path` |

### property

Generic property access.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `get` | Get a property value | `path`, `property` |
| `set` | Set a property value | `path`, `property`, `value` |
| `list` | List all properties | `path` |
| `reset` | Reset property to default | `path`, `property` |
| `revert` | Revert to scene default | `path`, `property` |

### hierarchy

Parent-child relationship management.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `reparent` | Move node to new parent | `path`, `new_parent` |
| `reorder` | Set child index | `path`, `index` |
| `move_up` / `move_down` | Shift in sibling order | `path` |
| `move_to_front` / `move_to_back` | Move to first/last | `path` |
| `set_owner` / `get_owner` | Scene ownership | `path`, `owner` |

### process

Processing and input control.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `get_status` | Get processing state | `path` |
| `set_process` | Enable/disable _process | `path`, `enabled` |
| `set_physics_process` | Enable/disable _physics_process | `path`, `enabled` |
| `set_input` | Enable/disable _input | `path`, `enabled` |
| `set_process_mode` | Set process mode | `path`, `mode` |

### metadata

Custom metadata operations.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `get` / `set` / `has` / `remove` / `list` | CRUD on node metadata | `path`, `key`, `value` |

### call

Method invocation on nodes.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `call` | Call a method | `path`, `method`, `args` |
| `call_deferred` | Deferred call | `path`, `method`, `args` |
| `propagate_call` | Call on node and descendants | `path`, `method`, `args` |
| `has_method` | Check method existence | `path`, `method` |
| `get_method_list` | List methods | `path` |

### visibility

Rendering control.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `show` / `hide` / `toggle` | Visibility control | `path` |
| `is_visible` | Check visibility | `path` |
| `set_z_index` | Set render order | `path`, `z_index` |
| `set_modulate` | Set color modulation | `path`, `color` |

---

## Script Tools

Category: `script` | Domain: `core`

### read

Read Godot script files (`.gd` or `.cs`) as plain text.

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | string | Script file path |

### open

Open scripts in Godot's editor.

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | string | Script file path |
| `line` | integer | Optional line number to jump to |

### inspect

Parse scripts and return language-aware metadata.

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | string | Script path |

### symbols

List parsed symbols with filtering.

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | string | Script path |
| `kind` | string | Filter: `function`, `variable`, `signal`, `export`, etc. |
| `name` | string | Filter by name pattern |

### exports

Return exported members from scripts.

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | string | Script path |

### references

Build cross-file index for scene usage and inheritance lookups.

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | string | Script path |

### edit_gd

Template-based editing for GDScript files only.

Operations: create, write, delete, add/remove members, list functions/variables.

### edit_cs

Template-based editing for C# script files.

Operations: create scripts from namespace/class/base_type, add fields/methods with indentation handling.

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | string | C# script path |
| `action` | string | Operation type |
| `namespace` | string | For create |
| `class_name` | string | For create |
| `base_type` | string | For create |
| `name` | string | Member name |
| `type` | string | Member type |
| `body` | string | Method body |

---

## Resource Tools

Category: `resource` | Domain: `core`

### query

Search and list resources.

| Action | Parameters | Description |
|--------|-----------|-------------|
| `list` | `path`, `type`, `recursive` | List resources in directory |
| `search` | `pattern`, `type` | Search by pattern |
| `get_info` | `path` | Resource metadata |
| `get_dependencies` | `path` | Resource dependencies |

### create

Create a new resource file.

| Parameter | Type | Description |
|-----------|------|-------------|
| `type` | string | Resource type (GDScript, Resource, Environment, StandardMaterial3D, etc.) |
| `path` | string | Destination path |

### file_ops

File operations on resources.

| Action | Parameters | Description |
|--------|-----------|-------------|
| `copy` | `source`, `dest` | Copy resource |
| `move` | `source`, `dest` | Move/rename resource |
| `delete` | `source` | Delete resource |
| `reload` | `source` | Reload from disk |

### texture

Texture resource management.

| Action | Parameters | Description |
|--------|-----------|-------------|
| `get_info` | `path` | Texture metadata |
| `list_all` | -- | List all textures |
| `assign_to_node` | `texture_path`, `node_path`, `property` | Assign texture to node |

---

## Project Tools

Category: `project` | Domain: `core`

### info

| Action | Description |
|--------|-------------|
| `get_info` | Basic project details |
| `get_settings` | Project configuration |
| `get_features` | Enabled features and platform info |
| `get_export_presets` | Configured export configurations |

### dotnet

Parse `.csproj` and extract .NET project metadata. Auto-discovers `.csproj` when path omitted. Returns TargetFramework, AssemblyName, RootNamespace, DefineConstants, PackageReference, ProjectReference.

### settings

| Action | Parameters | Description |
|--------|-----------|-------------|
| `set` | `setting`, `value` | Update a setting |
| `reset` | `setting` | Restore default |
| `list_category` | `category` | View all settings in category |

### input

Input action management.

| Action | Description |
|--------|-------------|
| `list_actions` | All input actions |
| `get_action` | Specific action bindings |
| `add_action` / `remove_action` | Create/delete input actions |
| `add_binding` / `remove_binding` | Manage keybindings |

### autoload

| Action | Description |
|--------|-------------|
| `list` | All autoloads |
| `add` / `remove` | Register/unregister autoload |
| `reorder` | Adjust loading order |

---

## Editor Tools

Category: `editor` | Domain: `core`

### status

| Action | Description |
|--------|-------------|
| `get_info` | Editor state information |
| `get_main_screen` / `set_main_screen` | Current editor screen (2D, 3D, Script, AssetLib) |
| `get_distraction_free` / `set_distraction_free` | Distraction-free mode |

### settings

Editor preferences. Actions: `get`, `set`, `list_category`, `reset`.

### undo_redo

Full undo/redo system control: `get_info`, `undo`, `redo`, `create_action`, `commit_action`, `add_do_property`, `add_undo_property`, `add_do_method`, `add_undo_method`, `merge_mode`.

### notification

| Action | Parameters | Description |
|--------|-----------|-------------|
| `toast` | `message`, `severity` | Toast notification |
| `popup` | `message`, `title` | Popup dialog |
| `confirm` | `message`, `title` | Confirmation dialog |

### inspector

| Action | Description |
|--------|-------------|
| `edit_object` | Focus inspector on node |
| `get_edited` | Get currently inspected object |
| `refresh` | Refresh inspector |
| `inspect_resource` | Inspect a resource file |

### filesystem

FileSystem dock operations: `select_file`, `get_selected`, `get_current_path`, `scan`, `reimport`.

### plugin

Editor plugin management: `list`, `is_enabled`, `enable`, `disable`.

---

## Debug Tools

Category: `debug` | Domain: `core`

### log_write

Write messages to Godot's console. Actions: `print`, `warning`, `error`, `rich`.

### log_buffer

Read buffered MCP debug events. Actions: `get_recent`, `get_errors`, `clear_buffer`.

### runtime_bridge

Read structured runtime events from running project.

| Action | Description |
|--------|-------------|
| `get_recent` | Recent events |
| `get_errors` | Error events only |
| `get_sessions` | Session list |
| `get_summary` | Summary statistics |
| `clear_buffer` | Clear buffer |
| `get_recent_filtered` | Filter by level (error/warning/info) |
| `get_errors_context` | Errors with surrounding context |
| `get_scene_snapshot` | Running scene tree snapshot |

### dotnet

Run .NET build operations. Actions: `restore`, `build`. Parameters: `path`, `timeout_sec`.

### performance

Metrics: `get_fps`, `get_memory`, `get_monitors`, `get_render_info`.

### profiler

Built-in profiler control: `start`, `stop`, `is_active`, `get_summary`.

### editor_log

Editor Output panel: `get_output`, `get_errors`, `clear`.

### class_db

Query Godot's ClassDB: `get_class_list`, `get_class_info`, `get_class_methods`, `get_class_properties`, `get_class_signals`, `get_inheriters`, `class_exists`.

---

## Physics Tools

Category: `physics` | Domain: `gameplay`

### physics_body

Create and configure physics bodies (2D/3D).

| Action | Description |
|--------|-------------|
| `create` | Create physics body (rigid_body_3d, character_body_3d, static_body_3d, area_3d, and 2D variants) |
| `get_info` | Body properties |
| `set_mode` / `set_mass` / `set_gravity_scale` | Configure physics properties |
| `set_linear_velocity` / `set_angular_velocity` | Set velocities |
| `apply_force` / `apply_impulse` | Apply forces |
| `set_layers` / `set_mask` | **Collision layers and masks** |
| `freeze` | Freeze body |

### collision_shape

Manage collision shapes with auto 2D/3D detection.

| Action | Description |
|--------|-------------|
| `create` | Create collision shape |
| `create_box` / `create_sphere` / `create_capsule` / `create_cylinder` | Create specific shapes |
| `set_shape` / `set_size` | Configure shape |
| `set_disabled` | Enable/disable |
| `make_convex_from_siblings` | Generate convex shape from mesh siblings |

### physics_joint

Create and configure joints: `pin_joint_3d`, `hinge_joint_3d`, `slider_joint_3d`, `cone_twist_joint_3d`, `generic_6dof_joint_3d` (and 2D variants).

### physics_query

Perform raycasts and spatial queries.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `raycast` | Cast a ray | `from`, `to`, `mode` (2d/3d), `collision_mask` |
| `shape_cast` | Cast a shape | `from`, `to`, `path` |
| `point_check` | Check point for collisions | `point`, `mode` |
| `intersect_shape` | Find overlapping shapes | `path` |
| `list_bodies_in_area` | Bodies in an Area node | `path` |

---

## Signal Tools

Category: `signal` | Domain: `core`

Single tool: `signal`.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `list` | All signals on a node | `path`, `include_inherited` |
| `get_info` | Signal metadata | `path`, `signal` |
| `list_connections` | Active connections | `path`, `signal` |
| `connect` | Connect signal to method | `source`, `target`, `signal`, `method`, `flags` |
| `disconnect` | Remove connection | `source`, `target`, `signal`, `method` |
| `disconnect_all` | Remove all connections | `path`, `signal` |
| `emit` | Trigger signal manually | `path`, `signal`, `args` (max 4) |
| `is_connected` | Check connection | `source`, `target`, `signal`, `method` |
| `list_all_connections` | All connections in scene | -- |

---

## Group Tools

Category: `group` | Domain: `core`

Single tool: `group`.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `list` | Groups a node belongs to | `path` |
| `add` / `remove` | Add/remove from group | `path`, `group` |
| `is_in` | Check membership | `path`, `group` |
| `get_nodes` | All nodes in a group | `group` |
| `call_group` | Call method on all group members | `group`, `method`, `args` |
| `set_group` | Set property on all group members | `group`, `property`, `value` |

---

## Filesystem Tools

Category: `filesystem` | Domain: `core`

### directory

Manage directories: `list`, `create`, `delete`, `exists`, `get_files`.

### file_read

Read files: `read`, `exists`, `get_info`.

### file_write

Write files: `write`, `append`.

### file_manage

File operations: `delete`, `copy`, `move`.

### json

JSON file operations: `read`, `write`, `get_value`, `set_value` (dot-separated key paths).

### search

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `find_files` | Find files by pattern | `pattern`, `path`, `recursive` |
| `grep` | Search file content | `find`, `filter`, `path` |
| `find_and_replace` | Find and replace in files | `find`, `replace`, `filter`, `path` |

---

## Animation Tools

Category: `animation` | Domain: `visual`

8 tools covering the full animation system:

- **player**: Control AnimationPlayer nodes (play, stop, pause, seek, speed)
- **animation**: Create/manage animation resources (create, delete, duplicate, set_length, set_loop)
- **track**: Manage tracks and keyframes (add_property_track, add_method_track, add_key, remove_key)
- **tween**: Procedural tweens (create, property, method, callback)
- **animation_tree**: Animation blending (create, set_active, set_root, set_parameter)
- **state_machine**: State-based animation (add_state, add_transition, travel, get_current)
- **blend_space**: 1D/2D blend spaces (add_point, set_blend_mode, triangulate)
- **blend_tree**: Complex animation graphs (add_node, connect, disconnect, set_position)

---

## Material Tools

Category: `material` | Domain: `visual`

### material

Create and configure materials (StandardMaterial3D, ORMMaterial3D, ShaderMaterial, CanvasItemMaterial).

Actions: `create`, `get_info`, `set_property`, `get_property`, `list_properties`, `assign_to_node`, `duplicate`, `save`.

### mesh

Mesh operations and primitives.

Actions: `get_info`, `list_surfaces`, `get_surface_material`, `set_surface_material`, `create_primitive` (box, sphere, cylinder, capsule, plane, prism, torus, quad), `get_aabb`.

---

## Shader Tools

Category: `shader` | Domain: `visual`

### shader

Create and manage shaders (spatial, canvas_item, particles, sky, fog).

Actions: `create`, `read`, `write`, `get_info`, `get_uniforms`, `set_default`.

### shader_material

ShaderMaterial instance management.

Actions: `create`, `get_info`, `set_shader`, `get_param`, `set_param`, `list_params`, `assign_to_node`.

---

## Lighting Tools

Category: `lighting` | Domain: `visual`

- **light**: Create and configure lights. Actions: `create`, `get_info`, `set_color`, `set_energy`, `set_shadow`, `set_range`, `set_angle`, `set_bake_mode`, `list`.
- **environment**: Environment settings. Actions: `create`, `get_info`, `set_background`, `set_ambient`, `set_fog`, `set_glow`, `set_ssao`, `set_ssr`, `set_tonemap`, etc.
- **sky**: Sky configuration. Actions: `create`, `set_procedural`, `set_physical`, `set_panorama`.

---

## Navigation Tools

Category: `navigation` | Domain: `gameplay`

Single tool: `navigation`.

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `get_map_info` | Navigation map config | `mode` (2d/3d) |
| `list_regions` / `list_agents` | Enumerate nav nodes | -- |
| `bake_mesh` | Bake navigation mesh | `path` |
| `get_path` | Compute path between points | `from`, `to`, `mode` |
| `set_agent_target` | Set agent destination | `path`, `target` |
| `get_agent_info` | Agent state | `path` |
| `set_region_enabled` / `set_agent_enabled` | Toggle nodes | `path`, `enabled` |

---

## Particle Tools

Category: `particle` | Domain: `visual`

- **particles**: Create and control particle emitters (GPU/CPU, 2D/3D). Actions: `create`, `get_info`, `set_emitting`, `restart`, `set_amount`, `set_lifetime`, `set_process_material`, `convert_to_cpu`, etc.
- **particle_material**: Configure ParticleProcessMaterial. Actions: `set_direction`, `set_spread`, `set_gravity`, `set_velocity`, `set_color`, `set_emission_shape`, etc.

---

## UI Tools

Category: `ui` | Domain: `interface`

- **theme**: Create and manage UI themes. Actions: `create`, `set_color`, `set_constant`, `set_font`, `set_font_size`, `set_stylebox`, `assign_to_node`, etc.
- **control**: Control node layout. Actions: `get_layout`, `set_anchor`, `set_anchor_preset`, `set_margins`, `set_size_flags`, `set_min_size`, `set_focus_mode`, `set_mouse_filter`, `arrange`.

---

## Audio Tools

Category: `audio` | Domain: `gameplay`

- **bus**: Audio bus management. Actions: `list`, `get_info`, `add`, `remove`, `set_volume`, `set_mute`, `set_solo`, `add_effect`, `remove_effect`, etc.
- **player**: AudioStreamPlayer control. Actions: `list`, `get_info`, `play`, `stop`, `pause`, `seek`, `set_volume`, `set_pitch`, `set_bus`, `set_stream`.

---

## TileMap Tools

Category: `tilemap` | Domain: `visual`

- **tileset**: TileSet resource management. Actions: `create_empty`, `assign_to_tilemap`, `get_info`, `list_sources`, `get_source`, `list_tiles`, `get_tile_data`.
- **tilemap**: TileMap cell operations. Actions: `get_info`, `get_cell`, `set_cell`, `erase_cell`, `fill_rect`, `clear_layer`, `get_used_cells`, `get_used_rect`.

---

## Geometry Tools

Category: `geometry` | Domain: `visual`

- **csg**: Constructive Solid Geometry. Actions: `create`, `get_info`, `set_operation` (union/intersection/subtraction), `set_material`, `set_size`, `set_use_collision`, `bake_mesh`, `list`.
- **gridmap**: 3D tile-based levels. Actions: `create`, `get_info`, `set_mesh_library`, `get_cell`, `set_cell`, `erase_cell`, `clear`, `get_used_cells`, `set_cell_size`.
- **multimesh**: Instanced rendering. Actions: `create`, `get_info`, `set_mesh`, `set_instance_count`, `set_transform`, `set_color`, `populate_random`, `clear`.

---

## Plugin Runtime Tools

Category: `plugin_runtime` | Domain: `plugin`

### state

Plugin health and diagnostics: `list_loaded_domains`, `get_reload_status`, `get_tool_usage_stats`, `get_self_health`, `get_self_errors`, `get_self_timeline`, `clear_self_diagnostics`, `get_lsp_diagnostics_status`.

### reload

Hot-reload tools: `reload_domain`, `reload_all_domains`, `soft_reload_plugin`, `full_reload_plugin`.

### server

Restart the embedded MCP server without changing tool registration.

### toggle

Enable/disable tools: `set_tool_enabled`, `set_category_enabled`, `set_domain_enabled`.

### usage_guide

Returns the recommended runtime control and reload workflow.

---

## Plugin Evolution Tools

Category: `plugin_evolution` | Domain: `plugin`

Manage user-extensible tools lifecycle:

- **list_user_tools**: List all registered user-category tools
- **scaffold_user_tool**: Preview or create a tool scaffold (requires `authorized: true`)
- **delete_user_tool**: Preview or delete a user tool script
- **restore_user_tool**: Restore most recently deleted tool
- **user_tool_audit**: Read recent audit entries
- **check_compatibility**: Compare user tools against current scaffold version
- **usage_guide**: Authorization and workflow documentation

---

## Plugin Developer Tools

Category: `plugin_developer` | Domain: `plugin`

Advanced plugin configuration:

- **settings**: Read dock-facing developer settings
- **log_level**: Set min debug level (trace/debug/info/warning/error)
- **user_visibility**: Toggle user category visibility in dock
- **list_languages** / **set_language**: UI language control
- **list_profiles** / **apply_profile** / **save_profile** / **rename_profile** / **delete_profile**: Tool preset management
- **export_config** / **import_config**: Export/import tool configuration to JSON
- **usage_guide**: Development and debug loop documentation

---
