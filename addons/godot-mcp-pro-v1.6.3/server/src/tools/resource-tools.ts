import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerResourceTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "read_resource",
    "Read a .tres resource file and return its properties. Works with any Godot Resource type (StyleBox, Font, Theme, Material, etc.)",
    {
      path: z.string().describe("Path to the resource file (e.g. 'res://themes/main_theme.tres')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("read_resource", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "edit_resource",
    "Edit properties of an existing .tres resource file. Changes are saved to disk immediately.",
    {
      path: z.string().describe("Path to the resource file (e.g. 'res://themes/main_theme.tres')"),
      properties: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).describe("Properties to set as key-value pairs. Values auto-parsed for Vector2, Color, etc."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("edit_resource", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "create_resource",
    "Create a new .tres resource file of a given type with optional initial properties",
    {
      path: z.string().describe("Path to save the resource (e.g. 'res://resources/player_stats.tres')"),
      type: z.string().describe("Resource type to create (e.g. 'StyleBoxFlat', 'LabelSettings', 'Environment')"),
      properties: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional().describe("Initial properties to set"),
      overwrite: z.boolean().optional().describe("Overwrite if file exists (default: false)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("create_resource", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_resource_preview",
    "Get a visual preview of an image or texture resource as a PNG. Works with .png, .jpg, .webp, .svg image files and Texture2D resources.",
    {
      path: z.string().describe("Path to the resource (e.g. 'res://assets/player.png', 'res://icon.svg')"),
      max_size: z.number().optional().describe("Maximum width/height in pixels, preserving aspect ratio (default: 256)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_resource_preview", params) as Record<string, unknown>;
        if (result && typeof result === "object" && "image_base64" in result) {
          return {
            content: [
              {
                type: "image" as const,
                data: result.image_base64 as string,
                mimeType: "image/png",
              },
              {
                type: "text" as const,
                text: `Preview of ${result.path}: ${result.width}x${result.height}`,
              },
            ],
          };
        }
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
