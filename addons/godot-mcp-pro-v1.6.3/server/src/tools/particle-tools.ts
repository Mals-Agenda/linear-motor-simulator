import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerParticleTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "create_particles",
    "Add a GPUParticles2D or GPUParticles3D node with a ParticleProcessMaterial. Configure amount, lifetime, one_shot, explosiveness, and randomness.",
    {
      parent_path: z.string().describe("Path to the parent node to add particles to"),
      name: z.string().optional().describe("Name for the particles node (default: 'Particles')"),
      is_3d: z.boolean().optional().describe("Create GPUParticles3D instead of GPUParticles2D (default: false)"),
      amount: z.number().optional().describe("Number of particles (default: 16)"),
      lifetime: z.number().optional().describe("Particle lifetime in seconds (default: 1.0)"),
      one_shot: z.boolean().optional().describe("Emit only once (default: false)"),
      explosiveness: z.number().optional().describe("Explosiveness ratio 0-1 (default: 0.0)"),
      randomness: z.number().optional().describe("Randomness ratio 0-1 (default: 0.0)"),
      emitting: z.boolean().optional().describe("Start emitting immediately (default: true)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("create_particles", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_particle_material",
    "Configure ParticleProcessMaterial properties: direction, spread, velocity, gravity, scale, color, emission shape (point/sphere/box/ring), angular/orbit velocity, damping, and attractor interaction.",
    {
      node_path: z.string().describe("Path to the GPUParticles2D/3D node"),
      direction: z.object({
        x: z.number(),
        y: z.number(),
        z: z.number(),
      }).optional().describe("Emission direction vector"),
      spread: z.number().optional().describe("Spread angle in degrees (0-180)"),
      initial_velocity_min: z.number().optional().describe("Minimum initial velocity"),
      initial_velocity_max: z.number().optional().describe("Maximum initial velocity"),
      gravity: z.object({
        x: z.number(),
        y: z.number(),
        z: z.number(),
      }).optional().describe("Gravity vector"),
      scale_min: z.number().optional().describe("Minimum particle scale"),
      scale_max: z.number().optional().describe("Maximum particle scale"),
      color: z.string().optional().describe("Particle color (hex '#RRGGBB' or named color)"),
      emission_shape: z.string().optional().describe("Emission shape: point, sphere, sphere_surface, box, ring"),
      emission_sphere_radius: z.number().optional().describe("Sphere emission radius"),
      emission_box_extents: z.object({
        x: z.number(),
        y: z.number(),
        z: z.number(),
      }).optional().describe("Box emission extents"),
      emission_ring_radius: z.number().optional().describe("Ring outer radius"),
      emission_ring_inner_radius: z.number().optional().describe("Ring inner radius"),
      emission_ring_height: z.number().optional().describe("Ring height"),
      angular_velocity_min: z.number().optional().describe("Minimum angular velocity (degrees/sec)"),
      angular_velocity_max: z.number().optional().describe("Maximum angular velocity (degrees/sec)"),
      orbit_velocity_min: z.number().optional().describe("Minimum orbit velocity"),
      orbit_velocity_max: z.number().optional().describe("Maximum orbit velocity"),
      damping_min: z.number().optional().describe("Minimum damping"),
      damping_max: z.number().optional().describe("Maximum damping"),
      attractor_interaction_enabled: z.boolean().optional().describe("Enable attractor interaction"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_particle_material", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_particle_color_gradient",
    "Set a color ramp (gradient) on a particle system's material. Provide an array of color stops with offset (0-1) and color.",
    {
      node_path: z.string().describe("Path to the GPUParticles2D/3D node"),
      stops: z.array(z.object({
        offset: z.number().describe("Gradient position (0.0 to 1.0)"),
        color: z.string().describe("Color at this stop (hex '#RRGGBB' or named color)"),
      })).describe("Array of gradient color stops"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_particle_color_gradient", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "apply_particle_preset",
    "Apply a named particle preset. Available presets: explosion (burst, short life), fire (upward, orange gradient), smoke (slow upward, gray), sparks (burst, high velocity), rain (downward, blue), snow (slow downward, drift), magic (orbit, colorful), dust (ambient, subtle).",
    {
      node_path: z.string().describe("Path to the GPUParticles2D/3D node"),
      preset: z.string().describe("Preset name: explosion, fire, smoke, sparks, rain, snow, magic, dust"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("apply_particle_preset", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_particle_info",
    "Get the full configuration of a particle system: node properties, material settings, emission shape, color gradient stops.",
    {
      node_path: z.string().describe("Path to the GPUParticles2D/3D node"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_particle_info", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
