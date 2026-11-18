import { getVisitorThread, publicThread } from "@/lib/db";
import { fail } from "@/lib/demo";

// The visitor's thread, polled by the thread page every few seconds.

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(_request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const thread = await getVisitorThread(token);
  if (!thread) return fail(404, "not_found", "This conversation doesn't exist or has been deleted.");
  return Response.json(publicThread(thread), { headers: { "Cache-Control": "no-store" } });
}
