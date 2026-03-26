import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerExportTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "list_export_presets",
    "List all export presets configured in export_presets.cfg",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("list_export_presets");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "export_project",
    "Get the export command for a preset (direct export from editor is not supported in Godot 4)",
    {
      preset_name: z.string().optional().describe("Export preset name"),
      preset_index: z.number().optional().describe("Export preset index (alternative to name)"),
      debug: z.boolean().optional().describe("Debug export (default: true)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("export_project", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_export_info",
    "Get export-related project info (executable path, templates, project path)",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("get_export_info");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
