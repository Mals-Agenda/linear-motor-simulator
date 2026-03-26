import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerAnimationTreeTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "create_animation_tree",
    "Create an AnimationTree node with an AnimationNodeStateMachine as root, optionally linked to an AnimationPlayer",
    {
      node_path: z.string().describe("Path to the parent node where the AnimationTree will be added"),
      anim_player: z.string().optional().describe("Relative path from the AnimationTree to the AnimationPlayer (e.g. '../AnimationPlayer')"),
      name: z.string().optional().describe("Name for the AnimationTree node (default: 'AnimationTree')"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("create_animation_tree", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_animation_tree_structure",
    "Read the full structure of an AnimationTree including all states, transitions, and blend tree nodes",
    {
      node_path: z.string().describe("Path to the AnimationTree node"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_animation_tree_structure", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "add_state_machine_state",
    "Add a state to an AnimationNodeStateMachine (animation clip, blend tree, or nested state machine)",
    {
      node_path: z.string().describe("Path to the AnimationTree node"),
      state_name: z.string().describe("Name for the new state"),
      state_type: z.enum(["animation", "blend_tree", "state_machine"]).optional().describe("Type of state: 'animation' (default), 'blend_tree', or 'state_machine'"),
      animation: z.string().optional().describe("Animation name to play (only for state_type='animation')"),
      state_machine_path: z.string().optional().describe("Slash-separated path to a nested state machine (e.g. 'Run/SubState'). Empty or omit for root."),
      position_x: z.number().optional().describe("X position in the graph editor (default: 0)"),
      position_y: z.number().optional().describe("Y position in the graph editor (default: 0)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_state_machine_state", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "remove_state_machine_state",
    "Remove a state from an AnimationNodeStateMachine (also removes connected transitions)",
    {
      node_path: z.string().describe("Path to the AnimationTree node"),
      state_name: z.string().describe("Name of the state to remove"),
      state_machine_path: z.string().optional().describe("Slash-separated path to a nested state machine. Empty or omit for root."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("remove_state_machine_state", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "add_state_machine_transition",
    "Add a transition between two states in an AnimationNodeStateMachine with configurable switch mode, advance mode, and expression conditions",
    {
      node_path: z.string().describe("Path to the AnimationTree node"),
      from_state: z.string().describe("Source state name (use 'Start' for the entry point)"),
      to_state: z.string().describe("Destination state name (use 'End' for the exit point)"),
      switch_mode: z.enum(["at_end", "immediate", "sync"]).optional().describe("When to switch: 'at_end' (wait for animation), 'immediate' (default), 'sync'"),
      advance_mode: z.enum(["disabled", "enabled", "auto"]).optional().describe("How to advance: 'disabled', 'enabled' (default, uses travel), 'auto' (automatic)"),
      advance_expression: z.string().optional().describe("GDScript expression that triggers this transition (e.g. 'is_running')"),
      xfade_time: z.number().optional().describe("Cross-fade time in seconds"),
      state_machine_path: z.string().optional().describe("Slash-separated path to a nested state machine. Empty or omit for root."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_state_machine_transition", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "remove_state_machine_transition",
    "Remove a transition between two states in an AnimationNodeStateMachine",
    {
      node_path: z.string().describe("Path to the AnimationTree node"),
      from_state: z.string().describe("Source state name"),
      to_state: z.string().describe("Destination state name"),
      state_machine_path: z.string().optional().describe("Slash-separated path to a nested state machine. Empty or omit for root."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("remove_state_machine_transition", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_blend_tree_node",
    "Add or replace a node inside an AnimationNodeBlendTree state (Add2, Blend2, TimeScale, Animation, etc.) with optional connection",
    {
      node_path: z.string().describe("Path to the AnimationTree node"),
      blend_tree_state: z.string().describe("Name of the BlendTree state in the state machine"),
      bt_node_name: z.string().describe("Name for the node inside the BlendTree"),
      bt_node_type: z.enum(["Animation", "Add2", "Blend2", "Add3", "Blend3", "TimeScale", "TimeSeek", "Transition", "OneShot", "Sub2"]).describe("Type of BlendTree node to create"),
      animation: z.string().optional().describe("Animation name (only for bt_node_type='Animation')"),
      connect_to: z.string().optional().describe("Name of another BlendTree node to connect this node's output to"),
      connect_port: z.number().optional().describe("Input port index on the target node (default: 0)"),
      state_machine_path: z.string().optional().describe("Slash-separated path to a nested state machine. Empty or omit for root."),
      position_x: z.number().optional().describe("X position in the graph editor (default: 0)"),
      position_y: z.number().optional().describe("Y position in the graph editor (default: 0)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_blend_tree_node", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_tree_parameter",
    "Set an AnimationTree parameter value (conditions, blend amounts, time scale, etc.)",
    {
      node_path: z.string().describe("Path to the AnimationTree node"),
      parameter: z.string().describe("Parameter path (e.g. 'conditions/is_running', 'Blend2/blend_amount'). 'parameters/' prefix is auto-added if missing."),
      value: z.union([z.string(), z.number(), z.boolean()]).describe("Parameter value. Strings are auto-parsed for Vector2, Color, etc."),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_tree_parameter", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
