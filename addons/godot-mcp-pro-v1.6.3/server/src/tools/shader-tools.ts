import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerShaderTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "create_shader",
    "Create a new shader file with a template or custom content",
    {
      path: z.string().describe("Path for the shader file (e.g. 'res://shaders/dissolve.gdshader')"),
      shader_type: z.string().optional().describe("Shader type: spatial, canvas_item, particles, sky (default: spatial)"),
      content: z.string().optional().describe("Full shader code. If empty, generates a template."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("create_shader", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "read_shader",
    "Read the content of a shader file",
    {
      path: z.string().describe("Path to the shader file"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("read_shader", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "edit_shader",
    "Edit a shader file using full replacement or search-and-replace",
    {
      path: z.string().describe("Path to the shader file"),
      content: z.string().optional().describe("Full replacement content"),
      replacements: z.array(z.object({
        search: z.string().describe("Text to find"),
        replace: z.string().describe("Text to replace with"),
      })).optional().describe("Array of search-and-replace operations"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("edit_shader", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "assign_shader_material",
    "Create a ShaderMaterial from a shader file and assign it to a node",
    {
      node_path: z.string().describe("Path to the target node (CanvasItem or MeshInstance3D)"),
      shader_path: z.string().describe("Path to the shader file"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("assign_shader_material", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_shader_param",
    "Set a shader parameter on a node's ShaderMaterial",
    {
      node_path: z.string().describe("Path to the node with a ShaderMaterial"),
      param: z.string().describe("Shader parameter name"),
      value: z.union([z.string(), z.number(), z.boolean()]).describe("Parameter value. Strings auto-parsed for Vector2, Color, etc."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_shader_param", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_shader_params",
    "Get all shader parameters and their current values from a node's ShaderMaterial",
    {
      node_path: z.string().describe("Path to the node with a ShaderMaterial"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_shader_params", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
