import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";
import { coerceNumber } from "../utils/zod-coerce.js";

export function registerInputTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "simulate_key",
    "Simulate a keyboard key press or release in the running game. Use `duration` to hold a key for a set time (auto-releases after). Without duration: keys are NOT auto-released — you must explicitly call with pressed=false to release them.",
    {
      keycode: z.string().describe("Key constant (e.g. 'KEY_SPACE', 'KEY_W', 'KEY_ESCAPE')"),
      pressed: z.boolean().optional().describe("true for press, false for release (default: true)"),
      duration: coerceNumber().optional().describe("Hold duration in seconds (e.g. 1.5). Key is pressed, held for this duration, then auto-released. Cannot be used with pressed=false."),
      shift: z.boolean().optional().describe("Shift modifier (default: false)"),
      ctrl: z.boolean().optional().describe("Ctrl modifier (default: false)"),
      alt: z.boolean().optional().describe("Alt modifier (default: false)"),
    },
    async (params) => {
      try {
        if (params.duration !== undefined && params.duration > 0) {
          const { duration, ...keyParams } = params;
          // Press
          await godot.sendCommand("simulate_key", { ...keyParams, pressed: true });
          // Hold
          await new Promise(resolve => setTimeout(resolve, duration * 1000));
          // Release
          await godot.sendCommand("simulate_key", { ...keyParams, pressed: false });
          return { content: [{ type: "text", text: JSON.stringify({
            event: { keycode: params.keycode, duration, shift: params.shift, ctrl: params.ctrl, alt: params.alt, auto_released: true },
            sent: true
          }, null, 2) }] };
        }
        const result = await godot.sendCommand("simulate_key", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "simulate_mouse_click",
    "Simulate a mouse button click at a position in the running game. By default sends both press and release (auto_release) so UI buttons work correctly.",
    {
      x: z.number().optional().describe("X position in viewport (default: 0)"),
      y: z.number().optional().describe("Y position in viewport (default: 0)"),
      button: z.number().optional().describe("Mouse button index: 1=left, 2=right, 3=middle (default: 1)"),
      pressed: z.boolean().optional().describe("true for press, false for release (default: true)"),
      double_click: z.boolean().optional().describe("Double click (default: false)"),
      auto_release: z.boolean().optional().describe("Auto-send release after press so buttons fire (default: true). Set false for drag operations."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("simulate_mouse_click", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "simulate_mouse_move",
    "Simulate mouse movement in the running game. Use x/y for absolute viewport positioning (UI interaction), or relative_x/relative_y for relative motion (camera rotation in 3D games, FPS-style look). For 3D camera rotation: relative_x rotates yaw (negative = look left, positive = look right), relative_y rotates pitch (negative = look up, positive = look down). Typical values: 200-400px for a ~90° turn. Use navigate_to tool to calculate exact relative_x needed to face a target.",
    {
      x: z.number().optional().describe("Absolute X position in viewport (for UI interaction)"),
      y: z.number().optional().describe("Absolute Y position in viewport (for UI interaction)"),
      relative_x: z.number().optional().describe("Relative X movement in pixels. For 3D camera: negative = look left, positive = look right. ~400px ≈ 180° turn"),
      relative_y: z.number().optional().describe("Relative Y movement in pixels. For 3D camera: negative = look up, positive = look down"),
      button_mask: z.number().optional().describe("Mouse button mask to simulate drag. 1=left button held, 2=right button held, 4=middle button held. Required for drag operations like camera pan. (default: 0)"),
      unhandled: z.boolean().optional().describe("Force event to bypass GUI layer and go directly to _unhandled_input(). Auto-enabled when button_mask > 0. Use for camera pan/drag when UI overlays consume mouse events. (default: false)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("simulate_mouse_move", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "simulate_action",
    "Simulate a Godot Input Action (e.g. 'jump', 'move_left') in the running game",
    {
      action: z.string().describe("Action name as defined in Input Map (e.g. 'jump', 'move_left')"),
      pressed: z.boolean().optional().describe("true for press, false for release (default: true)"),
      strength: z.number().optional().describe("Action strength 0.0-1.0 (default: 1.0)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("simulate_action", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "simulate_sequence",
    "Simulate a sequence of input events with optional frame delays between them. Useful for complex input patterns like press W → wait 30 frames → press Space → wait → release all. After the sequence, use capture_frames to verify the visual result.",
    {
      events: z.array(z.object({
        type: z.string().describe("Event type: 'key', 'mouse_button', 'mouse_motion', or 'action'"),
        keycode: z.string().optional().describe("For 'key': key constant (e.g. 'KEY_SPACE')"),
        action: z.string().optional().describe("For 'action': action name"),
        button: z.number().optional().describe("For 'mouse_button': button index"),
        pressed: z.boolean().optional().describe("Press state (default: true)"),
        x: z.number().optional().describe("X position for mouse events"),
        y: z.number().optional().describe("Y position for mouse events"),
        relative_x: z.number().optional().describe("Relative X for mouse_motion"),
        relative_y: z.number().optional().describe("Relative Y for mouse_motion"),
        button_mask: z.number().optional().describe("Mouse button mask for mouse_motion drag: 1=left, 2=right, 4=middle"),
        unhandled: z.boolean().optional().describe("Bypass GUI, send directly to _unhandled_input. Auto-enabled for mouse_motion with button_mask > 0"),
        shift: z.boolean().optional(),
        ctrl: z.boolean().optional(),
        alt: z.boolean().optional(),
        strength: z.number().optional(),
        double_click: z.boolean().optional(),
      })).describe("Array of input events to send"),
      frame_delay: z.number().optional().describe("Frames to wait between events (default: 1, 0 = all in one frame)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("simulate_sequence", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
