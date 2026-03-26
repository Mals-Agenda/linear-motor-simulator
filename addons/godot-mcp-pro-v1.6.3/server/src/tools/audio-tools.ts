import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { GodotConnection } from "../godot-connection.js";
import { formatErrorForMcp } from "../utils/errors.js";

export function registerAudioTools(
  server: McpServer,
  godot: GodotConnection
): void {
  server.tool(
    "get_audio_bus_layout",
    "Get the entire audio bus layout: all buses with volumes, effects, send targets, solo/mute states",
    {},
    async (params) => {
      try {
        const result = await godot.sendCommand("get_audio_bus_layout", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "add_audio_bus",
    "Add a new audio bus with name, volume, send target, solo, and mute settings",
    {
      name: z.string().describe("Name for the new audio bus"),
      volume_db: z.number().optional().describe("Volume in dB (default: 0)"),
      send: z.string().optional().describe("Name of the bus to send output to (e.g. 'Master')"),
      solo: z.boolean().optional().describe("Solo this bus (default: false)"),
      mute: z.boolean().optional().describe("Mute this bus (default: false)"),
      at_position: z.number().optional().describe("Bus index position to insert at (-1 = end)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_audio_bus", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "set_audio_bus",
    "Modify an existing audio bus: volume, solo, mute, bypass_effects, send, or rename",
    {
      name: z.string().describe("Name of the audio bus to modify"),
      volume_db: z.number().optional().describe("Volume in dB"),
      solo: z.boolean().optional().describe("Solo state"),
      mute: z.boolean().optional().describe("Mute state"),
      bypass_effects: z.boolean().optional().describe("Bypass all effects on this bus"),
      send: z.string().optional().describe("Name of the bus to send output to"),
      rename: z.string().optional().describe("New name for the bus"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("set_audio_bus", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "add_audio_bus_effect",
    "Add an audio effect to a bus. Types: reverb, chorus, delay, compressor, limiter, phaser, distortion, lowpassfilter, highpassfilter, bandpassfilter, amplify, eq",
    {
      bus: z.string().describe("Name of the audio bus"),
      effect_type: z.string().describe("Effect type: reverb, chorus, delay, compressor, limiter, phaser, distortion, lowpassfilter (or lowpass), highpassfilter (or highpass), bandpassfilter (or bandpass), amplify, eq"),
      params: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional().describe("Effect-specific parameters. E.g. for reverb: {room_size, damping, wet, dry, spread}; for compressor: {threshold, ratio, attack_us, release_ms}; for filters: {cutoff_hz, resonance}"),
      at_position: z.number().optional().describe("Effect index position (-1 = end)"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_audio_bus_effect", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "add_audio_player",
    "Add an AudioStreamPlayer, AudioStreamPlayer2D, or AudioStreamPlayer3D node to a parent node",
    {
      node_path: z.string().describe("Path to the parent node"),
      name: z.string().describe("Name for the new audio player node"),
      type: z.string().optional().describe("Player type: AudioStreamPlayer (default), AudioStreamPlayer2D, AudioStreamPlayer3D"),
      stream: z.string().optional().describe("Path to audio resource (e.g. 'res://audio/music.ogg')"),
      volume_db: z.number().optional().describe("Volume in dB (default: 0)"),
      bus: z.string().optional().describe("Audio bus name (default: 'Master')"),
      autoplay: z.boolean().optional().describe("Auto-play when scene starts (default: false)"),
      max_distance: z.number().optional().describe("Maximum hearing distance (for 2D/3D players)"),
      attenuation: z.number().optional().describe("Distance attenuation factor (for 2D players)"),
      attenuation_model: z.number().optional().describe("Attenuation model for 3D: 0=inverse_distance, 1=inverse_square, 2=logarithmic"),
      unit_size: z.number().optional().describe("Unit size for 3D player volume reference"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("add_audio_player", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );

  server.tool(
    "get_audio_info",
    "Get audio setup for a node subtree: finds all AudioStreamPlayer nodes with their settings, streams, and bus assignments",
    {
      node_path: z.string().describe("Path to the root node to search within"),
    },
    async (params) => {
      try {
        const result = await godot.sendCommand("get_audio_info", params);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
      } catch (e) {
        return { content: [{ type: "text", text: formatErrorForMcp(e) }], isError: true };
      }
    }
  );
}
