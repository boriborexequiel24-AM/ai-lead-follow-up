-- Phase 5: remember each email lead's Gmail thread.
--
-- Replies to the agent's emails don't carry the lead-demo label, so the email
-- intake workflow finds them by thread instead: any new message in a thread
-- belonging to a recent lead is that lead replying. Also used to send the
-- agent's replies into the same thread.
--
-- Safe to run more than once.

alter table leads.leads add column if not exists email_thread_id text;
create index if not exists leads_email_thread_idx on leads.leads (email_thread_id) where email_thread_id is not null;
