import "server-only";
import { createHash } from "node:crypto";
import { env } from "./env";

// Shared by the API routes: who the visitor is (as a salted hash, never the
// raw IP) and how to call the n8n webhooks without exposing the secret.

export function visitorHash(request: Request): string {
  const ip =
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || request.headers.get("x-real-ip") || "local";
  return createHash("sha256").update(`${env.ipHashSalt()}:${ip}`).digest("hex");
}

export function fail(status: number, error: string, message: string) {
  return Response.json({ error, message }, { status });
}

/** Posts to an n8n webhook. Returns the status and JSON body, or a 504 on timeout. */
export async function callN8n(path: string, body: Record<string, unknown>, timeoutMs = 55_000) {
  try {
    const res = await fetch(`${env.n8nBaseUrl()}/webhook/${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-webhook-secret": env.n8nWebhookSecret() },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
      cache: "no-store",
    });
    const data = await res.json().catch(() => ({}));
    return { status: res.status, data: data as Record<string, unknown> };
  } catch {
    return { status: 504, data: { error: "timeout" } as Record<string, unknown> };
  }
}

/** An agent turn is two AI calls; refuse once the day's cap would be passed. */
export function overAiCap(aiCallsToday: number) {
  return aiCallsToday + 2 > env.dailyAiCallCap();
}

export const clean = (value: unknown, max: number) => (typeof value === "string" ? value.trim().slice(0, max) : "");
