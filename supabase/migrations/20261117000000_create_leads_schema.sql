-- Phase 1: a separate schema for the lead follow-up demo.
--
-- This demo shares a Supabase project with the invoice demo (the free plan
-- allows two active projects). Everything for this demo lives in the `leads`
-- schema, so its tables, cleanup and access rules never touch the invoice
-- tables in `public`.
--
-- Safe to run more than once.

create schema if not exists leads;

-- The API roles need to be allowed into the schema at all.
grant usage on schema leads to anon, authenticated, service_role;

-- n8n and server code use the service role, which gets full access to
-- everything created here from now on.
alter default privileges in schema leads
  grant all on tables to service_role;
alter default privileges in schema leads
  grant all on sequences to service_role;
alter default privileges in schema leads
  grant execute on functions to service_role;

-- The public key (anon) gets nothing by default. Each table grants anon only
-- the columns the public dashboard needs, in its own migration, so a new
-- table is private until we decide otherwise. This matters here because
-- visitors type names and emails.
--
-- Functions are different: Postgres lets everyone run new functions unless
-- told otherwise, and that default can't be switched off for one schema
-- only. So every function migration in this schema ends with
--   revoke execute on function leads.<name> from public, anon, authenticated;
