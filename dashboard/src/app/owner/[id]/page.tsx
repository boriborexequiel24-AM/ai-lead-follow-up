import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Container, PageHero, navyButton } from "@/components/Brand";
import { Conversation } from "@/components/Conversation";
import { LeadFacts } from "@/components/LeadFacts";
import { getOwnerLead } from "@/lib/db";
import { dateTime } from "@/lib/format";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Sample lead | Copperline owner view (demo)",
};

export default async function OwnerLeadPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const data = await getOwnerLead(id);
  if (!data) notFound();
  const { lead, events } = data;
  const decisions = events.filter((e) => e.kind === "agent").length;

  return (
    <>
      <PageHero
        compact
        eyebrow="Owner view: sample lead"
        title={lead.name || "Unknown lead"}
        actions={
          <Link href="/owner" className={navyButton}>
            Back to the owner view
          </Link>
        }
      >
        Came in {dateTime(lead.created_at)} by {lead.source === "email" ? "email" : "the website form"}. {decisions} agent
        decision{decisions === 1 ? "" : "s"}, each with its reason.
      </PageHero>

      <Container className="py-8 sm:py-10">
        <div className="grid items-start gap-6 lg:grid-cols-[1fr_20rem]">
          <section className="min-w-0 rounded-[22px] border border-sand-200 bg-white px-4 py-5 sm:px-6">
            <Conversation events={events} mode="owner" leadName={lead.name} />
          </section>
          <aside className="space-y-4 lg:sticky lg:top-6">
            <LeadFacts lead={lead}>
              <p className="mt-4 text-xs text-ink-500">
                {lead.follow_ups_sent > 0
                  ? `${lead.follow_ups_sent} follow-up${lead.follow_ups_sent === 1 ? "" : "s"} sent since the lead last wrote. `
                  : ""}
                Sample lead, made up for the demo.
              </p>
            </LeadFacts>
          </aside>
        </div>
      </Container>
    </>
  );
}
