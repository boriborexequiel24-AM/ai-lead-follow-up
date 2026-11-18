import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ThreadView } from "@/components/ThreadView";
import { getVisitorThread, publicThread } from "@/lib/db";
import { env } from "@/lib/env";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Your conversation | Copperline Plumbing & Air (demo)",
  robots: { index: false, follow: false },
};

export default async function ThreadPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const thread = await getVisitorThread(token);
  if (!thread) notFound();
  return <ThreadView token={token} initial={publicThread(thread)} maxMessages={env.messagesPerThread()} />;
}
