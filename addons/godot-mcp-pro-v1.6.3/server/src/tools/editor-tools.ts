import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerEditorTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "get_editor_errors",
    "Get recent errors and stack traces from the Godot editor log",
    {
      max_lines: z.number().optional().describe("Maximum log lines to scan for errors (default: 50)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_editor_errors", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_output_log",
    "Read the full Godot editor Output panel content. Unlike get_editor_errors which filters for errors only, this returns all output including print() statements and warnings.",
    {
      max_lines: z.number().optional().describe("Maximum number of lines to return from the end (default: 100)"),
      filter: z.string().optional().describe("Filter lines containing this substring (case-sensitive)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_output_log", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_editor_screenshot",
    "Capture a screenshot of the Godot editor's 2D/3D viewport",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("get_editor_screenshot") as Record<string, unknown>;
        if (result && typeof result === "object" && "image_base64" in result) {
          return {
            content: [
              {
                type: "image" as const,
                data: result.image_base64 as string,
                mimeType: "image/png",
              },
              {
                type: "text" as const,
                text: `Screenshot captured: ${result.width}x${result.height}`,
              },
            ],
          };
        }
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_game_screenshot",
    "Capture a single screenshot of the running game (requires a scene to be playing). Good for checking static visual state (UI layout, scene composition, colors). For verifying animations or movement, use capture_frames instead — a single screenshot cannot confirm whether an animation is playing.",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("get_game_screenshot") as Record<string, unknown>;
        if (result && typeof result === "object" && "image_base64" in result) {
          return {
            content: [
              {
                type: "image" as const,
                data: result.image_base64 as string,
                mimeType: "image/png",
              },
              {
                type: "text" as const,
                text: `Game screenshot: ${result.width}x${result.height}${result.note ? ` (${result.note})` : ""}`,
              },
            ],
          };
        }
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "execute_editor_script",
    "Execute arbitrary GDScript code inside the Godot editor. Use _mcp_print() to output values.",
    {
      code: z.string().describe(
        "GDScript code to execute. Use _mcp_print(value) to capture output. " +
        "The code runs inside a run() function with access to the full editor API."
      ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("execute_editor_script", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "clear_output",
    "Clear the Godot editor output panel",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("clear_output");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_signals",
    "Get all signals of a node, including current connections",
    {
      node_path: z.string().describe("Path to the node to inspect"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_signals", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "reload_plugin",
    "Reload the Godot MCP Pro plugin (disable/re-enable). Connection will briefly drop and auto-reconnect. NOTE: This does NOT reload GDScript preload() caches. If you changed GDScript command files, use execute_editor_script with 'EditorInterface.restart_editor(true)' instead for a full editor restart.",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("reload_plugin");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "reload_project",
    "Rescan the Godot project filesystem and reload changed scripts (no reconnection needed)",
    {},
    async () => {
      try {
        const result = await godot.sendCommand("reload_project");
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "compare_screenshots",
    "Compare two screenshots pixel-by-pixel and return a diff analysis. Returns changed pixel count, diff percentage, and a highlighted diff image. Useful for visual regression testing. Accepts file paths (res://, user://) or base64 PNG strings.",
    {
      image_a: z.string().describe("First image: file path (e.g. 'user://screenshot_a.png') or base64 PNG string"),
      image_b: z.string().describe("Second image: file path (e.g. 'user://screenshot_b.png') or base64 PNG string"),
      threshold: z.number().optional().describe("Color difference threshold (0-255, default: 10). Pixels with max channel difference below this are considered identical."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("compare_screenshots", params) as Record<string, unknown>;

        const content: Array<{type: "text"; text: string} | {type: "image"; data: string; mimeType: string}> = [];

        // Add summary text
        content.push({
          type: "text" as const,
          text: JSON.stringify({
            identical: result.identical,
            changed_pixels: result.changed_pixels,
            total_pixels: result.total_pixels,
            diff_percentage: result.diff_percentage,
            threshold: result.threshold,
            size: `${result.width}x${result.height}`,
          }, null, 2),
        });

        // Add diff image if there are differences
        if (result.diff_image_base64 && !result.identical) {
          content.push({
            type: "image" as const,
            data: result.diff_image_base64 as string,
            mimeType: "image/png",
          });
        }

        return { content };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
