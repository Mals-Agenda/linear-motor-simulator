# Tools Reference

## Project Tools

### get_project_info
Returns project metadata including name, Godot version, viewport settings, renderer, and autoloads.

### get_filesystem_tree
Scans the project directory and returns a tree structure.
- `path` (optional): Root path (default: `res://`)
- `filter` (optional): Glob pattern like `*.gd`, `*.tscn`
- `max_depth` (optional): Maximum recursion depth (default: 10)

### search_files
Fuzzy search for files by name.
- `query` (required): Search string or glob pattern
- `path` (optional): Root path
- `file_type` (optional): Extension filter (`gd`, `tscn`, etc.)
- `max_results` (optional): Limit results (default: 50)

### get_project_settings
Read settings from project.godot.
- `section` (optional): Filter by section prefix (e.g. `display/window`)
- `key` (optional): Get a specific setting

### uid_to_project_path / project_path_to_uid
Convert between UIDs (`uid://...`) and resource paths (`res://...`).

## Scene Tools

### get_scene_tree
Returns the live node hierarchy of the currently edited scene.
- `max_depth` (optional): Limit tree depth

### get_scene_file_content
Reads the raw .tscn file.
- `path` (required): Scene file path

### create_scene
Creates a new scene file.
- `path` (required): Where to save
- `root_type` (optional): Root node type (default: `Node2D`)
- `root_name` (optional): Root node name

### open_scene / delete_scene
Open or delete a scene file by path.

### add_scene_instance
Instance a scene as a child node.
- `scene_path` (required): Scene to instance
- `parent_path` (optional): Parent node (default: root)
- `name` (optional): Instance name

### play_scene / stop_scene
Run or stop scenes. `play_scene` accepts `mode`: `main`, `current`, or a file path.

## Node Tools

### add_node
Add a node to the scene.
- `type` (required): Node class name
- `parent_path` (optional): Parent node path
- `name` (optional): Node name
- `properties` (optional): Dict of property values

### delete_node / duplicate_node / move_node
Modify scene tree structure. All support undo.

### update_property
Set any node property. Values are auto-parsed:
- `"Vector2(100, 200)"` → Vector2
- `"#ff0000"` or `"Color(1, 0, 0)"` → Color
- `"true"` / `"false"` → bool
- Numbers → int/float

### get_node_properties
Get all editor-visible properties of a node.
- `category` (optional): Filter prefix

### add_resource
Create and assign a resource to a node property.
- `resource_type`: Class name (e.g. `RectangleShape2D`)
- `resource_properties` (optional): Properties for the resource

### set_anchor_preset
Set anchor preset on Control nodes. Available presets: `top_left`, `center`, `full_rect`, etc.

### rename_node
Rename a node in the current scene.
- `node_path` (required): Path to the node
- `new_name` (required): New name for the node

### connect_signal
Connect a signal from one node to a method on another node.
- `source_path` (required): Path to the source node (emitter)
- `signal_name` (required): Signal name to connect
- `target_path` (required): Path to the target node (receiver)
- `method_name` (required): Method name on target to call

### disconnect_signal
Disconnect a signal connection between two nodes.
- `source_path` (required): Path to the source node (emitter)
- `signal_name` (required): Signal name to disconnect
- `target_path` (required): Path to the target node (receiver)
- `method_name` (required): Method name on target

## Script Tools

### list_scripts
Find all scripts with class/extends info.

### read_script / create_script
Read or create script files.

### edit_script
Edit scripts via:
1. `replacements`: Array of `{search, replace, regex?}` operations
2. `content`: Full file replacement
3. `insert_at_line` + `text`: Insert at specific line

### attach_script
Attach a script to a node in the current scene.

### get_open_scripts
List scripts currently open in the script editor.

## Editor Tools

### get_editor_errors
Get recent errors from the Godot log.

### get_editor_screenshot / get_game_screenshot
Capture viewport as PNG (returned as base64 image).

### execute_editor_script
Run arbitrary GDScript in the editor context. Use `_mcp_print(value)` to capture output.

### clear_output
Clear the editor output panel.

### get_signals
Get all signals of a node, including current connections.
- `node_path` (required): Path to the node to inspect

