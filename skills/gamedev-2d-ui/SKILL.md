---
name: gamedev-2d-ui
description: >
  Game UI/HUD patterns in Godot 4 — health bars, inventory, dialog systems, damage numbers,
  menus, and multiplayer UI. Load when building game interfaces, HUD overlays, inventory
  screens, dialog boxes, or settings menus, or when the user mentions "game UI", "HUD",
  "health bar", "mana bar", "inventory", "dialog system", "damage numbers", "floating text",
  "game menu", "pause menu", "settings menu", "key rebinding", "multiplayer UI", "nameplates",
  "party frames", "trade window", "lobby browser", "Godot Control", "CanvasLayer",
  "GridContainer", "RichTextLabel", "BBCode", or "tooltip".
triggers:
  - game UI
  - HUD
  - health bar
  - inventory
  - dialog system
  - damage numbers
  - floating text
  - game menu
  - CanvasLayer
  - Godot Control
  - tooltip
version: "1.0.0"
---

# Game UI/HUD Patterns (Godot 4)

## Control Node Fundamentals

### CanvasLayer for HUD Separation

All game UI belongs on a CanvasLayer so it renders independently of the game world camera.

```
GameWorld (Node2D)
  ├── Camera2D
  └── ...
HUDLayer (CanvasLayer, layer = 10)
  └── HUD (Control)
MenuLayer (CanvasLayer, layer = 20)
  └── PauseMenu
TooltipLayer (CanvasLayer, layer = 30)
  └── TooltipPanel
```

Higher layer numbers render on top. Use distinct layers: HUD (10), floating text (15), menus (20), tooltips (30), transitions (100).

### Anchoring and Margins

| Anchor Preset | Anchors | Use Case |
|---------------|---------|----------|
| Top-Left | all 0.0 | Health bar, player portrait |
| Top-Right | left/right = 1.0, top = 0.0 | Minimap, currency display |
| Bottom-Center | left = 0.5, right = 0.5, bottom = 1.0 | Action bar, XP bar |
| Full Rect | all corners fill | Pause menu overlay, dialog backdrop |
| Center | all 0.5 | Popup dialogs, item comparison |

For responsive layouts that adapt to resolution changes, use Container nodes (HBoxContainer, VBoxContainer, MarginContainer) rather than hardcoding pixel offsets.

### Theme Resources

Create a shared Theme resource for consistent styling. Apply at the root Control node — all children inherit automatically. Theme defines fonts, colors, styleboxes, and spacing for every Control type.

## HUD Elements

Key HUD components:

- **Health/Mana bars**: `TextureProgressBar` for polished, `ProgressBar` + theme overrides for quick prototyping. Use smooth lerp to target value. Layered bars for damage-flash effect.
- **Minimap**: `SubViewportContainer` → `SubViewport` → `Camera2D` following player at low zoom.
- **Buff icons**: `TextureRect` + timer overlay with radial cooldown shader progress.
- **XP bar**: `ProgressBar` anchored bottom center showing level + current/max XP.
- **Currency**: Animated counter that smoothly interpolates displayed value toward target.

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for full implementations of all HUD components.

## Inventory UI

### Grid-Based Inventory

Use `GridContainer` (columns = 8) to lay out inventory slots. Each slot is a `PanelContainer` with icon and stack count label.

**Drag and drop**: Godot's built-in `_get_drag_data`, `_can_drop_data`, `_drop_data` on Control nodes. Always set `set_drag_preview()` with a visual clone of the item.

**Tooltip**: Autoload on a high CanvasLayer (layer = 30). Always clamp tooltip position to viewport bounds.

### Equipment Slots

Named slots (not a grid). Map body parts to slot containers.

| Slot | Accepts |
|------|---------|
| Head | Helmets, crowns |
| Chest | Armor, robes |
| Legs | Pants, greaves |
| Main Hand | Swords, staffs |
| Off Hand | Shields, orbs |
| Ring 1/2 | Rings |
| Amulet | Necklaces |

Equipment slots reuse the drag-and-drop interface but add type checking in `_can_drop_data`:
```gdscript
return data["item"].get("equip_slot", "") == slot_type
```

**Item comparison**: On hover over equippable, show side-by-side stats with color-coded diffs (green = upgrade, red = downgrade).

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for inventory grid, slot, and tooltip implementations.

## Dialog System

### RichTextLabel with BBCode

| Tag | Effect | Use Case |
|-----|--------|----------|
| `[b]...[/b]` | Bold | Speaker names, important words |
| `[i]...[/i]` | Italic | Thoughts, flavor text |
| `[color=#hex]...[/color]` | Text color | NPC name colors, keyword highlights |
| `[wave amp=30 freq=4]...[/wave]` | Wavy text | Magical speech |
| `[shake rate=20 level=5]...[/shake]` | Shaking text | Anger, fear |
| `[img]res://icon.png[/img]` | Inline image | Item icons, button prompts |
| `[hint=tooltip text]...[/hint]` | Hover tooltip | Lore terms, item references |

### Key Dialog Patterns

- **Typewriter effect**: Use `visible_characters` on `RichTextLabel`, incrementing at `characters_per_second`. Emit `line_finished` signal when complete. Allow player to skip via `ui_accept`.
- **Portrait display**: `TextureRect` that swaps texture based on speaker + emotion.
- **Branching dialog trees**: Store in external JSON files — separates content from logic, enables localization. Dialog manager autoload processes the tree and handles conditional choices.

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for typewriter and dialog manager implementations.

## Damage Numbers

Spawn `Label` nodes at the damage location on a dedicated CanvasLayer (layer = 15), animate upward with a tween, then free. Use a spawner autoload for world→screen position conversion.

**Damage type color reference:**

