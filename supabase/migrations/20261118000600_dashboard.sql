-- Phase 8: what the demo site reads, and the visitor playing the owner.
--
--   is_sample                  new column: the sample leads shown in the public
--                              owner view (made by scripts/seed_demo_leads.py)
--   thread_events              a lead's conversation as the site shows it
--   visitor_thread             a visitor's own thread, found by its private link
--   owner_overview             overall numbers plus the sample leads list
--   owner_lead                 one sample lead's full timeline
--   demo_usage                 counts for the demo limits
--   visitor_resolve_approval   a visitor approves or rejects their own price
--
-- The site calls these from its server with the service key. The public key
-- still can't run anything. Visitor leads are never listed: a visitor only
-- reaches their own thread through its unguessable link, and the owner view
-- shows sample leads only.
--
-- Safe to run more than once.

alter table leads.leads add column if not exists is_sample boolean not null default false;

-- Every step of a conversation, oldest first: the lead's messages, and each
-- agent decision with the message it produced (if any).
create or replace function leads.thread_events(p_lead_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(e.event order by e.at, e.seq), '[]'::jsonb)
  from (
    select m.created_at as at, m.id * 2 as seq, jsonb_build_object(
      'kind', 'lead',
      'at', m.created_at,
      'channel', m.channel,
      'body', m.body
    ) as event
    from leads.messages m
    where m.lead_id = p_lead_id and m.direction = 'in'
    union all
    select d.created_at, coalesce(o.id * 2 + 1, d.id), jsonb_build_object(
      'kind', 'agent',
      'at', d.created_at,
      'trigger', d.trigger,
      'action', d.action,
      'final_action', d.final_action,
      'reason', d.reason,
      'violations', to_jsonb(d.violations),
      'owner_note', d.owner_note,
      'end_state', d.end_state,
      'slot_label', case when d.final_action = 'confirm_booking' then leads.slot_label(d.slot) end,
      'message', case when o.id is null then null else jsonb_build_object(
        'body', o.body, 'status', o.status, 'sent_at', o.created_at, 'send_after', o.send_after) end,
      'approval', (select jsonb_build_object('status', a.status, 'decided_by', a.decided_by, 'decided_at', a.decided_at)
                   from leads.approvals a where a.decision_id = d.id order by a.id desc limit 1)
    )
    from leads.decisions d
    left join lateral (
      select m.* from leads.messages m
      where m.decision_id = d.id and m.direction = 'out' order by m.id limit 1
    ) o on true
    where d.lead_id = p_lead_id
  ) e
$$;

-- When the next follow-up is due, or null if none is coming.
create or replace function leads.next_follow_up_at(p_lead leads.leads)
returns timestamptz language sql stable set search_path = '' as $$
  select case
    when p_lead.status = 'active' and p_lead.end_state is null and p_lead.awaiting_reply_since is not null
    then p_lead.awaiting_reply_since
         + (s.follow_up_gaps_days[least(p_lead.follow_ups_sent, cardinality(s.follow_up_gaps_days) - 1) + 1])::double precision
           * leads.day_length()
  end
  from leads.settings s where s.id = 1
$$;

-- The lead fields the site shows (no email, phone or IP).
create or replace function leads.lead_card(p_lead leads.leads)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'name', p_lead.name,
    'source', p_lead.source,
    'zip', p_lead.zip,
    'status', p_lead.status,
    'end_state', p_lead.end_state,
    'summary', p_lead.summary,
    'trade', p_lead.facts->>'trade',
    'job_type', p_lead.facts->>'job_type',
    'urgency', p_lead.facts->>'urgency',
    'created_at', p_lead.created_at,
    'follow_ups_sent', p_lead.follow_ups_sent,
    'next_follow_up_at', leads.next_follow_up_at(p_lead),
    'booked_slot', (select leads.slot_label(s.starts_at) from leads.slots s
                    where s.booked_lead_id = p_lead.id order by s.starts_at limit 1)
  )
$$;

-- A visitor's own thread, found by the private link. Returns null if the
-- link is wrong. lead_id is for the site's server only; it never reaches the
-- browser.
create or replace function leads.visitor_thread(p_token uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'lead_id', l.id,
    'is_visitor', l.is_visitor,
    'lead', leads.lead_card(l),
    'events', leads.thread_events(l.id),
    'pending_approval', (select jsonb_build_object('id', a.id, 'reply', m.body, 'created_at', a.created_at)
                         from leads.approvals a join leads.messages m on m.id = a.message_id
                         where a.lead_id = l.id and a.status = 'pending' order by a.id desc limit 1),
    'visitor_messages', (select count(*) from leads.messages m where m.lead_id = l.id and m.direction = 'in'),
    'clock', (select jsonb_build_object('mode', s.clock_mode, 'minutes_per_day', s.demo_minutes_per_day,
                                        'retention_hours', s.visitor_retention_hours)
              from leads.settings s where s.id = 1)
  )
  from leads.leads l
  where l.public_token = p_token
