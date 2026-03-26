import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerPhysicsTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "setup_collision",
    "Add a CollisionShape2D/3D child to a physics body or area node with a specified shape. Auto-detects 2D/3D from the parent node type.",
    {
      node_path: z.string().describe("Path to the parent physics body or area node (e.g. CharacterBody2D, StaticBody3D, Area2D)"),
      shape: z.string().describe("Shape type: 'rectangle'/'rect', 'circle', 'capsule', 'segment' (2D only), 'cylinder' (3D only), 'custom'/'convex'. For 3D: 'box'/'sphere' also work."),
      width: z.number().optional().describe("Width for rectangle/box shape (default: 32 for 2D, 1 for 3D)"),
      height: z.number().optional().describe("Height for rectangle/box/capsule/cylinder shape"),
      depth: z.number().optional().describe("Depth for 3D box shape (default: 1)"),
      radius: z.number().optional().describe("Radius for circle/sphere/capsule/cylinder shape"),
      ax: z.number().optional().describe("Segment start X (2D segment only)"),
      ay: z.number().optional().describe("Segment start Y (2D segment only)"),
      bx: z.number().optional().describe("Segment end X (2D segment only)"),
      by: z.number().optional().describe("Segment end Y (2D segment only)"),
      points: z.array(z.array(z.number())).optional().describe("Convex polygon points as [[x,y],...] for 2D or [[x,y,z],...] for 3D"),
      disabled: z.boolean().optional().describe("Create the collision shape disabled (default: false)"),
      one_way_collision: z.boolean().optional().describe("Enable one-way collision (2D only, default: false)"),
      dimension: z.string().optional().describe("Force '2d' or '3d' if auto-detection fails"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("setup_collision", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_physics_layers",
    "Set collision layer and/or mask on a physics body or area node. Supports bitmask integers or arrays of layer numbers.",
    {
      node_path: z.string().describe("Path to the node with collision layers"),
      collision_layer: z.union([z.number(), z.array(z.number())]).optional().describe("Collision layer: bitmask integer or array of layer numbers [1,3,5]"),
      collision_mask: z.union([z.number(), z.array(z.number())]).optional().describe("Collision mask: bitmask integer or array of layer numbers [1,2,4]"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_physics_layers", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_physics_layers",
    "Get the current collision layer and mask for a node, including named layer info from ProjectSettings.",
    {
      node_path: z.string().describe("Path to the node with collision layers"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_physics_layers", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "add_raycast",
    "Add a RayCast2D/3D child node for collision detection. Auto-detects 2D/3D from the parent node type.",
    {
      node_path: z.string().describe("Path to the parent node"),
      name: z.string().optional().describe("Name for the raycast node (default: 'RayCast')"),
      target_x: z.number().optional().describe("Target position X (default: 0)"),
      target_y: z.number().optional().describe("Target position Y (default: 50 for 2D, -1 for 3D)"),
      target_z: z.number().optional().describe("Target position Z (3D only, default: 0)"),
      collision_mask: z.number().optional().describe("Collision mask bitmask (default: 1)"),
      enabled: z.boolean().optional().describe("Enable the raycast (default: true)"),
      collide_with_areas: z.boolean().optional().describe("Collide with Area nodes (default: false)"),
      collide_with_bodies: z.boolean().optional().describe("Collide with physics bodies (default: true)"),
      hit_from_inside: z.boolean().optional().describe("Detect hits from inside shapes (default: false)"),
      dimension: z.string().optional().describe("Force '2d' or '3d' if auto-detection fails"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_raycast", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "setup_physics_body",
    "Configure physics body properties. For CharacterBody2D/3D: floor settings, motion mode, etc. For RigidBody2D/3D: mass, gravity, damping, etc.",
    {
      node_path: z.string().describe("Path to the physics body node"),
      // CharacterBody properties
      floor_stop_on_slope: z.boolean().optional().describe("CharacterBody: stop on slopes when not moving"),
      floor_max_angle: z.number().optional().describe("CharacterBody: maximum floor angle in radians (default ~0.785 = 45 degrees)"),
      floor_snap_length: z.number().optional().describe("CharacterBody: floor snap distance for sticking to the ground"),
      wall_min_slide_angle: z.number().optional().describe("CharacterBody: minimum angle for wall sliding in radians"),
      motion_mode: z.string().optional().describe("CharacterBody: 'grounded' or 'floating'"),
      max_slides: z.number().optional().describe("CharacterBody: maximum slide iterations (default: 6)"),
      slide_on_ceiling: z.boolean().optional().describe("CharacterBody: allow sliding on ceiling"),
      // RigidBody properties
      mass: z.number().optional().describe("RigidBody: mass in kg (default: 1)"),
      gravity_scale: z.number().optional().describe("RigidBody: gravity multiplier (default: 1, 0 = no gravity)"),
      linear_damp: z.number().optional().describe("RigidBody: linear velocity damping"),
      angular_damp: z.number().optional().describe("RigidBody: angular velocity damping"),
      freeze: z.boolean().optional().describe("RigidBody: freeze the body (stop physics simulation)"),
      freeze_mode: z.string().optional().describe("RigidBody: 'static' or 'kinematic' freeze behavior"),
      continuous_cd: z.union([z.string(), z.boolean()]).optional().describe("RigidBody: continuous collision detection. 2D: 'disabled'/'cast_ray'/'cast_shape'. 3D: true/false"),
      contact_monitor: z.boolean().optional().describe("RigidBody: enable contact monitoring for body_entered/body_exited signals"),
      max_contacts_reported: z.number().optional().describe("RigidBody: max contacts to report (requires contact_monitor)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("setup_physics_body", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_collision_info",
    "Get detailed collision information for a node: all collision shapes, layers/masks, raycasts, and physics body settings. Scans children by default.",
    {
      node_path: z.string().describe("Path to the node to inspect"),
      include_children: z.boolean().optional().describe("Include children in the scan (default: true)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_collision_info", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
