-- Phase 4: where every lead, message and agent decision is stored.
--
--   leads       one row per lead (a person and their conversation)
--   decisions   every agent choice, its reason, and what the guardrails did with it
--   messages    every message in and out, shown as the conversation thread
--   approvals   prices waiting for the owner in Slack
--   slots       fake visit times the agent may offer (reset by the cleanup job)
--
-- All private: no grants to the public key and Row Level Security with no
-- policies. n8n and server code use the service role. Safe to run more than once.

create table if not exists leads.leads (
  id                    uuid primary key default gen_random_uuid(),
  -- The visitor's private link to their own thread. Unguessable, never the id.
  public_token          uuid not null unique default gen_random_uuid(),
  source                text not null check (source in ('form', 'email')),
  name                  text,
  email                 text,
  phone                 text,
  zip                   text,
  status                text not null default 'new'
                        check (status in ('new', 'active', 'waiting_approval', 'booked', 'handed_off', 'closed')),
  end_state             text check (end_state in (
                          'booked', 'handed_off', 'declined', 'not_interested',
                          'no_response', 'unsubscribed', 'spam')),
  facts                 jsonb,          -- latest output of the read step
  summary               text,           -- one line for the owner
  is_visitor            boolean not null default false,  -- made by a public demo visitor, deleted after 24h
  ip_hash               text,           -- salted hash, for demo rate limits only
  awaiting_reply_since  timestamptz,    -- last agent message the lead hasn't answered yet
  follow_ups_sent       int not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists leads_email_idx on leads.leads (lower(email), created_at);
create index if not exists leads_phone_idx on leads.leads (phone, created_at) where phone is not null and phone <> '';
create index if not exists leads_followup_idx on leads.leads (awaiting_reply_since) where awaiting_reply_since is not null;
create index if not exists leads_visitor_idx on leads.leads (ip_hash, created_at) where is_visitor;

create table if not exists leads.decisions (
  id             bigserial primary key,
  lead_id        uuid not null references leads.leads (id) on delete cascade,
  trigger        text not null check (trigger in ('message', 'follow_up')),
  facts          jsonb not null,
  action         text not null,     -- what the AI picked
  reason         text not null,
  reply          text not null,     -- what the AI wrote, before any guardrail change
  price_code     text,
  offered_slots  timestamptz[] not null default '{}',
  slot           timestamptz,
  end_state      text,
  owner_note     text,
  final_action   text not null,     -- what actually happened after the guardrails
  violations     text[] not null default '{}',
  model          text,
  created_at     timestamptz not null default now()
);
create index if not exists decisions_lead_idx on leads.decisions (lead_id, created_at);

create table if not exists leads.messages (
  id           bigserial primary key,
  lead_id      uuid not null references leads.leads (id) on delete cascade,
  direction    text not null check (direction in ('in', 'out')),
  channel      text not null check (channel in ('form', 'email', 'web')),
  subject      text,
  body         text not null,
  -- received: from the lead. sent: visible to the lead. scheduled: waiting for
  -- quiet hours to end. pending_approval / rejected: prices in Slack.
  status       text not null check (status in ('received', 'sent', 'scheduled', 'pending_approval', 'rejected')),
  send_after   timestamptz,
  decision_id  bigint references leads.decisions (id) on delete set null,
  external_id  text unique,          -- email Message-ID, so an email is never processed twice
  created_at   timestamptz not null default now()
);
create index if not exists messages_lead_idx on leads.messages (lead_id, created_at);

create table if not exists leads.approvals (
  id           bigserial primary key,
  lead_id      uuid not null references leads.leads (id) on delete cascade,
  decision_id  bigint not null references leads.decisions (id) on delete cascade,
  message_id   bigint not null references leads.messages (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  slack_ts     text,
  decided_by   text,
  decided_at   timestamptz,
  created_at   timestamptz not null default now()
);

create table if not exists leads.slots (
  starts_at       timestamptz primary key,
  booked_lead_id  uuid references leads.leads (id) on delete set null,
  booked_at       timestamptz
);

revoke all on leads.leads, leads.decisions, leads.messages, leads.approvals, leads.slots
  from anon, authenticated;
alter table leads.leads     enable row level security;
alter table leads.decisions enable row level security;
alter table leads.messages  enable row level security;
alter table leads.approvals enable row level security;
alter table leads.slots     enable row level security;
