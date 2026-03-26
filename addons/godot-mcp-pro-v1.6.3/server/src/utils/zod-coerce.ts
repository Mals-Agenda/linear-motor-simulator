import { z } from "zod";

/**
 * Coerce a value that might be a JSON string into a string array.
 * LLMs sometimes pass arrays as stringified JSON (e.g. '["a","b"]' instead of ["a","b"]).
 */
export function coerceStringArray() {
  return z.preprocess((val) => {
    if (typeof val === "string") {
      try {
        const parsed = JSON.parse(val);
        if (Array.isArray(parsed)) return parsed;
      } catch {
        // not JSON, return as-is for zod to validate
      }
    }
    return val;
  }, z.array(z.string()));
}

/**
 * Coerce a value that might be a numeric string into a number.
 * LLMs sometimes pass numbers as strings (e.g. "30" instead of 30).
 */
export function coerceNumber() {
  return z.preprocess((val) => {
    if (typeof val === "string") {
      const n = Number(val);
      if (!isNaN(n)) return n;
    }
    return val;
  }, z.number());
}
