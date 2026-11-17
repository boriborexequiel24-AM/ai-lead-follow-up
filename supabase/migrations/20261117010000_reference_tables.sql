-- Phase 2: what the agent knows about the fictional company.
--
-- Three small tables the agent reads on every turn: the company profile,
-- answers to common questions, and the sample price sheet. The contents are
-- in supabase/seed.sql. All of it is fictional.
--
-- Safe to run more than once.

-- One row only: the company the demo pretends to be.
create table if not exists leads.company_profile (
  id                    smallint primary key default 1 check (id = 1),
  name                  text not null,
  phone                 text not null,
  emergency_phone       text not null,
  email                 text not null,
  timezone              text not null default 'America/Denver',
  business_hours        text not null,
  service_area_name     text not null,
  service_area_zips     text[] not null,
  services_offered      text[] not null,
  services_not_offered  text[] not null,
  quiet_hours_start     time not null default '20:00',
  quiet_hours_end       time not null default '08:00',
  updated_at            timestamptz not null default now()
);

-- Answers the agent may give without asking the owner. No dollar amounts:
-- every price goes through owner approval.
create table if not exists leads.faq (
  id      serial primary key,
  topic   text not null unique,
  answer  text not null check (answer !~ '\$\s*\d')
);

-- Sample prices. The agent drafts a range from these; the owner approves it
-- in Slack before anything is sent.
create table if not exists leads.price_items (
  id          serial primary key,
  code        text not null unique,
  trade       text not null check (trade in ('plumbing', 'hvac')),
  job         text not null,
  low_price   numeric(10, 2) not null check (low_price > 0),
  high_price  numeric(10, 2) not null check (high_price >= low_price),
  notes       text
);

-- Private to the public key until the dashboard phase decides what to show.
revoke all on leads.company_profile, leads.faq, leads.price_items from anon, authenticated;
