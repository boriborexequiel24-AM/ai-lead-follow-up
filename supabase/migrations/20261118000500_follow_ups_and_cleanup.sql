-- Phase 7: follow-ups, the demo clock and the hourly cleanup.
--
--   settings            one row: the clock (demo or real), follow-up gaps,
--                       how long visitor leads are kept
--   day_length          how long a "day" is on the current clock
--   claim_follow_ups    leads whose next follow-up is due, claimed so two
--                       scheduler runs can never both follow up the same lead
--   release_scheduled   follow-ups held back by quiet hours whose time has come
--   cleanup             delete visitor leads past their retention, refresh slots
--
-- check_decision is redefined so quiet hours only apply on the real clock, and
-- get_agent_context so open slots carry a ready-made label (see below).
--
-- Safe to run more than once.

create table if not exists leads.settings (
  id                       smallint primary key default 1 check (id = 1),
  -- demo: a day passes in demo_minutes_per_day minutes, so visitors see the
  -- whole follow-up sequence. real: normal days, for a real client.
  clock_mode               text not null default 'demo' check (clock_mode in ('demo', 'real')),
  demo_minutes_per_day     numeric not null default 1 check (demo_minutes_per_day > 0),
  -- Days to wait after the last unanswered agent message, by follow-ups sent
  -- so far: 1st follow-up after 1 day, 2nd 2 days later (day 3), 3rd 4 days
  -- later (day 7). After the 3rd, the lead closes as no_response 3 days later.
  follow_up_gaps_days      numeric[] not null default '{1, 2, 4, 3}',
  visitor_retention_hours  int not null default 24 check (visitor_retention_hours > 0),
  updated_at               timestamptz not null default now()
);
insert into leads.settings (id) values (1) on conflict (id) do nothing;
revoke all on leads.settings from anon, authenticated;
alter table leads.settings enable row level security;

alter table leads.leads add column if not exists follow_up_claimed_at timestamptz;

create or replace function leads.day_length()
returns interval language sql stable set search_path = '' as $$
  select case when s.clock_mode = 'demo'
              then make_interval(secs => (s.demo_minutes_per_day * 60)::double precision)
              else interval '1 day' end
  from leads.settings s where s.id = 1
$$;

-- Leads whose next follow-up is due, oldest first. Each one is claimed for 5
-- minutes so an overlapping scheduler run skips it. Returns what workflow 4
-- needs: the lead, which follow-up this is (4 means close as no_response),
-- the stored facts, and where to email it.
create or replace function leads.claim_follow_ups(p_limit int default 10)
returns jsonb language sql set search_path = '' as $$
  with settings as (
    select s.follow_up_gaps_days as gaps, leads.day_length() as day from leads.settings s where s.id = 1
  ),
  due as (
    select l.id
    from leads.leads l, settings s
    where l.status = 'active'
      and l.end_state is null
      and l.awaiting_reply_since is not null
      and (l.follow_up_claimed_at is null or l.follow_up_claimed_at < now() - interval '5 minutes')
      and l.awaiting_reply_since
          + (s.gaps[least(l.follow_ups_sent, cardinality(s.gaps) - 1) + 1])::double precision * s.day <= now()
    order by l.awaiting_reply_since
    limit p_limit
    for update of l skip locked
  ),
  claimed as (
    update leads.leads l set follow_up_claimed_at = now()
    from due where l.id = due.id
    returning l.id, l.follow_ups_sent, l.facts, l.email, l.email_thread_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'lead_id', c.id,
    'follow_up_number', c.follow_ups_sent + 1,
    'facts', c.facts,
    'email', c.email,
    'thread_id', c.email_thread_id,
    'subject', (select m.subject from leads.messages m
                where m.lead_id = c.id and m.direction = 'in' order by m.created_at, m.id limit 1)
  )), '[]'::jsonb)
  from claimed c
$$;

