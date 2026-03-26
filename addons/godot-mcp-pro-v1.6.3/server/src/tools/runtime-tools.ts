import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";
import { coerceStringArray, coerceNumber } from "../utils/zod-coerce.js";

export function registerRuntimeTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "get_game_scene_tree",
    "Get the scene tree of the currently running game (requires a scene to be playing). Supports filtering by script path, node type, or name.",
    {
      max_depth: z
        .number()
        .optional()
        .describe("Maximum tree depth (-1 for unlimited, default: -1)"),
      script_filter: z
        .string()
        .optional()
        .describe(
          "Only include nodes whose script path contains this string (e.g. 'enemy' matches 'enemy.gd', 'enemy_drone.gd')"
        ),
      type_filter: z
        .string()
        .optional()
        .describe(
          "Only include nodes of this Godot class (e.g. 'CharacterBody2D', 'Area2D')"
        ),
      named_only: z
        .boolean()
        .optional()
        .describe(
          "If true, exclude nodes with auto-generated names (names starting with '@'). Default: false"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_game_scene_tree", params);
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_game_node_properties",
    "Get properties of a node in the running game (requires a scene to be playing)",
    {
      node_path: z
        .string()
        .describe(
          "Absolute node path in the running game (e.g. '/root/Main/Player')"
        ),
      properties: coerceStringArray()
        .optional()
        .describe(
          "Specific property names to read (default: all editor-visible properties)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand(
          "get_game_node_properties",
          params
        );
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "set_game_node_property",
    "Set a property on a node in the running game (requires a scene to be playing). Useful for live-tweaking values like position, speed, health, etc.",
    {
      node_path: z
        .string()
        .describe(
          "Absolute node path in the running game (e.g. '/root/Main/Player')"
        ),
      property: z
        .string()
        .describe("Property name to set (e.g. 'position', 'speed', 'health')"),
      value: z
        .union([z.string(), z.number(), z.boolean(), z.record(z.string(), z.number())])
        .describe(
          "Value to set. Accepts: strings with auto-parsing ('Vector2(100,200)', '#ff0000'), numbers, booleans, or JSON objects for vectors/colors ({\"x\":5,\"y\":3,\"z\":10} for Vector3, {\"x\":100,\"y\":200} for Vector2, {\"r\":1,\"g\":0,\"b\":0,\"a\":1} for Color)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand(
          "set_game_node_property",
          params
        );
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "execute_game_script",
    "Execute arbitrary GDScript code inside the running game process. Use _mcp_print() to output values. Has access to the live scene tree and all game nodes.",
    {
      code: z
        .string()
        .describe(
          "GDScript code to execute in the running game. Use _mcp_print(value) to capture output. Code runs inside a run() function with access to the live game scene tree."
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand(
          "execute_game_script",
          params
        );
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "capture_frames",
    "Capture multiple screenshots at regular frame intervals from the running game. Returns base64 PNG images. Use this to verify animations are playing correctly — if character poses differ across frames, the animation is working; if all frames show the same pose (e.g. T-pose), animation loading failed. Also useful for verifying movement, physics, and any time-based behavior. Prefer this over get_game_screenshot when you need to confirm something is changing over time.",
    {
      count: coerceNumber()
        .optional()
        .describe("Number of frames to capture (1-30, default: 5)"),
      frame_interval: coerceNumber()
        .optional()
        .describe(
          "Frames to wait between captures (default: 10, i.e. ~6 captures/sec at 60fps)"
        ),
      half_resolution: z
        .boolean()
        .optional()
        .describe("Halve resolution to reduce data size (default: true)"),
      node_data: z
        .object({
          node_path: z.string().describe("Path to a node to track (e.g. '/root/Main/Player')"),
          properties: coerceStringArray().describe("Property names to capture per frame (e.g. ['global_position', 'velocity'])"),
        })
        .optional()
        .describe("Optional: capture node property data alongside each frame for debugging (position, velocity, etc.)"),
    },
    async (params) => {
      try {
        const result = (await godot.sendCommand(
          "capture_frames",
          params
        )) as Record<string, unknown>;

        if (
          result &&
          typeof result === "object" &&
          "frames" in result &&
          Array.isArray(result.frames)
        ) {
          const content: Array<
            | { type: "image"; data: string; mimeType: string }
            | { type: "text"; text: string }
          > = [];

          const frameData = Array.isArray(result.frame_data) ? result.frame_data : null;

          for (let i = 0; i < result.frames.length; i++) {
            content.push({
              type: "image" as const,
              data: result.frames[i] as string,
              mimeType: "image/png",
            });
            if (frameData && frameData[i]) {
              content.push({
                type: "text" as const,
                text: `Frame ${i + 1}: ${JSON.stringify(frameData[i])}`,
              });
            }
          }
          content.push({
            type: "text" as const,
            text: `Captured ${result.count} frames (${result.width}x${result.height}${result.half_resolution ? ", half-res" : ""})`,
          });
          return { content };
        }
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "record_frames",
    "Record many screenshots to files on disk for long-running debug observation. Unlike capture_frames (which returns base64 images directly), this saves PNG files to user://mcp_recorded_frames/ and returns file paths. Use this when you need more than 30 frames or want to observe behavior over a longer period without flooding the context with image data.",
    {
      count: coerceNumber()
        .optional()
        .describe("Number of frames to capture (1-600, default: 30)"),
      frame_interval: coerceNumber()
        .optional()
        .describe(
          "Frames to wait between captures (default: 10, i.e. ~6 captures/sec at 60fps)"
        ),
      half_resolution: z
        .boolean()
        .optional()
        .describe("Halve resolution to reduce file size (default: true)"),
      node_data: z
        .object({
          node_path: z.string().describe("Path to a node to track (e.g. '/root/Main/Player')"),
          properties: coerceStringArray().describe("Property names to capture per frame (e.g. ['global_position', 'velocity'])"),
        })
        .optional()
        .describe("Optional: capture node property data alongside each frame for debugging"),
    },
    async (params) => {
      try {
        const result = (await godot.sendCommand(
          "record_frames",
          params
        )) as Record<string, unknown>;

        const content: Array<{ type: "text"; text: string }> = [];

        content.push({
          type: "text" as const,
          text: `Recorded ${result.count} frames to ${result.directory}/ (${result.width}x${result.height}${result.half_resolution ? ", half-res" : ""})`,
        });

        if (Array.isArray(result.files)) {
          content.push({
            type: "text" as const,
            text: `Files:\n${(result.files as string[]).join("\n")}`,
          });
        }

        if (Array.isArray(result.frame_data) && (result.frame_data as unknown[]).length > 0) {
          content.push({
            type: "text" as const,
            text: `Node data:\n${JSON.stringify(result.frame_data, null, 2)}`,
          });
        }

        return { content };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "monitor_properties",
    "Record property values over multiple frames from the running game. Returns a timeline of samples. Great for verifying movement (position changing), animation state (current_animation property), physics behavior (velocity), and debugging time-dependent issues.",
    {
      node_path: z
        .string()
        .describe(
          "Absolute node path in the running game (e.g. '/root/Main/Player')"
        ),
      properties: coerceStringArray()
        .describe(
          "Property names to monitor (e.g. ['position', 'velocity'])"
        ),
      frame_count: coerceNumber()
        .optional()
        .describe("Number of samples to collect (1-600, default: 60)"),
      frame_interval: coerceNumber()
        .optional()
        .describe(
          "Frames to wait between samples (default: 1, every frame)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("monitor_properties", params);
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "start_recording",
    "Start recording all input events (keyboard, mouse, actions) in the running game. Use stop_recording to get the recorded events.",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("start_recording");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "stop_recording",
    "Stop recording input events and return the recorded event timeline. Events include timestamps for replay.",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("stop_recording");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "replay_recording",
    "Replay a previously recorded input event sequence in the running game. Useful for regression testing — record a test once, replay it after code changes.",
    {
      events: z.array(z.record(z.string(), z.unknown())).describe("Array of recorded event objects (from stop_recording output)"),
      speed: z.number().optional().describe("Playback speed multiplier (default: 1.0, 2.0 = double speed)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("replay_recording", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "find_nodes_by_script",
    "Find all nodes in the running game whose script path contains a given string. Returns matching nodes with their properties.",
    {
      script: z
        .string()
        .describe(
          "Script path substring to search for (e.g. 'enemy', 'player.gd')"
        ),
      properties: coerceStringArray()
        .optional()
        .describe(
          "Specific property names to include for each match (default: all editor-visible properties)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand(
          "find_nodes_by_script",
          params
        );
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_autoload",
    "Get properties of an autoload/singleton node in the running game. Quick access to global game state like GameManager, EventBus, etc.",
    {
      name: z
        .string()
        .describe(
          "Autoload name (e.g. 'GameManager', 'EventBus', 'SaveManager')"
        ),
      properties: coerceStringArray()
        .optional()
        .describe(
          "Specific property names to read (default: all editor-visible properties)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_autoload", params);
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "find_ui_elements",
    "Find all visible UI elements (Button, Label, LineEdit, CheckBox, Slider, etc.) in the running game. Returns each element's text, type, position, and center point for clicking.",
    {
      type_filter: z
        .string()
        .optional()
        .describe(
          "Only return elements of this type (e.g. 'Button', 'Label', 'CheckBox'). Default: all types"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("find_ui_elements", params);
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "click_button_by_text",
    "Click a button in the running game by its text label. Finds the button, calculates its center, and simulates a full click (press + release). Much easier than manual coordinate-based clicking.",
    {
      text: z
        .string()
        .describe(
          "Button text to search for (e.g. 'New Game', 'Start', 'OK')"
        ),
      partial: z
        .boolean()
        .optional()
        .describe(
          "Allow partial text matching (default: true). If false, requires exact match."
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand(
          "click_button_by_text",
          params
        );
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "wait_for_node",
    "Wait until a node exists at the given path in the running game scene tree. Useful for waiting after scene transitions, node spawning, or UI state changes.",
    {
      node_path: z
        .string()
        .describe(
          "Absolute node path to wait for (e.g. '/root/Main/Player', '/root/Dungeon')"
        ),
      timeout: z
        .number()
        .optional()
        .describe("Maximum seconds to wait (default: 5.0)"),
      poll_frames: z
        .number()
        .optional()
        .describe(
          "Frames between each check (default: 5, i.e. ~12 checks/sec at 60fps)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("wait_for_node", params);
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "find_nearby_nodes",
    "Find all nodes within a radius of a position in the running game, sorted by distance. Useful for finding what's near the player (collectibles, enemies, interactables) without manually querying each node's position.",
    {
      position: z
        .union([z.string(), z.object({ x: z.number(), y: z.number(), z: z.number().optional() })])
        .describe(
          "Origin position: either a node_path string (e.g. '/root/Main/Player') to use that node's global_position, or an {x, y, z} coordinate object"
        ),
      radius: coerceNumber()
        .optional()
        .describe("Search radius in world units (default: 20.0)"),
      type_filter: z
        .string()
        .optional()
        .describe(
          "Only include nodes of this Godot class (e.g. 'Area3D', 'CharacterBody3D')"
        ),
      group_filter: z
        .string()
        .optional()
        .describe(
          "Only include nodes in this group (e.g. 'enemies', 'collectibles')"
        ),
      max_results: coerceNumber()
        .optional()
        .describe("Maximum number of results to return (default: 10)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("find_nearby_nodes", params);
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "navigate_to",
    "Calculate navigation info from the player to a target in the running 3D game. Returns the world direction, camera-relative suggested WASD keys to press, camera yaw rotation needed (as mouse relative_x pixels for simulate_mouse_move), and estimated walk duration. Use this to plan movement instead of manually calculating directions.",
    {
      target: z
        .union([z.string(), z.object({ x: z.number(), y: z.number(), z: z.number() })])
        .describe(
          "Target: either a node_path string (e.g. '/root/Main/Crystal') or an {x, y, z} coordinate object"
        ),
      player_path: z
        .string()
        .optional()
        .describe(
          "Player node path (default: '/root/Main/Player')"
        ),
      camera_path: z
        .string()
        .optional()
        .describe(
          "Camera node path (default: auto-detect active Camera3D)"
        ),
      move_speed: coerceNumber()
        .optional()
        .describe(
          "Player movement speed in units/sec for duration estimation (default: 5.0)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("navigate_to", params);
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "move_to",
    "Autopilot the player character to walk to a target position in the running 3D game. Handles camera rotation and forward movement internally at 60fps — completes in a single call with no manual simulate_key/simulate_mouse_move loops needed. The player's camera pivot is directly rotated toward the target, and W key is injected to walk. Much more reliable and efficient than navigate_to + manual input simulation.",
    {
      target: z
        .union([z.string(), z.object({ x: z.number(), y: z.number(), z: z.number() })])
        .describe(
          "Target: either a node_path string (e.g. '/root/Main/Crystal') or an {x, y, z} coordinate object"
        ),
      player_path: z
        .string()
        .optional()
        .describe(
          "Player node path (default: '/root/Main/Player')"
        ),
      camera_path: z
        .string()
        .optional()
        .describe(
          "Camera pivot node path (default: auto-detect SpringArm3D child of player, or active Camera3D parent)"
        ),
      arrival_radius: coerceNumber()
        .optional()
        .describe(
          "Stop when this close to target in world units (default: 1.5)"
        ),
      timeout: coerceNumber()
        .optional()
        .describe(
          "Maximum seconds before giving up (default: 15.0)"
        ),
      run: z
        .boolean()
        .optional()
        .describe(
          "Hold Shift for running speed (default: false)"
        ),
      look_at_target: z
        .boolean()
        .optional()
        .describe(
          "Rotate camera toward target while moving (default: true). Set false to walk forward without turning."
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("move_to", params);
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "batch_get_properties",
    "Get properties of multiple nodes at once in the running game. More efficient than calling get_game_node_properties multiple times.",
    {
      nodes: z
        .array(
          z.object({
            path: z
              .string()
              .describe("Absolute node path (e.g. '/root/Main/Player')"),
            properties: coerceStringArray()
              .optional()
              .describe(
                "Specific properties to read (default: all editor-visible)"
              ),
          })
        )
        .describe("Array of nodes to query"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand(
          "batch_get_properties",
          params
        );
        return {
          content: [
            { type: "text", text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );
}
