import { END_STATE_LABELS, STATUS_LABELS, label } from "@/lib/format";

const TONES: Record<string, string> = {
  new: "bg-sand-100 text-navy-900 ring-sand-200",
  active: "bg-navy-50 text-navy-800 ring-navy-200",
  waiting_approval: "bg-amber-50 text-amber-800 ring-amber-200",
  booked: "bg-emerald-50 text-emerald-700 ring-emerald-200",
  handed_off: "bg-violet-50 text-violet-700 ring-violet-200",
  closed: "bg-sand-100 text-ink-600 ring-sand-200",
};

/** The lead's status, with the end state for closed leads ("Closed: no response"). */
export function StatusBadge({ status, endState }: { status: string; endState?: string | null }) {
  const text =
    status === "closed" && endState ? `Closed: ${label(END_STATE_LABELS, endState).toLowerCase()}` : label(STATUS_LABELS, status);
  return (
    <span className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset ${TONES[status] ?? TONES.new}`}>
      {text}
    </span>
  );
}