-- Follow-ups that waited for quiet hours to end: mark them sent and return
-- them so workflow 4 can email the email leads.
create or replace function leads.release_scheduled()
returns jsonb language sql set search_path = '' as $$
  with released as (
    update leads.messages m set status = 'sent', created_at = now()
    where m.status = 'scheduled' and m.send_after <= now()
    returning m.id, m.lead_id, m.channel, m.body
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'message_id', r.id,
    'lead_id', r.lead_id,
    'channel', r.channel,
    'reply', r.body,
    'email', l.email,
    'thread_id', l.email_thread_id,
    'subject', (select m.subject from leads.messages m
                where m.lead_id = r.lead_id and m.direction = 'in' order by m.created_at, m.id limit 1)
  )), '[]'::jsonb)
  from released r join leads.leads l on l.id = r.lead_id
$$;

-- Hourly: delete visitor leads past their retention (their messages,
-- decisions and approvals go with them, and their booked slots open up
-- again), then make sure the coming week has slots.
create or replace function leads.cleanup()
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_deleted int;
  v_added int;
begin
  delete from leads.leads l
  using leads.settings s
  where s.id = 1 and l.is_visitor
    and l.created_at < now() - make_interval(hours => s.visitor_retention_hours);
  get diagnostics v_deleted = row_count;

  update leads.slots set booked_at = null where booked_lead_id is null and booked_at is not null;
  v_added := leads.refresh_slots();

  return jsonb_build_object('visitor_leads_deleted', v_deleted, 'slots_added', v_added);
end $$;

-- ---------- What the AI sees (redefined) ----------
-- Found while testing follow-ups: the model sometimes got the weekday of a
-- date wrong ("martes 7 de octubre" for a Wednesday). Every open slot now
-- comes with a label worked out here, like "Wednesday Oct 7 at 8am", plus
-- today's date, so the AI never has to calculate a weekday.

-- A slot as the customer reads it, e.g. "Wednesday Oct 7 at 8am".
create or replace function leads.slot_label(p_ts timestamptz)
returns text language sql stable set search_path = '' as $$
  select to_char(p_ts at time zone c.timezone, 'FMDay Mon FMDD "at" FMHH12am')
  from leads.company_profile c where c.id = 1
$$;


