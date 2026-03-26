import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerTilemapTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "tilemap_set_cell",
    "Set a single cell in a TileMapLayer",
    {
      node_path: z.string().describe("Path to the TileMapLayer node"),
      x: z.number().describe("Cell X coordinate"),
      y: z.number().describe("Cell Y coordinate"),
      source_id: z.number().optional().describe("Tile source ID (default: 0)"),
      atlas_x: z.number().optional().describe("Atlas X coordinate (default: 0)"),
      atlas_y: z.number().optional().describe("Atlas Y coordinate (default: 0)"),
      alternative: z.number().optional().describe("Alternative tile ID (default: 0)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("tilemap_set_cell", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "tilemap_fill_rect",
    "Fill a rectangular region of a TileMapLayer with tiles",
    {
      node_path: z.string().describe("Path to the TileMapLayer node"),
      x1: z.number().describe("Start X coordinate"),
      y1: z.number().describe("Start Y coordinate"),
      x2: z.number().describe("End X coordinate"),
      y2: z.number().describe("End Y coordinate"),
      source_id: z.number().optional().describe("Tile source ID (default: 0)"),
      atlas_x: z.number().optional().describe("Atlas X coordinate (default: 0)"),
      atlas_y: z.number().optional().describe("Atlas Y coordinate (default: 0)"),
      alternative: z.number().optional().describe("Alternative tile ID (default: 0)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("tilemap_fill_rect", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "tilemap_get_cell",
    "Get tile data at a specific cell in a TileMapLayer",
    {
      node_path: z.string().describe("Path to the TileMapLayer node"),
      x: z.number().describe("Cell X coordinate"),
      y: z.number().describe("Cell Y coordinate"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("tilemap_get_cell", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "tilemap_clear",
    "Clear all cells in a TileMapLayer",
    {
      node_path: z.string().describe("Path to the TileMapLayer node"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("tilemap_clear", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "tilemap_get_info",
    "Get TileMapLayer info including tile set sources and cell count",
    {
      node_path: z.string().describe("Path to the TileMapLayer node"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("tilemap_get_info", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "tilemap_get_used_cells",
    "Get a list of used (non-empty) cells in a TileMapLayer",
    {
      node_path: z.string().describe("Path to the TileMapLayer node"),
      max_count: z.number().optional().describe("Maximum cells to return (default: 500)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("tilemap_get_used_cells", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
