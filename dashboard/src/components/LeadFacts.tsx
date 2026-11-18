import { TRADE_LABELS, URGENCY_LABELS, label } from "@/lib/format";
import type { LeadCard } from "@/lib/types";
import { StatusBadge } from "./StatusBadge";

/** What the agent has worked out about the lead, as a small card. */
export function LeadFacts({ lead, children }: { lead: LeadCard; children?: React.ReactNode }) {
  const rows: [string, React.ReactNode][] = [
    ["Status", <StatusBadge key="s" status={lead.status} endState={lead.end_state} />],
    ["Job", [label(TRADE_LABELS, lead.trade), lead.job_type].filter(Boolean).join(", ") || "Not read yet"],
    ["Urgency", label(URGENCY_LABELS, lead.urgency) || "Not read yet"],
    ["Zip", lead.zip || "Not given yet"],
  ];
  if (lead.booked_slot) rows.push(["Booked", <span key="b" className="font-medium text-emerald-700">{lead.booked_slot}</span>]);
  return (
    <div className="rounded-xl border border-stone-200 bg-white p-4">
      <h2 className="text-sm font-semibold">What the agent knows</h2>
      {lead.summary && <p className="mt-2 text-sm text-stone-600">{lead.summary}</p>}
      <dl className="mt-3 space-y-2 text-sm">
        {rows.map(([k, v]) => (
          <div key={k} className="flex items-start justify-between gap-3">
            <dt className="text-stone-500">{k}</dt>
            <dd className="text-right">{v}</dd>
          </div>
        ))}
      </dl>
      {children}
    </div>
  );
}
