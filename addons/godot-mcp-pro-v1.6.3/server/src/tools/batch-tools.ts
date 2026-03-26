import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerBatchTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "find_nodes_by_type",
    "Find all nodes of a specific type in the current scene",
    {
      type: z.string().describe("Node type/class to search for (e.g. 'Sprite2D', 'Label', 'CollisionShape2D')"),
      recursive: z.boolean().optional().describe("Search recursively through children (default: true)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("find_nodes_by_type", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "find_signal_connections",
    "Find all signal connections in the current scene, optionally filtered by signal name or node",
    {
      signal_name: z.string().optional().describe("Filter by signal name (partial match)"),
      node_path: z.string().optional().describe("Filter by node path (partial match)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("find_signal_connections", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "batch_set_property",
    "Set a property on all nodes of a given type in the current scene",
    {
      type: z.string().describe("Node type to target (e.g. 'Label', 'Sprite2D')"),
      property: z.string().describe("Property name to set (e.g. 'visible', 'modulate')"),
      value: z.union([z.string(), z.number(), z.boolean()]).describe("Value to set. Strings auto-parsed for Vector2, Color, etc."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("batch_set_property", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "find_node_references",
    "Search through project files (.tscn, .gd, .tres, .gdshader) for a text pattern",
    {
      pattern: z.string().describe("Text pattern to search for"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("find_node_references", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_scene_dependencies",
    "Get all resource dependencies of a scene or resource file",
    {
      path: z.string().describe("Path to the scene or resource file (e.g. 'res://scenes/player.tscn')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_scene_dependencies", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "cross_scene_set_property",
    "Set a property on all nodes of a given type across ALL scene files in the project. Scans .tscn files, modifies matching nodes, and saves. Use for project-wide changes like updating all Label fonts or all Sprite2D modulate colors.",
    {
      type: z.string().describe("Node type to target (e.g. 'Label', 'Sprite2D')"),
      property: z.string().describe("Property name to set"),
      value: z.union([z.string(), z.number(), z.boolean()]).describe("Value to set. Strings auto-parsed for Vector2, Color, etc."),
      path_filter: z.string().optional().describe("Directory to search in (default: 'res://')"),
      exclude_addons: z.boolean().optional().describe("Exclude addons/ directory (default: true)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("cross_scene_set_property", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