$$;

-- The public owner view: numbers across every lead (no details), and the
-- sample leads.
create or replace function leads.owner_overview()
returns jsonb language sql stable set search_path = '' as $$
  with first_reply as (
    select l.id,
           extract(epoch from (
             (select min(d.created_at) from leads.decisions d where d.lead_id = l.id and d.trigger = 'message')
             - (select min(m.created_at) from leads.messages m where m.lead_id = l.id and m.direction = 'in')
           )) as seconds
    from leads.leads l
  ),
  counted as (
    select * from leads.leads where coalesce(end_state, '') <> 'spam'
  )
  select jsonb_build_object(
    'metrics', jsonb_build_object(
      'leads', (select count(*) from leads.leads),
      'median_first_reply_seconds', (select percentile_cont(0.5) within group (order by seconds)
                                     from first_reply where seconds is not null),
      'booked_pct', (select round(100.0 * count(*) filter (where status = 'booked') / nullif(count(*), 0)) from counted),
      'handed_off_pct', (select round(100.0 * count(*) filter (where status = 'handed_off') / nullif(count(*), 0)) from counted),
      'follow_ups_sent', (select count(*) from leads.decisions d
                          where d.trigger = 'follow_up' and d.final_action <> 'close'),
      'waiting_approval', (select count(*) from leads.approvals a where a.status = 'pending')
    ),
    'samples', coalesce((
      select jsonb_agg(leads.lead_card(l) || jsonb_build_object('id', l.id,
               'messages', (select count(*) from leads.messages m where m.lead_id = l.id and m.status in ('received', 'sent')),
               'last_activity', greatest(l.updated_at, (select max(m.created_at) from leads.messages m where m.lead_id = l.id)))
             order by l.created_at desc)
      from leads.leads l where l.is_sample
    ), '[]'::jsonb),
    'clock', (select jsonb_build_object('mode', s.clock_mode, 'minutes_per_day', s.demo_minutes_per_day)
              from leads.settings s where s.id = 1)
  )
$$;

-- One sample lead's timeline for the owner view. Null for anything that
-- isn't a sample lead.
create or replace function leads.owner_lead(p_lead_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('lead', leads.lead_card(l), 'facts', l.facts, 'events', leads.thread_events(l.id))
  from leads.leads l
  where l.id = p_lead_id and l.is_sample
$$;

-- Counts for the public demo limits: leads from this visitor today, AI calls
-- across the whole demo today (an agent turn is 2 calls, a follow-up 1), and,
-- for a thread, how many messages the visitor has sent.
create or replace function leads.demo_usage(p_ip_hash text, p_token uuid default null)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'leads_today', (select count(*) from leads.leads l
                    where l.is_visitor and l.ip_hash = p_ip_hash and l.created_at > now() - interval '24 hours'),
    'ai_calls_today', (select coalesce(sum(case when d.trigger = 'message' then 2 else 1 end), 0)
                       from leads.decisions d where d.created_at > now() - interval '24 hours'),
    'thread', (select jsonb_build_object(
                 'lead_id', l.id,
                 'is_visitor', l.is_visitor,
                 'visitor_messages', (select count(*) from leads.messages m where m.lead_id = l.id and m.direction = 'in'))
               from leads.leads l where p_token is not null and l.public_token = p_token)
  )
$$;

-- The visitor plays the owner: approve or reject the price waiting in their
-- own thread. Visitor leads only, so nobody can approve a sample or email
-- lead from the site. Returns what resolve_approval returns, plus the Slack
-- message to update.
create or replace function leads.visitor_resolve_approval(p_token uuid, p_approved boolean)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_lead_id   uuid;
  v_approval  leads.approvals;
begin
  select l.id into v_lead_id from leads.leads l where l.public_token = p_token and l.is_visitor;
  if v_lead_id is null then
    return jsonb_build_object('changed', false, 'error', 'not_found');
  end if;
  select * into v_approval from leads.approvals a
  where a.lead_id = v_lead_id and a.status = 'pending' order by a.id desc limit 1;
  if v_approval.id is null then
    return jsonb_build_object('changed', false, 'error', 'nothing_pending');
  end if;
  return leads.resolve_approval(v_approval.id, p_approved, 'a demo visitor playing the owner')
         || jsonb_build_object('approval_id', v_approval.id, 'slack_ts', v_approval.slack_ts);
end $$;

revoke execute on function
  leads.thread_events(uuid),
  leads.next_follow_up_at(leads.leads),
  leads.lead_card(leads.leads),
  leads.visitor_thread(uuid),
  leads.owner_overview(),
  leads.owner_lead(uuid),
  leads.demo_usage(text, uuid),
  leads.visitor_resolve_approval(uuid, boolean)
from public, anon, authenticated;
