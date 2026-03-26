import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerSceneTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "get_scene_tree",
    "Get the live scene tree of the currently edited scene, showing all nodes, types, and hierarchy",
    {
      max_depth: z.number().optional().describe("Max tree depth to return (-1 for unlimited)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_scene_tree", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_scene_file_content",
    "Read the raw .tscn file content of a scene",
    {
      path: z.string().describe("Path to the scene file (e.g. 'res://scenes/main.tscn')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_scene_file_content", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "create_scene",
    "Create a new scene file with a specified root node type",
    {
      path: z.string().describe("Path for the new scene (e.g. 'res://scenes/enemy.tscn')"),
      root_type: z.string().optional().describe("Root node type (default: Node2D). Examples: Node2D, Node3D, Control, CharacterBody2D"),
      root_name: z.string().optional().describe("Root node name (defaults to filename)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("create_scene", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "open_scene",
    "Open a scene file in the Godot editor",
    {
      path: z.string().describe("Path to the scene file (e.g. 'res://scenes/main.tscn')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("open_scene", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "delete_scene",
    "Delete a scene file from the project",
    {
      path: z.string().describe("Path to the scene file to delete"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("delete_scene", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "add_scene_instance",
    "Add an existing scene as a child node (instancing) in the current scene",
    {
      scene_path: z.string().describe("Path to the scene to instance (e.g. 'res://scenes/enemy.tscn')"),
      parent_path: z.string().optional().describe("Parent node path (default: root '.')"),
      name: z.string().optional().describe("Custom name for the instance"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_scene_instance", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "play_scene",
    "Run a scene in the Godot editor (main scene, current scene, or specific path)",
    {
      mode: z.string().optional().describe("'main' (default), 'current', or a scene file path"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("play_scene", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "stop_scene",
    "Stop the currently playing scene",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("stop_scene");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "save_scene",
    "Save the currently edited scene to disk",
    {
      path: z.string().optional().describe("Optional path to save to (defaults to current scene path)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("save_scene", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_scene_exports",
    "Get all @export variables from all scripted nodes in a scene file. Useful for inspecting configurable parameters without opening the scene.",
    {
      path: z.string().describe("Path to the scene file (e.g. 'res://scenes/enemy.tscn')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_scene_exports", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
