// Shapes returned by the leads schema functions (supabase/migrations/*_dashboard.sql).

export type LeadStatus = "new" | "active" | "waiting_approval" | "booked" | "handed_off" | "closed";

export type LeadCard = {
  name: string | null;
  source: "form" | "email";
  zip: string | null;
  status: LeadStatus;
  end_state: string | null;
  summary: string | null;
  trade: string | null;
  job_type: string | null;
  urgency: string | null;
  created_at: string;
  follow_ups_sent: number;
  next_follow_up_at: string | null;
  booked_slot: string | null;
};

export type LeadEvent = {
  kind: "lead";
  at: string;
  channel: "form" | "email" | "web";
  body: string;
};

export type AgentEvent = {
  kind: "agent";
  at: string;
  trigger: "message" | "follow_up";
  action: string;
  final_action: string;
  reason: string;
  violations: string[];
  owner_note: string | null;
  end_state: string | null;
  slot_label: string | null;
  message: {
    body: string;
    status: "sent" | "scheduled" | "pending_approval" | "rejected";
    sent_at: string;
    send_after: string | null;
  } | null;
  approval: { status: "pending" | "approved" | "rejected"; decided_by: string | null; decided_at: string | null } | null;
};

export type ThreadEvent = LeadEvent | AgentEvent;

export type Clock = { mode: "demo" | "real"; minutes_per_day: number; retention_hours?: number };

export type ThreadData = {
  lead: LeadCard;
  events: ThreadEvent[];
  pending_approval: { id: number; reply: string; created_at: string } | null;
  visitor_messages: number;
  clock: Clock;
};

export type OwnerMetrics = {
  leads: number;
  median_first_reply_seconds: number | null;
  booked_pct: number | null;
  handed_off_pct: number | null;
  follow_ups_sent: number;
  waiting_approval: number;
};

export type SampleLead = LeadCard & { id: string; messages: number; last_activity: string };

export type OwnerOverview = { metrics: OwnerMetrics; samples: SampleLead[]; clock: Clock };

export type OwnerLead = { lead: LeadCard; facts: Record<string, unknown> | null; events: ThreadEvent[] };

export type Usage = {
  leads_today: number;
  ai_calls_today: number;
  thread: { lead_id: string; is_visitor: boolean; visitor_messages: number } | null;
};
