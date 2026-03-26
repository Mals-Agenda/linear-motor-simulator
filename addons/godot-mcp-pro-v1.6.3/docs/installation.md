# Installation Guide

## Prerequisites

- Godot 4.3+ (tested with 4.6)
- Node.js 18+
- An MCP-compatible AI client (Claude Code, Claude Desktop, etc.)

## Step 1: Godot Plugin

1. Copy the `addons/godot_mcp/` folder into your Godot project
2. Open Project → Project Settings → Plugins
3. Find "Godot MCP Pro" and click Enable
4. You should see "MCP Server" appear in the bottom panel
5. The status should show "Waiting for connection..."

## Step 2: Node.js Server

```bash
cd server
npm install
npm run build
```

This creates the compiled server in `server/build/`.

## Step 3: MCP Client Configuration

### Claude Code (.mcp.json)

```json
{
  "mcpServers": {
    "godot-mcp-pro": {
      "command": "node",
      "args": ["/absolute/path/to/godot-mcp-pro/server/build/index.js"]
    }
  }
}
```

### Custom Port

Set the `GODOT_MCP_PORT` environment variable (default: 6505):

```json
{
  "mcpServers": {
    "godot-mcp-pro": {
      "command": "node",
      "args": ["/absolute/path/to/server/build/index.js"],
      "env": { "GODOT_MCP_PORT": "6510" }
    }
  }
}
```

Also update the port in `plugin.gd` (line 3: `const PORT := 6505`).

## Troubleshooting

### Plugin doesn't appear
- Make sure the `addons/godot_mcp/` directory is inside your Godot project
- Check that `plugin.cfg` exists in the directory

### Connection fails
- Verify the Godot editor is running with the plugin enabled
- Check the bottom panel "MCP Server" tab for status
- Ensure no firewall is blocking localhost port 6505

### Tools timeout
- Commands have a 30-second timeout
- Large operations (full filesystem scan) may need the `max_depth` parameter
