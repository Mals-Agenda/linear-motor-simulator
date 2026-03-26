import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerAnalysisTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "find_unused_resources",
    "Scan the project for resource files (.tres, .tscn, .png, .wav, .ogg, .ttf, .gdshader, etc.) that are not referenced by any .tscn, .gd, or .tres file. Useful for cleaning up unused assets.",
    {
      path: z.string().optional().describe("Root path to scan (default: res://)"),
      include_addons: z.boolean().optional().describe("Include addons/ directory in scan (default: false)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("find_unused_resources", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "analyze_signal_flow",
    "Map all signal connections in the currently edited scene. Returns a graph-like structure showing which nodes emit which signals and which nodes receive them.",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("analyze_signal_flow");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "analyze_scene_complexity",
    "Analyze a scene's complexity: total node count, max nesting depth, nodes grouped by type, attached scripts, and potential issues (too many nodes, deep nesting).",
    {
      path: z.string().optional().describe("Scene path to analyze (default: currently edited scene)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("analyze_scene_complexity", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "find_script_references",
    "Find all places where a given script path, class_name, or resource path is referenced across the project. Searches .tscn, .gd, and .tres files.",
    {
      query: z.string().describe("The script path, class_name, or resource path to search for (e.g. 'res://scripts/player.gd', 'PlayerController', 'res://assets/icon.png')"),
      path: z.string().optional().describe("Root path to search (default: res://)"),
      include_addons: z.boolean().optional().describe("Include addons/ directory in search (default: false)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("find_script_references", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "detect_circular_dependencies",
    "Check for circular scene dependencies where Scene A instances Scene B which instances Scene A (directly or indirectly). Walks all .tscn files and builds a dependency graph.",
    {
      path: z.string().optional().describe("Root path to scan (default: res://)"),
      include_addons: z.boolean().optional().describe("Include addons/ directory in scan (default: false)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("detect_circular_dependencies", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_project_statistics",
    "Get overall project statistics: file counts by extension, total script lines, scene count, resource count, autoload list, and enabled plugins.",
    {
      path: z.string().optional().describe("Root path to scan (default: res://)"),
      include_addons: z.boolean().optional().describe("Include addons/ directory in statistics (default: false)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_project_statistics", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
