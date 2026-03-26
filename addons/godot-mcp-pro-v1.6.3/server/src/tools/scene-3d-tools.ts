import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerScene3DTools(
  server: McpServer,
  godot: GodotConnection
): void {
  // ─── 1. add_mesh_instance ──────────────────────────────────────────────

  server.tool(
    "add_mesh_instance",
    "Add a MeshInstance3D node with a primitive mesh (Box, Sphere, Cylinder, Capsule, Plane, Prism, Torus, Quad) or load a 3D model file (.glb/.gltf/.obj). Set position, rotation, scale, and mesh-specific properties.",
    {
      mesh_type: z
        .string()
        .optional()
        .describe(
          "Primitive mesh type: BoxMesh, SphereMesh, CylinderMesh, CapsuleMesh, PlaneMesh, PrismMesh, TorusMesh, QuadMesh"
        ),
      mesh_file: z
        .string()
        .optional()
        .describe(
          "Path to a 3D model file (res://path/to/model.glb, .gltf, .obj). Use instead of mesh_type for imported models"
        ),
      parent_path: z
        .string()
        .optional()
        .describe("Parent node path (default: root '.')"),
      name: z.string().optional().describe("Node name (default: MeshInstance3D)"),
      position: z
        .any()
        .optional()
        .describe(
          "Position as Vector3 string 'Vector3(x,y,z)', object {x,y,z}, or array [x,y,z]"
        ),
      rotation: z
        .any()
        .optional()
        .describe(
          "Rotation in degrees as Vector3 string, object {x,y,z}, or array [x,y,z]"
        ),
      scale: z
        .any()
        .optional()
        .describe("Scale as Vector3 string, object {x,y,z}, or array [x,y,z]"),
      mesh_properties: z
        .record(z.string(), z.any())
        .optional()
        .describe(
          "Properties to set on the mesh resource (e.g. {\"size\": \"Vector3(2,1,2)\"} for BoxMesh)"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_mesh_instance", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  // ─── 2. setup_lighting ─────────────────────────────────────────────────

  server.tool(
    "setup_lighting",
    "Add a light node (DirectionalLight3D, OmniLight3D, SpotLight3D) to the scene. Supports preset configurations: 'sun' (directional with shadows), 'indoor' (warm omni), 'dramatic' (focused spot with shadows).",
    {
      light_type: z
        .string()
        .optional()
        .describe(
          "Light type: DirectionalLight3D, OmniLight3D, SpotLight3D. Not needed if preset is specified"
        ),
      preset: z
        .string()
        .optional()
        .describe(
          "Preset configuration: 'sun' (directional, shadows, -45deg), 'indoor' (warm omni, range 8), 'dramatic' (spot, high energy, shadows)"
        ),
      parent_path: z
        .string()
        .optional()
        .describe("Parent node path (default: root '.')"),
      name: z.string().optional().describe("Node name"),
      color: z
        .any()
        .optional()
        .describe("Light color as Color string or hex (default: white)"),
      energy: z
        .number()
        .optional()
        .describe("Light energy/intensity (default: 1.0)"),
      shadows: z
        .boolean()
        .optional()
        .describe("Enable shadow casting (default: false, true for sun/dramatic presets)"),
      range: z
        .number()
        .optional()
        .describe("Range for OmniLight3D/SpotLight3D (default: 5.0)"),
      attenuation: z
        .number()
        .optional()
        .describe("Attenuation for OmniLight3D/SpotLight3D (default: 1.0)"),
      spot_angle: z
        .number()
        .optional()
        .describe("Spot angle in degrees for SpotLight3D (default: 45.0)"),
      spot_angle_attenuation: z
        .number()
        .optional()
        .describe("Spot angle attenuation for SpotLight3D (default: 1.0)"),
      position: z
        .any()
        .optional()
        .describe("Position as Vector3 string, object {x,y,z}, or array [x,y,z]"),
      rotation: z
        .any()
        .optional()
        .describe("Rotation in degrees as Vector3 string, object {x,y,z}, or array [x,y,z]"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("setup_lighting", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  // ─── 3. set_material_3d ────────────────────────────────────────────────

  server.tool(
    "set_material_3d",
    "Create and apply a StandardMaterial3D to a MeshInstance3D. Configure PBR properties: albedo color/texture, metallic, roughness, emission, transparency, normal maps.",
    {
      node_path: z
        .string()
        .describe("Path to the MeshInstance3D node"),
      surface_index: z
        .number()
        .optional()
        .describe("Surface index to apply material to (default: 0)"),
      albedo_color: z
        .any()
        .optional()
        .describe(
          "Albedo color as Color string 'Color(r,g,b,a)', hex '#ff0000', or object {r,g,b,a}"
        ),
      albedo_texture: z
        .string()
        .optional()
        .describe("Path to albedo texture (res://path/to/texture.png)"),
      metallic: z
        .number()
        .optional()
        .describe("Metallic value 0.0-1.0 (default: 0.0)"),
      roughness: z
        .number()
        .optional()
        .describe("Roughness value 0.0-1.0 (default: 1.0)"),
      metallic_texture: z
        .string()
        .optional()
        .describe("Path to metallic texture"),
      roughness_texture: z
        .string()
        .optional()
        .describe("Path to roughness texture"),
      normal_texture: z
        .string()
        .optional()
        .describe("Path to normal map texture (auto-enables normal mapping)"),
      emission: z
        .any()
        .optional()
        .describe(
          "Emission color (auto-enables emission). Color string or hex"
        ),
      emission_color: z
        .any()
        .optional()
        .describe("Alias for emission"),
      emission_energy: z
        .number()
        .optional()
        .describe("Emission energy multiplier (default: 1.0)"),
      emission_texture: z
        .string()
        .optional()
        .describe("Path to emission texture"),
      transparency: z
        .string()
        .optional()
        .describe(
          "Transparency mode: DISABLED, ALPHA, ALPHA_SCISSOR, ALPHA_HASH, ALPHA_DEPTH_PRE_PASS"
        ),
      cull_mode: z
        .string()
        .optional()
        .describe("Cull mode: BACK, FRONT, DISABLED"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_material_3d", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  // ─── 4. setup_environment ──────────────────────────────────────────────

  server.tool(
    "setup_environment",
    "Add or configure a WorldEnvironment node with sky, ambient light, tonemap, fog, glow, SSAO, SSR, and SDFGI settings.",
    {
      parent_path: z
        .string()
        .optional()
        .describe("Parent node path (default: root '.')"),
      node_path: z
        .string()
        .optional()
        .describe(
          "Path to an existing WorldEnvironment to modify instead of creating a new one"
        ),
      name: z
        .string()
        .optional()
        .describe("Node name (default: WorldEnvironment)"),
      background_mode: z
        .string()
        .optional()
        .describe(
          "Background mode: 'sky', 'color', 'canvas', 'clear_color' (default: sky)"
        ),
      background_color: z
        .any()
        .optional()
        .describe("Background color when mode is 'color'"),
      sky: z
        .object({
          sky_top_color: z.any().optional().describe("Sky top color"),
          sky_horizon_color: z.any().optional().describe("Sky horizon color"),
          ground_bottom_color: z.any().optional().describe("Ground bottom color"),
          ground_horizon_color: z
            .any()
            .optional()
            .describe("Ground horizon color"),
          sun_angle_max: z
            .number()
            .optional()
            .describe("Maximum sun angle in degrees"),
          sky_curve: z
            .number()
            .optional()
            .describe("Sky color curve (0.0-1.0)"),
        })
        .optional()
        .describe("ProceduralSkyMaterial settings"),
      ambient_light_color: z.any().optional().describe("Ambient light color"),
      ambient_light_energy: z
        .number()
        .optional()
        .describe("Ambient light energy"),
      ambient_light_source: z
        .string()
        .optional()
        .describe(
          "Ambient light source: BACKGROUND, DISABLED, COLOR, SKY"
        ),
      tonemap_mode: z
        .string()
        .optional()
        .describe("Tonemap mode: LINEAR, REINHARDT, FILMIC, ACES"),
      tonemap_exposure: z.number().optional().describe("Tonemap exposure"),
      tonemap_white: z.number().optional().describe("Tonemap white point"),
      fog_enabled: z.boolean().optional().describe("Enable volumetric fog"),
      fog_light_color: z.any().optional().describe("Fog light color"),
      fog_density: z.number().optional().describe("Fog density"),
      fog_light_energy: z.number().optional().describe("Fog light energy"),
      glow_enabled: z.boolean().optional().describe("Enable glow/bloom"),
      glow_intensity: z.number().optional().describe("Glow intensity"),
      glow_strength: z.number().optional().describe("Glow strength"),
      glow_bloom: z.number().optional().describe("Glow bloom amount"),
      ssao_enabled: z
        .boolean()
        .optional()
        .describe("Enable Screen-Space Ambient Occlusion"),
      ssao_radius: z.number().optional().describe("SSAO radius"),
      ssao_intensity: z.number().optional().describe("SSAO intensity"),
      ssr_enabled: z
        .boolean()
        .optional()
        .describe("Enable Screen-Space Reflections"),
      ssr_max_steps: z.number().optional().describe("SSR max steps"),
      ssr_fade_in: z.number().optional().describe("SSR fade in"),
      ssr_fade_out: z.number().optional().describe("SSR fade out"),
      sdfgi_enabled: z
        .boolean()
        .optional()
        .describe("Enable Signed Distance Field Global Illumination"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("setup_environment", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  // ─── 5. setup_camera_3d ────────────────────────────────────────────────

  server.tool(
    "setup_camera_3d",
    "Add or configure a Camera3D node. Set projection mode, FOV, near/far planes, position, rotation, look-at target, and cull mask.",
    {
      parent_path: z
        .string()
        .optional()
        .describe("Parent node path (default: root '.')"),
      node_path: z
        .string()
        .optional()
        .describe(
          "Path to an existing Camera3D to configure instead of creating a new one"
        ),
      name: z.string().optional().describe("Node name (default: Camera3D)"),
      projection: z
        .string()
        .optional()
        .describe(
          "Projection mode: 'perspective', 'orthogonal'/'orthographic', 'frustum'"
        ),
      fov: z
        .number()
        .optional()
        .describe("Field of view in degrees for perspective (default: 75)"),
      size: z
        .number()
        .optional()
        .describe("View size for orthogonal projection"),
      near: z
        .number()
        .optional()
        .describe("Near clipping plane (default: 0.05)"),
      far: z
        .number()
        .optional()
        .describe("Far clipping plane (default: 4000)"),
      cull_mask: z
        .number()
        .optional()
        .describe("Cull mask as integer bitmask"),
      current: z
        .boolean()
        .optional()
        .describe("Make this the current/active camera (default: false)"),
      position: z
        .any()
        .optional()
        .describe("Position as Vector3 (default: (0, 1, 3) for new cameras)"),
      rotation: z
        .any()
        .optional()
        .describe("Rotation in degrees as Vector3"),
      look_at: z
        .any()
        .optional()
        .describe(
          "Target position to look at as Vector3 (overrides rotation)"
        ),
      environment_path: z
        .string()
        .optional()
        .describe(
          "Path to an Environment resource for camera-specific environment override"
        ),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("setup_camera_3d", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: formatErrorForMcp(e) }],
          isError: true,
        };
      }
    }
  );

  // ─── 6. add_gridmap ────────────────────────────────────────────────────

  server.tool(
    "add_gridmap",
    "Add or configure a GridMap node with a MeshLibrary. Optionally set cells at specific grid positions with item IDs and orientations.",
    {
      parent_path: z
        .string()
        .optional()
        .describe("Parent node path (default: root '.')"),
      node_path: z
        .string()
        .optional()
        .describe(
          "Path to an existing GridMap to configure instead of creating a new one"
        ),
      name: z.string().optional().describe("Node name (default: GridMap)"),
      mesh_library_path: z
        .string()
        .optional()
        .describe(
          "Path to a MeshLibrary resource (res://path/to/library.meshlib or .tres)"
        ),
      cell_size: z
        .any()
        .optional()
        .describe("Cell size as Vector3 (default: (2, 2, 2))"),
      position: z.any().optional().describe("GridMap position as Vector3"),
      cells: z
        .array(
          z.object({
            x: z.number().describe("Cell X coordinate"),
            y: z.number().describe("Cell Y coordinate"),
            z: z.number().describe("Cell Z coordinate"),
            item: z
              .number()
              .optional()
              .describe("MeshLibrary item index (default: 0)"),
            orientation: z
              .number()
              .optional()
              .describe("Cell orientation index (default: 0)"),
          })
        )
        .optional()
        .describe("Array of cells to set with grid positions and item IDs"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_gridmap", params);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
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