-- The exact input for the read and decide prompts (see agent/*.md), so n8n
-- sends the same shape the eval tests. Also returns service_area_zips for the
-- zip rule between the two steps.
create or replace function leads.get_agent_context(p_lead_id uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'lead', jsonb_strip_nulls(jsonb_build_object(
      'source', l.source, 'name', l.name, 'email', l.email, 'phone', l.phone, 'zip', l.zip,
      'subject', (select m.subject from leads.messages m
                  where m.lead_id = l.id and m.direction = 'in' order by m.created_at, m.id limit 1)
    )),
    'conversation', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'from', case m.direction when 'in' then 'lead' else 'agent' end,
        'at', leads.iso_local(m.created_at),
        'text', m.body,
        'action', d.final_action,
        'offered_slots', case when cardinality(d.offered_slots) > 0 and d.final_action = 'offer_booking'
                              then (select jsonb_agg(leads.iso_local(s)) from unnest(d.offered_slots) s) end,
        'approved', case when d.final_action = 'draft_price' then true end
      )) order by m.created_at, m.id)
      from leads.messages m
      left join leads.decisions d on d.id = m.decision_id
      where m.lead_id = l.id and m.status in ('received', 'sent')
    ), '[]'::jsonb),
    'company', jsonb_build_object(
      'name', c.name, 'phone', c.phone, 'emergency_phone', c.emergency_phone,
      'business_hours', c.business_hours, 'service_area_name', c.service_area_name,
      'services_offered', c.services_offered, 'services_not_offered', c.services_not_offered,
      'timezone', c.timezone
    ),
    'faq', (select jsonb_agg(jsonb_build_object('topic', f.topic, 'answer', f.answer) order by f.id) from leads.faq f),
    'price_sheet', (select jsonb_agg(jsonb_build_object(
                      'code', p.code, 'trade', p.trade, 'job', p.job,
                      'low_price', p.low_price, 'high_price', p.high_price, 'notes', p.notes) order by p.id)
                    from leads.price_items p),
    'service_area_zips', to_jsonb(c.service_area_zips),
    'now', leads.iso_local(now()),
    'today', to_char(now() at time zone c.timezone, 'FMDay Mon FMDD, YYYY'),
    'open_slots', coalesce((select jsonb_agg(jsonb_build_object('time', u.s, 'label', leads.slot_label(leads.try_timestamptz(u.s)))
                                             order by u.n)
                            from unnest(leads.open_slots()) with ordinality as u(s, n)), '[]'::jsonb)
  )
  from leads.leads l
  cross join leads.company_profile c
  where l.id = p_lead_id and c.id = 1
$$;

-- ---------- The guardrails ----------

-- Check one agent decision before anything is sent. Returns:
--   final_action    what actually happens (the AI's pick, or hand_off / close)
--   end_state       for closing actions
--   reply           what to send ('' = nothing)
--   needs_approval  true for prices: the reply waits for the owner in Slack
--   send_after      set when a follow-up falls in quiet hours
--   violations      what was wrong; any violation turns the action into hand_off
create or replace function leads.check_decision(
  p_lead_id   uuid,
  p_trigger   text,
  p_decision  jsonb,
  p_now       timestamptz default now()
) returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_lead        leads.leads;
  v_company     leads.company_profile;
  v_action      text := p_decision->>'action';
  v_reply       text := coalesce(p_decision->>'reply', '');
  v_violations  text[] := '{}';
  v_send_after  timestamptz;
  v_last_in     text;
  v_price       leads.price_items;
  v_amount      numeric;
  v_slot_text   text;
  v_slot        timestamptz;
  v_local       time;
  v_end_state   text;
begin
  select * into v_lead from leads.leads where id = p_lead_id;
  if not found then
    raise exception 'lead % not found', p_lead_id;
  end if;
  select * into v_company from leads.company_profile where id = 1;

  -- House style: no em dashes in anything the company sends.
  v_reply := btrim(regexp_replace(v_reply, '\s*' || chr(8212) || '\s*', ', ', 'g'));

  -- Unsubscribed means nothing, ever. Handed off means a person is in charge.
  if v_lead.end_state = 'unsubscribed' then
    return jsonb_build_object('final_action', 'close', 'end_state', 'unsubscribed', 'reply', '',
      'needs_approval', false, 'send_after', null, 'violations', '[]'::jsonb);
  end if;
  if v_lead.status = 'handed_off' then
    return jsonb_build_object('final_action', 'hand_off', 'end_state', 'handed_off', 'reply', '',
      'needs_approval', false, 'send_after', null, 'violations', '[]'::jsonb);
  end if;

  -- A stop request wins over whatever the agent picked. Matches clear
  -- requests only, so "the water won't stop" doesn't count.
  select body into v_last_in from leads.messages
  where lead_id = p_lead_id and direction = 'in' order by created_at desc, id desc limit 1;
  if p_trigger = 'message' and v_last_in ~* (
       '^\s*(stop|unsubscribe)\W*$'
    || '|unsubscribe'
    || '|stop (emailing|contacting|messaging|texting|sending|writing)'
    || '|remove me from'
    || '|(don''t|do not) (email|contact|message|text) me') then
    if v_action <> 'close' then
      v_violations := v_violations || 'lead asked to stop but the agent did not close'::text;
    end if;
    return jsonb_build_object('final_action', 'close', 'end_state', 'unsubscribed', 'reply', '',
      'needs_approval', false, 'send_after', null, 'violations', to_jsonb(v_violations));
  end if;

  -- At most 4 unanswered messages: the first reply plus 3 follow-ups.
  if p_trigger = 'follow_up' and v_lead.follow_ups_sent >= 3 then
    return jsonb_build_object('final_action', 'close', 'end_state', 'no_response', 'reply', '',
      'needs_approval', false, 'send_after', null, 'violations', '[]'::jsonb);
  end if;

  -- The reply itself.
  if v_action <> 'close' and v_reply = '' then
    v_violations := v_violations || 'empty reply'::text;
  end if;
  if length(v_reply) > 1500 then
    v_violations := v_violations || 'reply too long'::text;
  end if;
  if v_action <> 'draft_price' and v_reply ~ '\$\s*\d' then
    v_violations := v_violations || 'dollar amount without owner approval'::text;
  end if;

  -- Prices must come from the sheet, inside its range.
  if v_action = 'draft_price' then
    select * into v_price from leads.price_items where code = p_decision->>'price_code';
    if not found then
      v_violations := v_violations || 'price_code is not on the price sheet'::text;
    else
      for v_amount in
        select replace(t.m[1], ',', '')::numeric
        from regexp_matches(v_reply, '\$\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', 'g') as t(m)
      loop
        if v_amount < v_price.low_price or v_amount > v_price.high_price then
          v_violations := v_violations || ('price outside the sheet range: $' || v_amount)::text;
        end if;
      end loop;
    end if;
  end if;

  -- Slots must be real, open and in the future.
  if v_action = 'offer_booking'
     and jsonb_array_length(coalesce(p_decision->'offered_slots', '[]'::jsonb)) not between 1 and 3 then
    v_violations := v_violations || 'offer_booking needs 1 to 3 slots'::text;
  end if;
  for v_slot_text in select jsonb_array_elements_text(coalesce(p_decision->'offered_slots', '[]'::jsonb)) loop
    v_slot := leads.try_timestamptz(v_slot_text);
    if v_slot is null or not exists (
      select 1 from leads.slots s where s.starts_at = v_slot and s.booked_lead_id is null and s.starts_at > p_now
    ) then
      v_violations := v_violations || ('offered a slot that is not open: ' || v_slot_text)::text;
    end if;
  end loop;

  -- A booking must be an open slot this lead was actually offered.
  if v_action = 'confirm_booking' then
    v_slot := leads.try_timestamptz(p_decision->>'slot');
    if v_slot is null then
      v_violations := v_violations || 'confirm_booking without a valid slot'::text;
    elsif not exists (select 1 from leads.slots s
                      where s.starts_at = v_slot and s.starts_at > p_now
                        and (s.booked_lead_id is null or s.booked_lead_id = p_lead_id)) then
      v_violations := v_violations || 'slot is no longer open'::text;
    elsif not exists (select 1 from leads.decisions d
                      where d.lead_id = p_lead_id and d.final_action = 'offer_booking'
                        and v_slot = any (d.offered_slots)) then
      v_violations := v_violations || 'slot was never offered to this lead'::text;
    end if;
  end if;

  -- Any violation: nothing the AI wrote is sent, the owner takes over, and the
  -- customer gets a safe holding message.
  if cardinality(v_violations) > 0 then
    return jsonb_build_object(
      'final_action', 'hand_off',
      'end_state', 'handed_off',
      'reply', case
        when p_trigger <> 'message' then ''
        when v_action = 'escalate_emergency'
          then 'Please call our emergency line now at ' || v_company.emergency_phone
               || '. The owner has been alerted and will call you right away.' || chr(10) || chr(10) || v_company.name
        else 'Thanks for your message. The owner will get back to you personally shortly.' || chr(10) || chr(10) || v_company.name
      end,
      'needs_approval', false,
      'send_after', null,
      'violations', to_jsonb(v_violations));
  end if;

  -- Quiet hours apply to follow-ups only. A reply to a message the lead just
  -- sent goes out right away: answering fast is the point. On the demo clock
  -- a "day" is a minute, so real-world quiet hours don't apply there.
  if p_trigger = 'follow_up' and (select clock_mode from leads.settings where id = 1) = 'real' then
    v_local := (p_now at time zone v_company.timezone)::time;
    if v_local >= v_company.quiet_hours_start or v_local < v_company.quiet_hours_end then
      v_send_after := (((p_now at time zone v_company.timezone)::date
                        + case when v_local >= v_company.quiet_hours_start then 1 else 0 end)
                       + v_company.quiet_hours_end) at time zone v_company.timezone;
    end if;
  end if;

  v_end_state := case v_action
    when 'close' then coalesce(p_decision->>'end_state', 'not_interested')
    when 'decline' then 'declined'
    when 'hand_off' then 'handed_off'
    when 'escalate_emergency' then 'handed_off'
    when 'confirm_booking' then 'booked'
  end;

  return jsonb_build_object(
    'final_action', v_action,
    'end_state', v_end_state,
    'reply', v_reply,
    'needs_approval', v_action = 'draft_price',
    'send_after', v_send_after,
    'violations', '[]'::jsonb);
end $$;

revoke execute on function
  leads.day_length(),
  leads.claim_follow_ups(int),
  leads.release_scheduled(),
  leads.cleanup(),
  leads.slot_label(timestamptz),
  leads.get_agent_context(uuid),
  leads.check_decision(uuid, text, jsonb, timestamptz)
from public, anon, authenticated;