### reload_plugin
Reload the Godot MCP Pro plugin (disable/re-enable). Connection will briefly drop and auto-reconnect.

### reload_project
Rescan the Godot project filesystem and reload changed scripts. No reconnection needed.

### save_scene
Save the currently edited scene to disk.
- `path` (optional): Path to save to (defaults to current scene path)

### set_project_setting
Set a project setting value via the editor API.
- `key` (required): Setting key (e.g. `display/window/size/viewport_width`)
- `value` (required): Value to set (auto-parsed for Vector2, bool, int, float)

## Input Tools

### simulate_key
Simulate a keyboard key press/release in the running game.
- `keycode` (required): Key constant (e.g. `KEY_SPACE`, `KEY_W`)
- `pressed` (optional): true for press, false for release
- `ctrl`, `shift`, `alt` (optional): Modifier keys

### simulate_mouse_click
Simulate a mouse button click at a position in the running game.
- `x`, `y` (optional): Viewport position
- `button` (optional): 1=left, 2=right, 3=middle
- `pressed` (optional): true for press, false for release

### simulate_mouse_move
Simulate mouse movement in the running game.
- `x`, `y` (optional): Target position
- `relative_x`, `relative_y` (optional): Relative movement

### simulate_action
Simulate a Godot Input Action in the running game.
- `action` (required): Action name from Input Map
- `pressed` (optional): true for press, false for release
- `strength` (optional): 0.0–1.0

### simulate_sequence
Simulate a sequence of input events with frame delays.
- `events` (required): Array of input events
- `frame_delay` (optional): Frames between events

## Runtime Tools

### get_game_scene_tree
Get the scene tree of the currently running game.
- `max_depth` (optional): Maximum tree depth

### get_game_node_properties
Get properties of a node in the running game.
- `node_path` (required): Absolute node path
- `properties` (optional): Specific property names to read

### capture_frames
Capture multiple screenshots at regular frame intervals from the running game.
- `count` (optional): Number of frames (1–30)
- `frame_interval` (optional): Frames between captures
- `half_resolution` (optional): Halve resolution to reduce data size

### monitor_properties
Record property values over multiple frames from the running game.
- `node_path` (required): Absolute node path
- `properties` (required): Property names to monitor
- `frame_count` (optional): Number of samples (1–600)
- `frame_interval` (optional): Frames between samples

## Animation Tools

### list_animations
List all animations in an AnimationPlayer node.
- `node_path` (required): Path to the AnimationPlayer

### create_animation
Create a new animation in an AnimationPlayer.
- `node_path` (required): Path to the AnimationPlayer
- `name` (required): Animation name
- `length` (optional): Length in seconds (default: 1.0)
- `loop_mode` (optional): 0=none, 1=linear, 2=pingpong

### add_animation_track
Add a track to an animation.
- `node_path` (required): Path to the AnimationPlayer
- `animation` (required): Animation name
- `track_path` (required): Node path and property (e.g. `Sprite2D:position`)
- `track_type` (optional): value, position_2d, rotation_2d, scale_2d, method, bezier, blend_shape
- `update_mode` (optional): continuous, discrete, capture

### set_animation_keyframe
Insert a keyframe into an animation track.
- `node_path` (required): Path to the AnimationPlayer
- `animation` (required): Animation name
- `track_index` (required): Track index
- `time` (required): Time position in seconds
- `value` (required): Keyframe value (auto-parsed)

### get_animation_info
Get detailed info about an animation including all tracks and keyframes.
- `node_path` (required): Path to the AnimationPlayer
- `animation` (required): Animation name

### remove_animation
Remove an animation from an AnimationPlayer.
- `node_path` (required): Path to the AnimationPlayer
- `name` (required): Animation name

## TileMap Tools

### tilemap_set_cell
Set a single cell in a TileMapLayer.
- `node_path` (required): Path to the TileMapLayer
- `x`, `y` (required): Cell coordinates
- `source_id` (optional): Tile source ID
- `atlas_x`, `atlas_y` (optional): Atlas coordinates
- `alternative` (optional): Alternative tile ID

### tilemap_fill_rect
Fill a rectangular region with tiles.
- `node_path` (required): Path to the TileMapLayer
- `x1`, `y1`, `x2`, `y2` (required): Rectangle bounds
- `source_id`, `atlas_x`, `atlas_y`, `alternative` (optional): Tile data

