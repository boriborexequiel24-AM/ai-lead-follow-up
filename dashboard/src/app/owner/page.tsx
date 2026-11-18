import type { Metadata } from "next";
import Link from "next/link";
import { Container, PageHero } from "@/components/Brand";
import { StatusBadge } from "@/components/StatusBadge";
import { getOwnerOverview } from "@/lib/db";
import { TRADE_LABELS, URGENCY_LABELS, ago, duration, label } from "@/lib/format";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Owner view | Copperline Plumbing & Air (demo)",
  description: "How fast the agent answers, how many leads book, and every decision it made on sample leads.",
};

export default async function OwnerView() {
  const { metrics, samples, clock } = await getOwnerOverview();
  const cards = [
    {
      label: "Median time to first reply",
      value: metrics.median_first_reply_seconds == null ? "No data" : duration(metrics.median_first_reply_seconds),
      note: "From the lead's message to the agent's answer",
    },
    { label: "Booked", value: metrics.booked_pct == null ? "No data" : `${metrics.booked_pct}%`, note: "Of all leads, spam left out" },
    {
      label: "Needed a person",
      value: metrics.handed_off_pct == null ? "No data" : `${metrics.handed_off_pct}%`,
      note: "Emergencies, rejected prices and anything unclear",
    },
    { label: "Follow-ups sent", value: String(metrics.follow_ups_sent), note: "To leads who went quiet" },
    { label: "Prices waiting", value: String(metrics.waiting_approval), note: "For the owner's OK in Slack" },
  ];

  return (
    <>
      <PageHero eyebrow="Owner view" title="Every lead answered, and nothing hidden.">
        This is what Copperline&apos;s owner sees. The numbers cover every lead in the system: the sample leads plus demo
        visitors from the last 24 hours. The list shows sample leads only, because visitor conversations stay private to
        the person who started them. Open a lead to see each decision the agent made and why.
      </PageHero>

      <Container className="space-y-12 py-10">
      <section className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-5 [&>*:last-child]:col-span-2 lg:[&>*:last-child]:col-span-1">
        {cards.map((c) => (
          <div key={c.label} className="rounded-2xl border border-sand-200 bg-white p-4 sm:p-5">
            <p className="text-xs text-ink-500">{c.label}</p>
            <p className="mt-1.5 font-display text-3xl font-black text-copper-600">{c.value}</p>
            <p className="mt-1 text-xs text-ink-500">{c.note}</p>
          </div>
        ))}
      </section>

      <section>
        <div className="flex flex-wrap items-end justify-between gap-2">
          <h2 className="font-display text-[28px] font-extrabold leading-tight">Sample leads</h2>
          <p className="text-xs text-ink-500">
            {metrics.leads} leads in total
            {clock.mode === "demo" ? `. Demo clock: 1 day = ${clock.minutes_per_day} min` : ""}
          </p>
        </div>
        {samples.length === 0 ? (
          <p className="mt-4 rounded-xl border border-dashed border-sand-300 p-6 text-sm text-ink-500">
            No sample leads yet.
          </p>
        ) : (
          <ul className="mt-4 divide-y divide-sand-200 overflow-hidden rounded-2xl border border-sand-200 bg-white">
            {samples.map((lead) => (
              <li key={lead.id}>
                <Link href={`/owner/${lead.id}`} className="flex flex-col gap-2 p-4 hover:bg-copper-50 sm:flex-row sm:items-center sm:gap-6">
                  <div className="min-w-0 flex-1">
                    <p className="flex flex-wrap items-center gap-2 text-sm font-semibold">
                      {lead.name || "Unknown"}
                      <span className="text-xs font-normal text-ink-500">
                        {lead.source === "email" ? "by email" : "web form"}
                        {lead.zip ? `, ${lead.zip}` : ""}
                      </span>
                    </p>
                    <p className="mt-0.5 truncate text-sm text-ink-600">{lead.summary || "Not read yet"}</p>
                  </div>
                  <div className="flex flex-wrap items-center gap-2 text-xs text-ink-500 sm:w-64 sm:justify-end">
                    {lead.urgency === "emergency" && (
                      <span className="rounded-full bg-[#FCE8E4] px-2 py-0.5 font-medium text-[#9B2C1C] ring-1 ring-inset ring-[#F3C6BC]">
                        {label(URGENCY_LABELS, lead.urgency)}
                      </span>
                    )}
                    {lead.trade && lead.trade !== "unclear" && <span>{label(TRADE_LABELS, lead.trade)}</span>}
                    <StatusBadge status={lead.status} endState={lead.end_state} />
                  </div>
                  <p className="text-xs text-ink-500 sm:w-24 sm:text-right">{ago(lead.last_activity)}</p>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
      </Container>
    </>
  );
}
