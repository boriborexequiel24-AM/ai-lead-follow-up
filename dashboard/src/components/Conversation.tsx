import { ACTION_LABELS, label, timeOfDay } from "@/lib/format";
import type { AgentEvent, ThreadEvent } from "@/lib/types";

// A conversation, oldest first. "customer" is what the visitor sees in their
// thread; "owner" adds everything behind each reply (the reason, guardrail
// changes, notes for the owner, approvals).

type Mode = "customer" | "owner";

export function Conversation({ events, mode, leadName }: { events: ThreadEvent[]; mode: Mode; leadName?: string | null }) {
  let followUps = 0;
  return (
    <ol className="space-y-4">
      {events.map((event, i) => {
        if (event.kind === "lead") {
          return (
            <li key={i} className="flex flex-col items-end">
              <div className="max-w-[85%] whitespace-pre-wrap rounded-[16px_16px_4px_16px] bg-copper-600 px-4 py-2.5 text-sm text-white">
                {event.body}
              </div>
              <p className="mt-1 text-xs text-ink-500">
                {mode === "customer" ? "You" : leadName || "Lead"}
                {mode === "owner" && event.channel === "email" ? " by email" : ""} &middot; {timeOfDay(event.at)}
              </p>
            </li>
          );
        }
        const followUp = event.trigger === "follow_up" && event.final_action !== "close" ? ++followUps : null;
        return <AgentStep key={i} event={event} mode={mode} followUp={followUp} />;
      })}
    </ol>
  );
}

const FOLLOW_UP_DAY: Record<number, number> = { 1: 1, 2: 3, 3: 7 };

function AgentStep({ event, mode, followUp }: { event: AgentEvent; mode: Mode; followUp: number | null }) {
  const msg = event.message;
  const changed = event.action !== event.final_action || event.violations.length > 0;
  const owner = mode === "owner";

  let bubble: React.ReactNode = null;
  if (msg?.status === "sent") {
    bubble = msg.body;
  } else if (msg?.status === "pending_approval") {
    bubble = owner ? (
      <>
        <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-amber-700">Draft, waiting for approval</span>
        {msg.body}
      </>
    ) : (
      <span className="italic text-ink-500">Checking the price with the owner before sending it...</span>
    );
  } else if (msg?.status === "rejected") {
    bubble = owner ? (
      <>
        <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-red-700">Rejected, never sent</span>
        <span className="text-ink-500 line-through">{msg.body}</span>
      </>
    ) : (
      <span className="italic text-ink-500">The owner will get in touch about the price personally.</span>
    );
  } else if (msg?.status === "scheduled") {
    bubble = (
      <>
        <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-ink-500">
          Held for quiet hours{msg.send_after ? `, goes out at ${timeOfDay(msg.send_after)}` : ""}
        </span>
        {owner ? msg.body : null}
      </>
    );
  }

  const tone =
    event.final_action === "escalate_emergency"
      ? "bg-[#FCE8E4] text-[#9B2C1C] ring-[#F3C6BC]"
      : event.final_action === "hand_off" || changed
        ? "bg-amber-50 text-amber-800 ring-amber-200"
        : event.final_action === "confirm_booking"
          ? "bg-emerald-50 text-emerald-800 ring-emerald-200"
          : "bg-sand-100 text-navy-900 ring-sand-200";

  return (
    <li className="flex flex-col items-start">
      {bubble ? (
        <div className="max-w-[85%] whitespace-pre-wrap rounded-[16px_16px_16px_4px] bg-navy-50 px-4 py-2.5 text-sm leading-[1.5] text-navy-900">
          {bubble}
        </div>
      ) : (
        <p className="text-sm italic text-ink-500">
          {event.final_action === "close" && event.end_state === "no_response"
            ? "No reply after 3 follow-ups, so the agent closed the lead."
            : `${label(ACTION_LABELS, event.final_action)}, no message sent.`}
        </p>
      )}

      <div className="mt-1.5 flex max-w-[85%] flex-wrap items-center gap-x-2 gap-y-1 text-xs text-ink-500">
        <span>Copperline agent &middot; {timeOfDay(event.at)}</span>
        <span className={`rounded-full px-2 py-0.5 font-medium ring-1 ring-inset ${tone}`}>
          {label(ACTION_LABELS, event.final_action)}
        </span>
        {followUp && (
          <span className="rounded-full bg-copper-50 px-2 py-0.5 font-medium text-copper-700 ring-1 ring-inset ring-copper-200">
            Follow-up {followUp}
            {FOLLOW_UP_DAY[followUp] ? `, day ${FOLLOW_UP_DAY[followUp]}` : ""}
          </span>
        )}
        {event.slot_label && <span className="text-emerald-700">{event.slot_label}</span>}
        {event.approval?.status === "approved" && (
          <span className="text-emerald-700">
            {owner ? `Price approved by ${event.approval.decided_by}` : "Price approved by the owner"}
          </span>
        )}
        {event.approval?.status === "rejected" && owner && <span className="text-red-700">Rejected by {event.approval.decided_by}</span>}
      </div>

      {changed && (
        <p className="mt-1.5 max-w-[85%] rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
          <span className="font-semibold">Guardrail stepped in.</span> The agent chose &ldquo;
          {label(ACTION_LABELS, event.action)}&rdquo;
          {event.violations.length ? `, but: ${event.violations.join("; ")}.` : "."}{" "}
          {event.action !== event.final_action ? `It became "${label(ACTION_LABELS, event.final_action)}".` : ""}
        </p>
      )}

      {owner ? (
        <div className="mt-1.5 max-w-[85%] space-y-1 text-xs text-ink-600">
          <p>
            <span className="font-semibold text-navy-900">Why:</span> {event.reason}
          </p>
          {event.owner_note && (
            <p>
              <span className="font-semibold text-navy-900">Note for the owner:</span> {event.owner_note}
            </p>
          )}
        </div>
      ) : (
        <details className="mt-1 max-w-[85%] text-xs text-ink-500">
          <summary className="cursor-pointer select-none hover:text-copper-700">Why did it do that?</summary>
          <p className="mt-1 rounded-lg bg-sand-100 px-3 py-2 text-ink-600">{event.reason}</p>
        </details>
      )}
    </li>
  );
}
