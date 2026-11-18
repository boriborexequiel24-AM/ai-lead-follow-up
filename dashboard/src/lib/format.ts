// Plain-English labels and times. Safe to use in server and client components.

export const ACTION_LABELS: Record<string, string> = {
  offer_booking: "Offered visit times",
  confirm_booking: "Booked a visit",
  ask_question: "Asked a question",
  answer_question: "Answered a question",
  draft_price: "Drafted a price",
  escalate_emergency: "Emergency: owner alerted",
  decline: "Declined politely",
  hand_off: "Handed to a person",
  close: "Closed the lead",
};

export const STATUS_LABELS: Record<string, string> = {
  new: "New",
  active: "Talking",
  waiting_approval: "Price waiting for owner",
  booked: "Booked",
  handed_off: "With a person",
  closed: "Closed",
};

export const END_STATE_LABELS: Record<string, string> = {
  booked: "Booked",
  handed_off: "Handed off",
  declined: "Declined",
  not_interested: "Not interested",
  no_response: "No response",
  unsubscribed: "Unsubscribed",
  spam: "Spam",
};

export const URGENCY_LABELS: Record<string, string> = {
  emergency: "Emergency",
  this_week: "This week",
  flexible: "Flexible",
};

export const TRADE_LABELS: Record<string, string> = {
  plumbing: "Plumbing",
  hvac: "Heating and cooling",
  both: "Plumbing and HVAC",
  unclear: "Not clear yet",
};

export const label = (map: Record<string, string>, key: string | null | undefined) =>
  key ? (map[key] ?? key.replace(/_/g, " ")) : "";

const TZ = "America/Denver";

export function timeOfDay(iso: string) {
  return new Date(iso).toLocaleTimeString("en-US", { timeZone: TZ, hour: "numeric", minute: "2-digit" });
}

export function dateTime(iso: string) {
  return new Date(iso).toLocaleString("en-US", {
    timeZone: TZ, month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
  });
}

export function ago(iso: string, now = Date.now()) {
  const seconds = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000));
  if (seconds < 60) return "just now";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 48) return `${hours} h ago`;
  return `${Math.round(hours / 24)} days ago`;
}

export function duration(seconds: number) {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  const minutes = Math.floor(seconds / 60);
  const rest = Math.round(seconds % 60);
  return rest ? `${minutes}m ${rest}s` : `${minutes}m`;
}