### tilemap_get_cell
Get tile data at a specific cell.
- `node_path` (required): Path to the TileMapLayer
- `x`, `y` (required): Cell coordinates

### tilemap_clear
Clear all cells in a TileMapLayer.
- `node_path` (required): Path to the TileMapLayer

### tilemap_get_info
Get TileMapLayer info including tile set sources and cell count.
- `node_path` (required): Path to the TileMapLayer

### tilemap_get_used_cells
Get a list of used (non-empty) cells.
- `node_path` (required): Path to the TileMapLayer
- `max_count` (optional): Maximum cells to return (default: 500)

## Theme Tools

### create_theme
Create a new Theme resource file.
- `path` (required): Save path (e.g. `res://themes/main.tres`)
- `default_font_size` (optional): Default font size

### set_theme_color
Set a theme color override on a Control node.
- `node_path` (required): Path to the Control node
- `name` (required): Color name (e.g. `font_color`)
- `color` (required): Hex color string

### set_theme_constant
Set a theme constant override on a Control node.
- `node_path` (required): Path to the Control node
- `name` (required): Constant name
- `value` (required): Integer value

### set_theme_font_size
Set a theme font size override on a Control node.
- `node_path` (required): Path to the Control node
- `name` (required): Font size name (e.g. `font_size`)
- `size` (required): Font size in pixels

### set_theme_stylebox
Set a StyleBoxFlat override on a Control node.
- `node_path` (required): Path to the Control node
- `name` (required): Style name (e.g. `panel`, `normal`)
- `bg_color` (optional): Background color
- `border_color` (optional): Border color
- `border_width` (optional): Border width
- `corner_radius` (optional): Corner radius
- `padding` (optional): Content padding

### get_theme_info
Get theme information and overrides for a Control node.
- `node_path` (required): Path to the Control node

## Profiling Tools

### get_performance_monitors
Get all Godot performance monitors (FPS, memory, draw calls, physics, navigation).
- `category` (optional): Filter by prefix (e.g. `render`, `physics_2d`)

### get_editor_performance
Get a quick performance summary (FPS, frame time, draw calls, memory).

## Batch & Refactoring Tools

### find_nodes_by_type
Find all nodes of a specific type in the current scene.
- `type` (required): Node class name
- `recursive` (optional): Search recursively (default: true)

### find_signal_connections
Find all signal connections in the current scene.
- `signal_name` (optional): Filter by signal name
- `node_path` (optional): Filter by node path

### batch_set_property
Set a property on all nodes of a given type.
- `type` (required): Node type to target
- `property` (required): Property name
- `value` (required): Value to set (auto-parsed)

### find_node_references
Search through project files for a text pattern.
- `pattern` (required): Text pattern to search for

### get_scene_dependencies
Get all resource dependencies of a scene or resource file.
- `path` (required): Path to the file

## Shader Tools

### create_shader
Create a new shader file with template or custom content.
- `path` (required): Shader file path
- `shader_type` (optional): spatial, canvas_item, particles, sky
- `content` (optional): Full shader code

### read_shader
Read the content of a shader file.
- `path` (required): Path to the shader file

### edit_shader
Edit a shader file using full replacement or search-and-replace.
- `path` (required): Path to the shader file
- `content` (optional): Full replacement content
- `replacements` (optional): Array of `{search, replace}` operations

### assign_shader_material
Create a ShaderMaterial from a shader and assign to a node.
- `node_path` (required): Target node path
- `shader_path` (required): Path to the shader file

### set_shader_param
Set a shader parameter on a node's ShaderMaterial.
- `node_path` (required): Node with ShaderMaterial
- `param` (required): Parameter name
- `value` (required): Parameter value (auto-parsed)

### get_shader_params
Get all shader parameters from a node's ShaderMaterial.
- `node_path` (required): Node with ShaderMaterial

## Export Tools

### list_export_presets
List all export presets configured in export_presets.cfg.

### export_project
Get the export command for a preset.
- `preset_name` (optional): Preset name
- `preset_index` (optional): Preset index
- `debug` (optional): Debug export (default: true)

### get_export_info
Get export-related project info (executable path, templates directory, project path).
