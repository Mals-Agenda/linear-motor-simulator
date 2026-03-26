import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerThemeTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "create_theme",
    "Create a new Theme resource file",
    {
      path: z.string().describe("Path to save the theme (e.g. 'res://themes/main.tres')"),
      default_font_size: z.number().optional().describe("Default font size"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("create_theme", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_theme_color",
    "Set a theme color override on a Control node",
    {
      node_path: z.string().describe("Path to the Control node"),
      name: z.string().describe("Color name (e.g. 'font_color', 'font_hover_color')"),
      color: z.string().describe("Color as hex string (e.g. '#ff0000') or name"),
      theme_type: z.string().optional().describe("Theme type (defaults to node's class)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_theme_color", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_theme_constant",
    "Set a theme constant override on a Control node",
    {
      node_path: z.string().describe("Path to the Control node"),
      name: z.string().describe("Constant name (e.g. 'margin_left', 'separation')"),
      value: z.number().describe("Integer value"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_theme_constant", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_theme_font_size",
    "Set a theme font size override on a Control node",
    {
      node_path: z.string().describe("Path to the Control node"),
      name: z.string().describe("Font size name (e.g. 'font_size')"),
      size: z.number().describe("Font size in pixels"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_theme_font_size", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_theme_stylebox",
    "Set a StyleBoxFlat override on a Control node with customizable appearance",
    {
      node_path: z.string().describe("Path to the Control node"),
      name: z.string().describe("Style name (e.g. 'panel', 'normal', 'hover', 'pressed')"),
      bg_color: z.string().optional().describe("Background color (hex)"),
      border_color: z.string().optional().describe("Border color (hex)"),
      border_width: z.number().optional().describe("Border width in pixels"),
      corner_radius: z.number().optional().describe("Corner radius in pixels"),
      padding: z.number().optional().describe("Content padding in pixels"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_theme_stylebox", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_theme_info",
    "Get theme information and overrides for a Control node",
    {
      node_path: z.string().describe("Path to the Control node"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_theme_info", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
