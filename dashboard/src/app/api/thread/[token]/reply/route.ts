import { getUsage, getVisitorThread } from "@/lib/db";
import { callN8n, clean, fail, overAiCap, visitorHash } from "@/lib/demo";
import { env } from "@/lib/env";

// The visitor writes back as the customer. Same agent turn as the form, with
// the lead id so the agent sees the whole conversation.

export const runtime = "nodejs";
export const maxDuration = 60;

export async function POST(request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const body = await request.json().catch(() => null);
  const message = clean(body?.message, 2000);
  if (message.length < 1) return fail(400, "no_message", "Type a message first.");

  const thread = await getVisitorThread(token);
  if (!thread) return fail(404, "not_found", "This conversation doesn't exist or has been deleted.");
  if (thread.visitor_messages >= env.messagesPerThread()) {
    return fail(429, "thread_full", `This demo thread has reached its ${env.messagesPerThread()} messages. Start a new request from the home page to try another scenario.`);
  }

  const ipHash = visitorHash(request);
  const usage = await getUsage(ipHash);
  if (overAiCap(usage.ai_calls_today)) {
    return fail(429, "daily_cap", "The demo has reached its limit of AI replies for today. Please come back tomorrow.");
  }

  const { status, data } = await callN8n("lead-message", {
    source: "form",
    lead_id: thread.leadId,
    message,
    is_visitor: true,
    ip_hash: ipHash,
  });
  if (status === 200) return Response.json({ final_action: data.final_action ?? null });
  if (status === 504) return fail(504, "timeout", "The agent is taking longer than usual. Its reply will show up here shortly.");
  return fail(502, "agent_failed", "The agent couldn't answer just now. Your message is saved; try again in a minute.");
}
