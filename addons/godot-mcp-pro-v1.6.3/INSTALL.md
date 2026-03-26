# Godot MCP Pro - Installation Guide

## Step 1: Install the Godot Plugin

Copy the `addons/godot_mcp/` folder into your Godot project's `addons/` directory.

Then enable the plugin in Godot:
**Project → Project Settings → Plugins → Godot MCP Pro → Enable**

You should see "MCP Pro" in the bottom panel.

## Step 2: Install the MCP Server

```bash
cd server
npm install
npm run build
```

Requires Node.js 18+.

## Step 3: Configure Your AI Assistant

Add to your project's `.mcp.json` (for Claude Code):

```json
{
  "mcpServers": {
    "godot-mcp-pro": {
      "command": "node",
      "args": ["/path/to/server/build/index.js"],
      "env": {
        "GODOT_MCP_PORT": "6505"
      }
    }
  }
}
```

Replace `/path/to/` with the actual path where you extracted the files.

## Step 4: Use It

1. Open your Godot project with the plugin enabled
2. Start Claude Code (or Cursor/Cline) in your project directory
3. Ask the AI to interact with your Godot editor

## Troubleshooting

- **Plugin not connecting**: Check that the MCP server is running and the port matches (default: 6505)
- **Port conflict**: Set a different port via `GODOT_MCP_PORT` environment variable (6505-6509)
- **Need help?**: Contact abyo.software@gmail.com

## Documentation

- Full tool reference: https://godot-mcp.abyo.net
- All 49 tools documented in `docs/tools-reference.md`
