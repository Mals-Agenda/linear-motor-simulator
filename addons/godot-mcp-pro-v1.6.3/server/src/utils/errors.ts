export class GodotConnectionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GodotConnectionError";
  }
}

export class GodotCommandError extends Error {
  public code: number;
  public data?: Record<string, unknown>;

  constructor(code: number, message: string, data?: Record<string, unknown>) {
    super(message);
    this.name = "GodotCommandError";
    this.code = code;
    this.data = data;
  }
}

export class TimeoutError extends Error {
  constructor(method: string, timeoutMs: number) {
    super(`Command '${method}' timed out after ${timeoutMs}ms`);
    this.name = "TimeoutError";
  }
}

export function formatErrorForMcp(error: unknown): string {
  if (error instanceof GodotCommandError) {
    let msg = `Godot error (${error.code}): ${error.message}`;
    if (error.data?.suggestion) {
      msg += `\nSuggestion: ${error.data.suggestion}`;
    }
    return msg;
  }
  if (error instanceof GodotConnectionError) {
    return `Connection error: ${error.message}. Make sure the Godot MCP Pro plugin is enabled in your Godot editor.`;
  }
  if (error instanceof TimeoutError) {
    return error.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}