| Damage Type | Color | Hex |
|-------------|-------|-----|
| Physical | White | `#FFFFFF` |
| Fire | Orange-red | `#FF6619` |
| Ice | Light blue | `#4DB3FF` |
| Poison | Green | `#33E633` |
| Heal | Bright green | `#33FF66` |
| Crit | Gold | `#FFD900` |
| Miss/Dodge | Gray | `#888888` |

Crits: larger font (28px vs 18px), "!" suffix, scale pop animation.

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for full damage number and spawner implementations.

## Menus

### Main Menu

`VBoxContainer` of Buttons inside `CenterContainer`. Disable Continue button if no save exists.

### Pause Menu

Set `get_tree().paused = true`. The pause menu's `process_mode` must be `PROCESS_MODE_WHEN_PAUSED` to still receive input. Toggle visibility on `pause` action.

### Settings Menu

Organize into tabs using `TabContainer`:
- **Audio**: `HSlider` per bus → `AudioServer.set_bus_volume_db()` with `linear_to_db()`
- **Video**: Fullscreen toggle, VSync toggle, resolution `OptionButton` → `DisplayServer`
- **Controls**: Key rebinding using `InputMap` — list actions, capture new `InputEventKey`, call `action_erase_events` + `action_add_event`

### Screen Transitions

`ColorRect` with `AnimationPlayer` on persistent CanvasLayer (layer = 100). Autoload: `change_scene(path)` plays fade_out → changes scene → plays fade_in.

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for settings and transition implementations.

## Multiplayer UI

### Nameplates

`Label` on CanvasLayer that follows entity. Convert world position to screen space using camera offset. Color by relationship:

| Relationship | Color | Hex |
|-------------|-------|-----|
| Self | White | `#FFFFFF` |
| Party member | Blue | `#4488FF` |
| Friendly NPC | Green | `#44CC44` |
| Hostile player | Red | `#FF4444` |
| Neutral | Yellow | `#CCCC44` |

### Party Frames

`VBoxContainer` of compact `HBoxContainer` rows (portrait + name + HP bar + MP bar). Update via signals from player data changes.

### Trade Window

Two-panel layout. Both players must confirm before trade executes. Reset confirmation state when either side changes their offer.

### Chat Input

`LineEdit` + `OptionButton` for channels. Hidden until `chat_open` action. Support `/p` and `/w` prefix commands for party/whisper.

### Lobby Browser

`VBoxContainer` or `ItemList` of server rows. Async refresh, click-to-select, join button.

See [references/gdscript-implementations.md](references/gdscript-implementations.md) for nameplate, trade window, and chat implementations.

## Godot MCP Integration

### UI Scene Scaffolding Workflows

**HUD scene workflow:**
1. `scene_create` — root: CanvasLayer (layer = 10)
2. Add Control (HUD, full rect anchor)
3. Add TextureProgressBar (HealthBar) anchored top-left: `offset_left=10, offset_top=10, offset_right=210, offset_bottom=30`
4. Add TextureProgressBar (ManaBar) below
5. Add HBoxContainer (BuffContainer) below bars
6. Add SubViewportContainer (Minimap) anchored top-right
7. Add SubViewport → Camera2D inside minimap container
8. `scene_save`

**Inventory scene workflow:**
1. `scene_create` — root: CanvasLayer (layer = 20)
2. PanelContainer centered (anchor_left=0.5, anchor_right=0.5, anchor_top=0.5, anchor_bottom=0.5)
3. MarginContainer → VBoxContainer → Label + GridContainer (columns = 8)
4. `scene_save`

### CanvasLayer Ordering

| Layer | Purpose |
|-------|---------|
| 10 | HUD (health, mana, buffs, minimap) |
| 15 | Floating text (damage numbers, XP popups) |
| 20 | Menus (inventory, dialog, pause, settings) |
| 30 | Tooltips |
| 100 | Scene transitions |

**Verification workflow:** `scene_create` → `editor_run` → check `editor_debug_output` for layout warnings → `editor_stop` → adjust → repeat.

## Anti-Patterns

| # | Anti-Pattern | Problem | Fix |
|---|-------------|---------|-----|
| 1 | UI in game world space | Camera movement moves the HUD | Place all UI on a CanvasLayer |
| 2 | Hardcoded pixel positions | UI breaks at different resolutions | Use anchors and Container nodes |
| 3 | Polling UI state every frame | Checking `player.health` in `_process` | Use signals — update only on change |
| 4 | One massive UI scene | Editor lag, merge conflicts | Split into sub-scenes |
| 5 | No input guard on menus | Player moves while typing in chat | Pause tree or consume input events |
| 6 | Theme per Control | Inconsistent styling | One shared Theme resource |
| 7 | Direct node references in dialog | Tightly couples data and display | Use a dialog manager autoload + signals |
| 8 | Drag-drop without preview | Nothing visible while dragging | Always set `set_drag_preview()` |
| 9 | Tooltip with no viewport clamping | Clips off screen edges | Clamp to viewport bounds before showing |
| 10 | Missing state reset on menu close | Stale hover/selection state on reopen | Reset in `_on_visibility_changed` |
| 11 | Font fallback not configured | Missing chars render as boxes | Set fallback fonts in Theme |
| 12 | Damage numbers as children of entities | Disappear when entity dies | Spawn on dedicated CanvasLayer (layer 15) |

## Cross-References

| Skill | When to Load |
|-------|-------------|
| `gamedev-2d-platformer` | Player movement, combat, camera that the HUD wraps |
| `gamedev-2d-art-pipeline` | Sprite creation, UI icon workflows, texture atlas |
| `gamedev-godot` | Godot engine fundamentals, scene architecture, MCP setup |
| `gamedev-multiplayer` | Netcode for syncing UI state: health, inventory, trade |
