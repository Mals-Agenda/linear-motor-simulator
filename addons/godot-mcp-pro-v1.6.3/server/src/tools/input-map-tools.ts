import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerInputMapTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "get_input_actions",
    "Get all input actions defined in the project's Input Map with their key/button bindings",
    {
      filter: z.string().optional().describe("Filter action names containing this substring"),
      include_builtin: z.boolean().optional().describe("Include built-in ui_* actions (default: false)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_input_actions", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_input_action",
    "Create or update an input action with key/mouse/joypad bindings. Saves to project.godot and updates the runtime InputMap.",
    {
      action: z.string().describe("Action name (e.g. 'move_left', 'jump', 'attack')"),
      events: z.array(z.object({
        type: z.enum(["key", "mouse_button", "joypad_button", "joypad_motion"]).describe("Event type"),
        keycode: z.string().optional().describe("Key name for 'key' type (e.g. 'W', 'Space', 'Escape', 'Shift')"),
        physical_keycode: z.string().optional().describe("Physical key name for 'key' type"),
        ctrl: z.boolean().optional().describe("Ctrl modifier for 'key' type"),
        shift: z.boolean().optional().describe("Shift modifier for 'key' type"),
        alt: z.boolean().optional().describe("Alt modifier for 'key' type"),
        meta: z.boolean().optional().describe("Meta/Cmd modifier for 'key' type"),
        button_index: z.number().optional().describe("Button index for mouse/joypad button types"),
        axis: z.number().optional().describe("Axis index for joypad_motion type"),
        axis_value: z.number().optional().describe("Axis value (-1.0 or 1.0) for joypad_motion type"),
      })).describe("Array of input event bindings"),
      deadzone: z.number().optional().describe("Deadzone for analog inputs (default: 0.5)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_input_action", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
