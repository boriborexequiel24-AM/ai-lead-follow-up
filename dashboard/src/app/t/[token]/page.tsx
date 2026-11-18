import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Container, PageHero, navyButton } from "@/components/Brand";
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
  return (
    <>
      <PageHero
        compact
        eyebrow="Your private conversation"
        title="You and Copperline"
        actions={
          <Link href="/" className={navyButton}>
            Try another scenario
          </Link>
        }
      >
        Only you can see this link. The conversation is deleted after 24 hours.
      </PageHero>
      <Container className="py-8 sm:py-10">
        <ThreadView token={token} initial={publicThread(thread)} maxMessages={env.messagesPerThread()} />
      </Container>
    </>
  );
}
