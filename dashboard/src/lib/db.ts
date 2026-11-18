import "server-only";
import { env } from "./env";
import type { OwnerLead, OwnerOverview, ThreadData, Usage } from "./types";

// Every read goes through a function in the leads schema
// (supabase/migrations/*_dashboard.sql), called with the service key from the
// server. The browser never talks to Supabase.

async function rpc<T>(name: string, args: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${env.supabaseUrl()}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: env.supabaseServiceKey(),
      Authorization: `Bearer ${env.supabaseServiceKey()}`,
      "Content-Type": "application/json",
      "Content-Profile": "leads",
      "Accept-Profile": "leads",
    },
    body: JSON.stringify(args),
    cache: "no-store",
  });
  if (!res.ok) {
    throw new Error(`Supabase ${name} failed: ${res.status} ${await res.text()}`);
  }
  return (await res.json()) as T;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (value: string) => UUID.test(value);

type ThreadRow = ThreadData & { lead_id: string; is_visitor: boolean };

/** A visitor's own thread. Null unless the link is right and it's a visitor lead. */
export async function getVisitorThread(token: string): Promise<(ThreadData & { leadId: string }) | null> {
  if (!isUuid(token)) return null;
  const row = await rpc<ThreadRow | null>("visitor_thread", { p_token: token });
  if (!row || !row.is_visitor) return null;
  const { lead_id: leadId, lead, events, pending_approval, visitor_messages, clock } = row;
  return { lead, events, pending_approval, visitor_messages, clock, leadId };
}

/** The same thread without anything the browser shouldn't see. */
export function publicThread(thread: ThreadData & { leadId: string }): ThreadData {
  const { lead, events, pending_approval, visitor_messages, clock } = thread;
  return { lead, events, pending_approval, visitor_messages, clock };
}

export const getOwnerOverview = () => rpc<OwnerOverview>("owner_overview");

export async function getOwnerLead(id: string): Promise<OwnerLead | null> {
  if (!isUuid(id)) return null;
  return rpc<OwnerLead | null>("owner_lead", { p_lead_id: id });
}

export const getUsage = (ipHash: string, token?: string) =>
  rpc<Usage>("demo_usage", { p_ip_hash: ipHash, p_token: token ?? null });
