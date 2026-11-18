import { getUsage } from "@/lib/db";
import { callN8n, clean, fail, overAiCap, visitorHash } from "@/lib/demo";
import { env } from "@/lib/env";

// The quote form. Checks the demo limits, then sends the lead to n8n
// (workflow 1, the agent turn) and answers with the visitor's private thread
// link. Runs on the server so the webhook secret never reaches the browser.

export const runtime = "nodejs";
export const maxDuration = 60;

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object") return fail(400, "bad_request", "Something went wrong. Please try again.");

  const lead = {
    name: clean(body.name, 100),
    email: clean(body.email, 200).toLowerCase(),
    phone: clean(body.phone, 30),
    zip: clean(body.zip, 10),
    message: clean(body.message, 2000),
  };
  if (lead.message.length < 3) return fail(400, "no_message", "Tell us a little about the job.");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(lead.email)) return fail(400, "bad_email", "Enter an email address (a made-up one is fine).");
  if (lead.zip && !/^\d{5}$/.test(lead.zip)) return fail(400, "bad_zip", "Zip codes are 5 digits.");

  const ipHash = visitorHash(request);
  const usage = await getUsage(ipHash);
  if (usage.leads_today >= env.leadsPerIpPerDay()) {
    return fail(429, "rate_limited", `The demo allows ${env.leadsPerIpPerDay()} new requests a day per visitor. Try again tomorrow, or keep chatting in a thread you already started.`);
  }
  if (overAiCap(usage.ai_calls_today)) {
    return fail(429, "daily_cap", "The demo has reached its limit of AI replies for today. Please come back tomorrow.");
  }

  const { status, data } = await callN8n("lead-message", {
    source: "form",
    ...lead,
    subject: "Quote request from the website",
    is_visitor: true,
    ip_hash: ipHash,
  });
  if (status === 200 && typeof data.public_token === "string") {
    return Response.json({ token: data.public_token, final_action: data.final_action ?? null });
  }
  if (status === 504) return fail(504, "timeout", "The agent is taking longer than usual. Please try again in a minute.");
  if (status === 400) return fail(400, "invalid", String(data.error || "Please check the form."));
  return fail(502, "agent_failed", "The agent couldn't answer just now. Please try again in a minute.");
}
