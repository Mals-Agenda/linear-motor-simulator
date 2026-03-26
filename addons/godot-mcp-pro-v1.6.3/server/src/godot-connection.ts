import { WebSocketServer, WebSocket } from "ws";
import { randomUUID } from "crypto";
import { createServer } from "net";
import {
  JsonRpcRequest,
  JsonRpcResponse,
  PendingRequest,
} from "./utils/types.js";
import {
  GodotConnectionError,
  GodotCommandError,
  TimeoutError,
} from "./utils/errors.js";

const BASE_PORT = 6505;
const MAX_PORT = 6509;
const COMMAND_TIMEOUT_MS = 30000;
const HEARTBEAT_INTERVAL_MS = 10000;

/** Check if a port is available */
function isPortFree(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = createServer();
    server.once("error", () => resolve(false));
    server.once("listening", () => {
      server.close(() => resolve(true));
    });
    server.listen(port, "127.0.0.1");
  });
}

export class GodotConnection {
  private wss: WebSocketServer | null = null;
  private client: WebSocket | null = null;
  private port: number;
  private pendingRequests: Map<string, PendingRequest> = new Map();
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;

  constructor(port: number = BASE_PORT) {
    this.port = port;
  }

  /** Start WebSocket server on first available port in range */
  async connect(): Promise<void> {
    if (this.wss) return;

    // Find an available port in range
    let chosenPort = this.port;
    for (let p = BASE_PORT; p <= MAX_PORT; p++) {
      if (await isPortFree(p)) {
        chosenPort = p;
        break;
      }
      if (p === MAX_PORT) {
        console.error(
          `[MCP] All ports ${BASE_PORT}-${MAX_PORT} are in use. Trying configured port ${this.port} anyway.`
        );
        chosenPort = this.port;
      }
    }
    this.port = chosenPort;

    return new Promise<void>((resolve, reject) => {
      this.wss = new WebSocketServer({ port: this.port, host: "127.0.0.1" });

      this.wss.on("listening", () => {
        console.error(
          `[MCP] WebSocket server listening on ws://127.0.0.1:${this.port}`
        );
        resolve();
      });

      this.wss.on("error", (err: Error) => {
        console.error("[MCP] WebSocket server error:", err.message);
        reject(err);
      });

      this.wss.on("connection", (ws: WebSocket) => {
        console.error("[MCP] Godot editor connected");

        if (this.client) {
          this.client.close(1000, "Replaced by new connection");
        }
        this.client = ws;
        this.startHeartbeat();

        ws.on("message", (data: Buffer) => {
          this.handleMessage(data.toString());
        });

        ws.on("close", () => {
          console.error("[MCP] Godot editor disconnected");
          if (this.client === ws) {
            this.client = null;
            this.stopHeartbeat();
            this.rejectAllPending(
              new GodotConnectionError("Godot disconnected")
            );
          }
        });

        ws.on("error", (err: Error) => {
          console.error("[MCP] WebSocket error:", err.message);
        });
      });
    });
  }

  disconnect(): void {
    this.stopHeartbeat();
    if (this.client) {
      this.client.close(1000, "Server shutting down");
      this.client = null;
    }
    if (this.wss) {
      this.wss.close();
      this.wss = null;
    }
    this.rejectAllPending(new GodotConnectionError("Server shut down"));
  }

  isConnected(): boolean {
    return this.client?.readyState === WebSocket.OPEN;
  }

  getPort(): number {
    return this.port;
  }

  async sendCommand(
    method: string,
    params: Record<string, unknown> = {}
  ): Promise<unknown> {
    if (!this.isConnected()) {
      throw new GodotConnectionError(
        "Godot editor is not connected. Make sure the Godot MCP Pro plugin is enabled and the editor is running."
      );
    }

    const id = randomUUID();
    const request: JsonRpcRequest = {
      jsonrpc: "2.0",
      method,
      params,
      id,
    };

    return new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(new TimeoutError(method, COMMAND_TIMEOUT_MS));
      }, COMMAND_TIMEOUT_MS);

      this.pendingRequests.set(id, {
        resolve: resolve as (value: JsonRpcResponse) => void,
        reject,
        timer,
      });
      this.client!.send(JSON.stringify(request));
    });
  }

  private handleMessage(data: string): void {
    let msg: JsonRpcResponse;
    try {
      msg = JSON.parse(data);
    } catch {
      console.error("[MCP] Failed to parse message from Godot:", data);
      return;
    }

    if ((msg as unknown as { method: string }).method === "pong") {
      return;
    }

    if (!msg.id) return;

    const pending = this.pendingRequests.get(msg.id);
    if (!pending) return;

    clearTimeout(pending.timer);
    this.pendingRequests.delete(msg.id);

    if (msg.error) {
      pending.reject(
        new GodotCommandError(
          msg.error.code,
          msg.error.message,
          msg.error.data
        )
      );
    } else {
      pending.resolve(msg.result as unknown as JsonRpcResponse);
    }
  }

  private rejectAllPending(error: Error): void {
    for (const [, pending] of this.pendingRequests) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pendingRequests.clear();
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnected()) {
        this.client!.send(
          JSON.stringify({ jsonrpc: "2.0", method: "ping", params: {} })
        );
      }
    }, HEARTBEAT_INTERVAL_MS);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }
}
