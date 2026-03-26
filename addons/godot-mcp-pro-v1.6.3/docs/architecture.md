# Architecture

## Overview

```
┌─────────────┐     stdio/MCP      ┌──────────────┐    WebSocket:6505    ┌──────────────────┐
│  AI Client   │ ←────────────────→ │  Node.js MCP │ ←──────────────────→ │  Godot Plugin    │
│ (Claude Code)│                    │    Server     │    JSON-RPC 2.0     │  (Editor Plugin) │
└─────────────┘                     └──────────────┘                      └──────────────────┘
```

## Communication Flow

1. AI client sends MCP tool call (e.g. `add_node`)
2. Node.js server translates to JSON-RPC 2.0 request
3. WebSocket sends to Godot plugin
4. Plugin's command router dispatches to handler
5. Handler executes via Godot Editor API (with UndoRedo)
6. Result sent back as JSON-RPC 2.0 response
7. Node.js formats as MCP tool result
8. AI receives structured response

## Godot Plugin Structure

```
plugin.gd (EditorPlugin)
├── websocket_server.gd (TCP+WebSocket server)
├── command_router.gd (dispatch hub)
│   ├── project_commands.gd (6 commands)
│   ├── scene_commands.gd (8 commands)
│   ├── node_commands.gd (8 commands)
│   ├── script_commands.gd (6 commands)
│   └── editor_commands.gd (5 commands)
└── ui/status_panel (connection monitor)
```

## Key Design Decisions

### WebSocket over HTTP
- Real-time bidirectional communication
- Natural for editor integration (persistent connection)
- Heartbeat keeps connection alive

### JSON-RPC 2.0
- Standard protocol with well-defined error codes
- Each request has unique ID for tracking
- Easy to debug and extend

### UndoRedo Integration
- All scene modifications go through `EditorUndoRedoManager`
- Users can Ctrl+Z any AI-made change
- Prevents accidental data loss

### Type Parsing
- `PropertyParser` handles string → Godot type conversion
- Supports Vector2/3, Color, Rect2, NodePath, etc.
- AI can send simple strings, plugin handles the rest

## Error Codes

| Code | Meaning |
|------|---------|
| -32700 | Parse error (invalid JSON) |
| -32600 | Invalid request |
| -32601 | Method not found |
| -32602 | Invalid params |
| -32603 | Internal error |
| -32000 | No scene open |
| -32001 | Node/resource not found |
| -32002 | Script compilation failed |
