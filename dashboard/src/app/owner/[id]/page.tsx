import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
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
    <div className="space-y-6">
      <Link href="/owner" className="text-sm text-copper-700 hover:underline">
        Back to the owner view
      </Link>
      <div className="grid items-start gap-6 lg:grid-cols-[1fr_20rem]">
        <section className="rounded-2xl border border-stone-200 bg-stone-100/60 p-4 sm:p-6">
          <div className="mb-5 border-b border-stone-200 pb-4">
            <h1 className="text-lg font-semibold">{lead.name || "Unknown lead"}</h1>
            <p className="text-xs text-stone-500">
              Came in {dateTime(lead.created_at)} by {lead.source === "email" ? "email" : "the website form"}. {decisions}{" "}
              agent decision{decisions === 1 ? "" : "s"}, each with its reason.
            </p>
          </div>
          <Conversation events={events} mode="owner" leadName={lead.name} />
        </section>
        <aside className="space-y-4 lg:sticky lg:top-6">
          <LeadFacts lead={lead}>
            <p className="mt-4 text-xs text-stone-400">
              {lead.follow_ups_sent > 0
                ? `${lead.follow_ups_sent} follow-up${lead.follow_ups_sent === 1 ? "" : "s"} sent since the lead last wrote. `
                : ""}
              Sample lead, made up for the demo.
            </p>
          </LeadFacts>
        </aside>
      </div>
    </div>
  );
}
