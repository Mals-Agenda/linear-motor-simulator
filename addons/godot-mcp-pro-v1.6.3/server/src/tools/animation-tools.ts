import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerAnimationTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "list_animations",
    "List all animations in an AnimationPlayer node",
    {
      node_path: z.string().describe("Path to the AnimationPlayer node"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("list_animations", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "create_animation",
    "Create a new animation in an AnimationPlayer",
    {
      node_path: z.string().describe("Path to the AnimationPlayer node"),
      name: z.string().describe("Name for the new animation"),
      length: z.number().optional().describe("Animation length in seconds (default: 1.0)"),
      loop_mode: z.number().optional().describe("Loop mode: 0=none, 1=linear, 2=pingpong (default: 0)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("create_animation", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "add_animation_track",
    "Add a track to an animation (value, position, rotation, scale, method, bezier)",
    {
      node_path: z.string().describe("Path to the AnimationPlayer node"),
      animation: z.string().describe("Animation name"),
      track_path: z.string().describe("Node path and property for the track (e.g. 'Sprite2D:position')"),
      track_type: z.string().optional().describe("Track type: value, position_2d, rotation_2d, scale_2d, method, bezier, blend_shape (default: value)"),
      update_mode: z.string().optional().describe("Update mode for value tracks: continuous, discrete, capture"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_animation_track", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_animation_keyframe",
    "Insert a keyframe into an animation track",
    {
      node_path: z.string().describe("Path to the AnimationPlayer node"),
      animation: z.string().describe("Animation name"),
      track_index: z.number().describe("Track index"),
      time: z.number().describe("Time position in seconds"),
      value: z.union([z.string(), z.number(), z.boolean()]).describe("Keyframe value. Strings auto-parsed for Vector2, Color, etc."),
      easing: z.number().optional().describe("Easing/transition value. 1.0=linear, <1.0=ease-in, >1.0=ease-out. Use negative for in-out variants. (default: 1.0)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_animation_keyframe", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_animation_info",
    "Get detailed info about an animation including all tracks and keyframes",
    {
      node_path: z.string().describe("Path to the AnimationPlayer node"),
      animation: z.string().describe("Animation name"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_animation_info", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "remove_animation",
    "Remove an animation from an AnimationPlayer",
    {
      node_path: z.string().describe("Path to the AnimationPlayer node"),
      name: z.string().describe("Name of the animation to remove"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("remove_animation", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
