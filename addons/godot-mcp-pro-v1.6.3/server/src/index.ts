#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { GodotConnection } from "./godot-connection.js";
import { registerProjectTools } from "./tools/project-tools.js";
import { registerSceneTools } from "./tools/scene-tools.js";
import { registerNodeTools } from "./tools/node-tools.js";
import { registerScriptTools } from "./tools/script-tools.js";
import { registerEditorTools } from "./tools/editor-tools.js";
import { registerInputTools } from "./tools/input-tools.js";
import { registerRuntimeTools } from "./tools/runtime-tools.js";
import { registerAnimationTools } from "./tools/animation-tools.js";
import { registerTilemapTools } from "./tools/tilemap-tools.js";
import { registerThemeTools } from "./tools/theme-tools.js";
import { registerProfilingTools } from "./tools/profiling-tools.js";
import { registerBatchTools } from "./tools/batch-tools.js";
import { registerShaderTools } from "./tools/shader-tools.js";
import { registerExportTools } from "./tools/export-tools.js";
import { registerResourceTools } from "./tools/resource-tools.js";
import { registerAnimationTreeTools } from "./tools/animation-tree-tools.js";
import { registerPhysicsTools } from "./tools/physics-tools.js";
import { registerScene3DTools } from "./tools/scene-3d-tools.js";
import { registerParticleTools } from "./tools/particle-tools.js";
import { registerNavigationTools } from "./tools/navigation-tools.js";
import { registerAudioTools } from "./tools/audio-tools.js";
import { registerTestTools } from "./tools/test-tools.js";
import { registerAnalysisTools } from "./tools/analysis-tools.js";
import { registerInputMapTools } from "./tools/input-map-tools.js";

const LITE_MODE = process.argv.includes("--lite");

const godot = new GodotConnection(
  parseInt(process.env.GODOT_MCP_PORT || "6505")
);

const server = new McpServer({
  name: LITE_MODE ? "godot-mcp-pro-lite" : "godot-mcp-pro",
  version: "1.5.0",
});

// Core tools (always registered)
registerProjectTools(server, godot);
registerSceneTools(server, godot);
registerNodeTools(server, godot);
registerScriptTools(server, godot);
registerEditorTools(server, godot);
registerInputTools(server, godot);
registerRuntimeTools(server, godot);
registerInputMapTools(server, godot);

// Extended tools (Full mode only)
if (!LITE_MODE) {
  registerAnimationTools(server, godot);
  registerAnimationTreeTools(server, godot);
  registerAudioTools(server, godot);
  registerBatchTools(server, godot);
  registerExportTools(server, godot);
  registerNavigationTools(server, godot);
  registerParticleTools(server, godot);
  registerPhysicsTools(server, godot);
  registerProfilingTools(server, godot);
  registerResourceTools(server, godot);
  registerScene3DTools(server, godot);
  registerShaderTools(server, godot);
  registerTestTools(server, godot);
  registerThemeTools(server, godot);
  registerTilemapTools(server, godot);
  registerAnalysisTools(server, godot);
}

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Attempt initial connection to Godot (non-blocking)
  godot.connect().catch((err) => {
    console.error(
      `[MCP] Initial Godot connection failed: ${err.message}. Will retry on first command.`
    );
  });

  console.error(LITE_MODE
    ? "[MCP] Godot MCP Pro LITE started (76 tools, stdio transport)"
    : "[MCP] Godot MCP Pro started (stdio transport)");
}

main().catch((err) => {
  console.error("[MCP] Fatal error:", err);
  process.exit(1);
});
