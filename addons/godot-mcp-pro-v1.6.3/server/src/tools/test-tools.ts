import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerTestTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "run_test_scenario",
    "Execute a test scenario in the running game. Optionally plays a scene, then runs a sequence of steps (input simulation, waits, assertions, screenshots). Returns pass/fail summary. Note: keep scenarios short (under 20 seconds total) to avoid timeout.",
    {
      scene_path: z
        .string()
        .optional()
        .describe(
          "Scene to play before running steps. Use 'main' for main scene, 'current' for current scene, or a res:// path. If omitted, uses already-running scene."
        ),
      steps: z
        .array(
          z.record(z.string(), z.unknown())
        )
        .describe(
          "Array of test steps. Each step has a 'type' field: " +
          "'input' (action/keycode simulation), " +
          "'wait' (seconds or node_path to wait for), " +
          "'assert' (node_path+property+expected+operator, or text for screen text), " +
          "'screenshot' (capture a frame). " +
          "Examples: " +
          "{type:'input', action:'ui_accept'}, " +
          "{type:'wait', seconds:0.5}, " +
          "{type:'wait', node_path:'/root/Main/Player'}, " +
          "{type:'assert', node_path:'/root/Main/Player', property:'health', expected:100, operator:'eq'}, " +
          "{type:'assert', text:'Game Over'}, " +
          "{type:'screenshot'}"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("run_test_scenario", params);
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
    "assert_node_state",
    "Assert a node's property value in the running game. Compares the actual property value against an expected value using the specified operator. Returns pass/fail with actual value for debugging.",
    {
      node_path: z
        .string()
        .describe(
          "Absolute node path in the running game (e.g. '/root/Main/Player')"
        ),
      property: z
        .string()
        .describe(
          "Property name to check (e.g. 'health', 'position:x', 'visible')"
        ),
      expected: z
        .union([z.string(), z.number(), z.boolean()])
        .describe("Expected value to compare against"),
      operator: z
        .enum(["eq", "neq", "gt", "lt", "gte", "lte", "contains", "type_is"])
        .optional()
        .describe(
          "Comparison operator (default: 'eq'). " +
          "eq/neq: equality, gt/lt/gte/lte: numeric comparison, " +
          "contains: string/array contains, type_is: check Godot type name"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("assert_node_state", params);
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
    "assert_screen_text",
    "Assert that specific text is visible on screen in the running game. Searches all visible UI elements (Button, Label, LineEdit, etc.) for matching text. Useful for verifying UI state, dialog content, or game messages.",
    {
      text: z
        .string()
        .describe("Text to search for on screen (e.g. 'Game Over', 'Score:', 'New Game')"),
      partial: z
        .boolean()
        .optional()
        .describe(
          "Allow partial text matching (default: true). If false, requires exact match."
        ),
      case_sensitive: z
        .boolean()
        .optional()
        .describe("Case-sensitive comparison (default: true)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("assert_screen_text", params);
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
    "run_stress_test",
    "Run rapid random input events for a specified duration and check if the game crashes. Sends random UI actions (up/down/left/right/accept/cancel) plus any custom actions. Returns whether the game survived, event count, and new errors.",
    {
      duration: z
        .number()
        .optional()
        .describe(
          "Duration in seconds to run the stress test (1-60, default: 5)"
        ),
      actions: z
        .array(z.string())
        .optional()
        .describe(
          "Additional input action names to include in random input pool (e.g. ['jump', 'attack', 'dash'])"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("run_stress_test", params);
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
    "get_test_report",
    "Collect and format results from all assertions run so far (via assert_node_state, assert_screen_text, and run_test_scenario) into a summary test report. Shows pass/fail counts, pass rate, and detailed results.",
    {
      clear: z
        .boolean()
        .optional()
        .describe(
          "Clear accumulated results after generating report (default: true)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_test_report", params);
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
