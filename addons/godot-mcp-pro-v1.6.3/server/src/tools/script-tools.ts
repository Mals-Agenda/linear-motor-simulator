import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerScriptTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "list_scripts",
    "List all GDScript/C#/shader files in the project with class info",
    {
      path: z.string().optional().describe("Root path to search (default: res://)"),
      recursive: z.boolean().optional().describe("Search recursively (default: true)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("list_scripts", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "read_script",
    "Read the full content of a GDScript file",
    {
      path: z.string().describe("Path to the script (e.g. 'res://scripts/player.gd')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("read_script", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "create_script",
    "Create a new GDScript file with optional content or auto-generated template",
    {
      path: z.string().describe("Path for the new script (e.g. 'res://scripts/enemy_ai.gd')"),
      content: z.string().optional().describe("Full script content. If empty, generates a template."),
      extends: z.string().optional().describe("Base class (default: 'Node'). Only used for template generation."),
      class_name: z.string().optional().describe("Class name to add. Only used for template generation."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("create_script", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "edit_script",
    "Edit a script using search-and-replace, full content replacement, or line insertion",
    {
      path: z.string().describe("Path to the script to edit"),
      replacements: z
        .array(
          z.object({
            search: z.string().describe("Text to find"),
            replace: z.string().describe("Replacement text"),
            regex: z.boolean().optional().describe("Use regex for search (default: false)"),
          })
        )
        .optional()
        .describe("Array of search-and-replace operations"),
      content: z.string().optional().describe("Full replacement content (replaces entire file)"),
      insert_at_line: z.number().optional().describe("Line number to insert text at (0-indexed)"),
      text: z.string().optional().describe("Text to insert (used with insert_at_line)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("edit_script", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "attach_script",
    "Attach a GDScript to a node in the current scene",
    {
      node_path: z.string().describe("Path to the target node"),
      script_path: z.string().describe("Path to the script file (e.g. 'res://scripts/player.gd')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("attach_script", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "validate_script",
    "Validate a GDScript file by attempting to compile it. Returns whether the script is valid. Use get_output_log or get_editor_errors for detailed error messages on failure.",
    {
      path: z.string().describe("Path to the script to validate (e.g. 'res://scripts/player.gd')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("validate_script", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_open_scripts",
    "Get a list of scripts currently open in the Godot script editor",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("get_open_scripts");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
