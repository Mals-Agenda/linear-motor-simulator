import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerNavigationTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "setup_navigation_region",
    "Add a NavigationRegion2D/3D child to a node with auto-created NavigationPolygon or NavigationMesh. Auto-detects 2D/3D from parent context.",
    {
      node_path: z.string().describe("Path to the parent node to add the region to"),
      mode: z.string().optional().describe("Force '2d' or '3d' mode, or 'auto' to detect from parent (default: auto)"),
      name: z.string().optional().describe("Name for the NavigationRegion node"),
      navigation_layers: z.number().optional().describe("Navigation layers bitmask"),
      agent_radius: z.number().optional().describe("Agent radius for mesh generation (3D default: 0.5, 2D: from NavigationPolygon)"),
      agent_height: z.number().optional().describe("Agent height (3D only, default: 1.5)"),
      agent_max_climb: z.number().optional().describe("Max climb height (3D only, default: 0.25)"),
      agent_max_slope: z.number().optional().describe("Max slope angle in degrees (3D only, default: 45.0)"),
      cell_size: z.number().optional().describe("Cell size for navigation mesh (default: 0.25 for 3D)"),
      cell_height: z.number().optional().describe("Cell height (3D only, default: 0.25)"),
      source_geometry_mode: z.string().optional().describe("2D only: root_node, groups_with_children, or groups_explicit"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("setup_navigation_region", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "bake_navigation_mesh",
    "Bake navigation mesh for a NavigationRegion3D, or set outline vertices and generate polygons for a NavigationRegion2D.",
    {
      node_path: z.string().describe("Path to the NavigationRegion2D or NavigationRegion3D node"),
      outline: z.array(z.union([
        z.array(z.number()).describe("[x, y] coordinate pair"),
        z.object({ x: z.number(), y: z.number() }),
      ])).optional().describe("2D only: Array of outline vertices as [x,y] pairs or {x,y} objects. At least 3 vertices required."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("bake_navigation_mesh", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "setup_navigation_agent",
    "Add a NavigationAgent2D/3D child to a node and configure pathfinding and avoidance properties. Auto-detects 2D/3D from parent context.",
    {
      node_path: z.string().describe("Path to the parent node to add the agent to"),
      mode: z.string().optional().describe("Force '2d' or '3d' mode, or 'auto' to detect from parent (default: auto)"),
      name: z.string().optional().describe("Name for the NavigationAgent node"),
      path_desired_distance: z.number().optional().describe("Distance threshold to advance to next path point"),
      target_desired_distance: z.number().optional().describe("Distance threshold to consider target reached"),
      radius: z.number().optional().describe("Agent radius for avoidance"),
      neighbor_distance: z.number().optional().describe("Max distance to consider other agents as neighbors"),
      max_neighbors: z.number().optional().describe("Max number of neighbors for avoidance"),
      max_speed: z.number().optional().describe("Maximum movement speed for avoidance"),
      avoidance_enabled: z.boolean().optional().describe("Enable avoidance behavior"),
      navigation_layers: z.number().optional().describe("Navigation layers bitmask for pathfinding queries"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("setup_navigation_agent", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_navigation_layers",
    "Set navigation layers for a NavigationRegion or NavigationAgent. Supports bitmask value, layer bit numbers, or named layers from ProjectSettings.",
    {
      node_path: z.string().describe("Path to a NavigationRegion2D/3D or NavigationAgent2D/3D node"),
      layers: z.number().optional().describe("Navigation layers as a bitmask value (e.g. 5 = layers 1 and 3)"),
      layer_bits: z.array(z.number()).optional().describe("Array of 1-based layer numbers to enable (e.g. [1, 3] = bitmask 5)"),
      layer_names: z.array(z.string()).optional().describe("Array of named layer names from ProjectSettings (layer_names/2d_navigation/layer_N or 3d)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_navigation_layers", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_navigation_info",
    "Get navigation setup info for a node and its subtree: all NavigationRegions, NavigationAgents, their layers, and mesh/polygon data.",
    {
      node_path: z.string().describe("Path to the root node to inspect"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_navigation_info", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
