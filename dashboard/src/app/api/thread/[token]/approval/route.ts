import { getVisitorThread } from "@/lib/db";
import { callN8n, fail } from "@/lib/demo";

// The visitor plays the owner and approves or rejects their own price. n8n
// (workflow 6) records it exactly like the Slack button and updates the Slack
// message too.

export const runtime = "nodejs";
export const maxDuration = 30;

export async function POST(request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const body = await request.json().catch(() => null);
  if (typeof body?.approved !== "boolean") return fail(400, "bad_request", "Choose approve or reject.");

  const thread = await getVisitorThread(token);
  if (!thread) return fail(404, "not_found", "This conversation doesn't exist or has been deleted.");
  if (!thread.pending_approval) return fail(409, "nothing_pending", "There's no price waiting for approval.");

  const { status, data } = await callN8n("lead-demo-owner", { token, approved: body.approved }, 25_000);
  if (status === 200 && data.changed) return Response.json({ status: data.status });
  if (status === 200) return fail(409, "already_decided", "That price was already decided.");
  return fail(502, "failed", "That didn't go through. Please try again.");
}
