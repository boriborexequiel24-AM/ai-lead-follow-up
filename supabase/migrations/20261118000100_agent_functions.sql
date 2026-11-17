-- Phase 4: the guardrails and the conversation loop.
--
-- n8n stays thin. One agent turn is:
--   1. receive_message     store the incoming message (finds the lead, or makes one)
--   2. get_agent_context   the exact JSON the read and decide prompts expect
--   3. (n8n) read step, zip rule, decide step
--   4. apply_decision      run the guardrails, store the decision, the reply and
--                          any booking, and update the lead
-- check_decision holds every guardrail rule and can be tested on its own.
--
-- Safe to run more than once.

-- ---------- Helpers ----------

-- A timestamp as ISO text in the company's timezone, e.g. 2026-04-29T15:00:00-06:00.
create or replace function leads.iso_local(p_ts timestamptz)
returns text language sql stable set search_path = '' as $$
  select to_char(p_ts at time zone c.timezone, 'YYYY-MM-DD"T"HH24:MI:SS')
         || case when o.off < interval '0' then '-' else '+' end
         || to_char(case when o.off < interval '0' then -o.off else o.off end, 'HH24:MI')
  from leads.company_profile c
  cross join lateral (select (p_ts at time zone c.timezone) - (p_ts at time zone 'UTC') as off) o
  where c.id = 1
$$;

-- Text to timestamp, or null instead of an error when the AI writes something odd.
create or replace function leads.try_timestamptz(p text)
returns timestamptz language plpgsql stable set search_path = '' as $$
begin
  return p::timestamptz;
exception when others then
  return null;
end $$;

-- ---------- Visit slots ----------

-- Make sure the next p_days working days have slots (Mon-Fri 8, 10, 1, 3;
-- Sat 8, 10; closed Sunday) and drop unbooked slots in the past.
-- Returns how many slots were added.
create or replace function leads.refresh_slots(p_days int default 6)
returns int language plpgsql set search_path = '' as $$
declare
  v_tz text;
  v_day date;
  v_hours int[];
  v_hour int;
  v_added int := 0;
  v_days_done int := 0;
begin
  select timezone into v_tz from leads.company_profile where id = 1;
  delete from leads.slots where starts_at < now() and booked_lead_id is null;

  v_day := (now() at time zone v_tz)::date;
  while v_days_done < p_days loop
    v_day := v_day + 1;
    continue when extract(isodow from v_day) = 7;
    v_hours := case when extract(isodow from v_day) = 6 then array[8, 10] else array[8, 10, 13, 15] end;
    foreach v_hour in array v_hours loop
      insert into leads.slots (starts_at)
      values ((v_day + make_time(v_hour, 0, 0)) at time zone v_tz)
      on conflict do nothing;
      if found then v_added := v_added + 1; end if;
    end loop;
    v_days_done := v_days_done + 1;
  end loop;
  return v_added;
end $$;

-- Open future slots, soonest first, as ISO text.
create or replace function leads.open_slots(p_limit int default 24)
returns text[] language sql stable set search_path = '' as $$
  select coalesce(array_agg(leads.iso_local(s.starts_at) order by s.starts_at), '{}')
  from (
    select starts_at from leads.slots
    where booked_lead_id is null and starts_at > now()
    order by starts_at limit p_limit
  ) s
$$;

-- ---------- 1. Receiving a message ----------

-- Store an incoming message. Finds the lead (by p_lead_id for a reply in the
-- web thread, or the same email/phone within 30 days for non-visitors) or
-- creates one. Visitors always get a new lead, so two visitors typing the
-- same fake email can never see each other's thread.
create or replace function leads.receive_message(
  p_source       text,
  p_channel      text,
  p_body         text,
  p_name         text default null,
  p_email        text default null,
  p_phone        text default null,
  p_zip          text default null,
  p_subject      text default null,
  p_external_id  text default null,
  p_lead_id      uuid default null,
  p_is_visitor   boolean default false,
  p_ip_hash      text default null
) returns jsonb language plpgsql set search_path = '' as $$
declare
  v_lead leads.leads;
  v_is_new boolean := false;
begin
  -- The same email is never processed twice.
  if p_external_id is not null and exists (select 1 from leads.messages where external_id = p_external_id) then
    return jsonb_build_object('duplicate', true);
  end if;

  if p_lead_id is not null then
    select * into v_lead from leads.leads where id = p_lead_id;
    if not found then
      raise exception 'lead % not found', p_lead_id;
    end if;
  elsif not p_is_visitor then
    select * into v_lead from leads.leads l
    where not l.is_visitor
      and l.created_at > now() - interval '30 days'
      and ((p_email is not null and lower(l.email) = lower(p_email))
        or (coalesce(p_phone, '') <> '' and l.phone = p_phone))
    order by l.created_at desc
    limit 1;
  end if;

  if v_lead.id is null then
    insert into leads.leads (source, name, email, phone, zip, is_visitor, ip_hash)
    values (p_source, p_name, p_email, nullif(p_phone, ''), nullif(p_zip, ''), p_is_visitor, p_ip_hash)
    returning * into v_lead;
    v_is_new := true;
  else
    -- The lead wrote back: follow-ups start over, and a closed conversation
    -- reopens unless they unsubscribed or it was spam.
    update leads.leads set
      awaiting_reply_since = null,
      follow_ups_sent = 0,
      zip = coalesce(zip, nullif(p_zip, '')),
      status = case when status = 'closed' and coalesce(end_state, '') not in ('unsubscribed', 'spam')
                    then 'active' else status end,
      end_state = case when status = 'closed' and coalesce(end_state, '') not in ('unsubscribed', 'spam')
                       then null else end_state end,
      updated_at = now()
    where id = v_lead.id
    returning * into v_lead;
  end if;

  insert into leads.messages (lead_id, direction, channel, subject, body, status, external_id)
  values (v_lead.id, 'in', p_channel, p_subject, p_body, 'received', p_external_id);

  return jsonb_build_object(
    'duplicate', false,
    'lead_id', v_lead.id,
    'public_token', v_lead.public_token,
    'is_new', v_is_new,
    -- After a hand-off a person is in charge, and unsubscribed or spam leads get nothing.
    'agent_should_reply', v_lead.status <> 'handed_off'
                          and coalesce(v_lead.end_state, '') not in ('unsubscribed', 'spam')
  );
end $$;

-- ---------- 2. What the AI sees ----------

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
    'open_slots', to_jsonb(leads.open_slots())
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
                      where s.starts_at = v_slot and s.booked_lead_id is null and s.starts_at > p_now) then
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
  -- sent goes out right away: answering fast is the point.
  if p_trigger = 'follow_up' then
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

-- ---------- 4. Applying a decision ----------

-- Run the guardrails, then store everything in one transaction: the decision,
-- the outgoing message (sent, scheduled, or waiting for approval), the
-- booking, and the lead's new status. Returns what n8n needs to send the
-- email and post to Slack.
create or replace function leads.apply_decision(
  p_lead_id   uuid,
  p_trigger   text,
  p_facts     jsonb,
  p_decision  jsonb,
  p_model     text default null
) returns jsonb language plpgsql set search_path = '' as $$
declare
  v_check        jsonb;
  v_final        text;
  v_reply        text;
  v_send_after   timestamptz;
  v_decision_id  bigint;
  v_message_id   bigint;
  v_approval_id  bigint;
  v_status       text;
  v_channel      text;
  v_slot         timestamptz;
  v_public_token uuid;
begin
  -- One decision at a time per lead.
  perform 1 from leads.leads where id = p_lead_id for update;

  v_check := leads.check_decision(p_lead_id, p_trigger, p_decision);
  v_final := v_check->>'final_action';
  v_reply := v_check->>'reply';
  v_send_after := (v_check->>'send_after')::timestamptz;

  insert into leads.decisions (
    lead_id, trigger, facts, action, reason, reply, price_code, offered_slots, slot,
    end_state, owner_note, final_action, violations, model)
  values (
    p_lead_id, p_trigger, p_facts,
    p_decision->>'action',
    coalesce(p_decision->>'reason', ''),
    coalesce(p_decision->>'reply', ''),
    p_decision->>'price_code',
    coalesce(array(
      select leads.try_timestamptz(x)
      from jsonb_array_elements_text(coalesce(p_decision->'offered_slots', '[]'::jsonb)) x
      where leads.try_timestamptz(x) is not null), '{}'),
    leads.try_timestamptz(p_decision->>'slot'),
    v_check->>'end_state',
    nullif(p_decision->>'owner_note', ''),
    v_final,
    array(select jsonb_array_elements_text(v_check->'violations')),
    p_model)
  returning id into v_decision_id;

  -- Email leads get email; form leads see replies in their web thread.
  select case when channel = 'email' then 'email' else 'web' end into v_channel
  from leads.messages where lead_id = p_lead_id and direction = 'in'
  order by created_at desc, id desc limit 1;

  if v_reply <> '' then
    v_status := case
      when (v_check->>'needs_approval')::boolean then 'pending_approval'
      when v_send_after is not null then 'scheduled'
      else 'sent' end;
    insert into leads.messages (lead_id, direction, channel, body, status, send_after, decision_id)
    values (p_lead_id, 'out', coalesce(v_channel, 'web'), v_reply, v_status, v_send_after, v_decision_id)
    returning id into v_message_id;

    if v_status = 'pending_approval' then
      insert into leads.approvals (lead_id, decision_id, message_id)
      values (p_lead_id, v_decision_id, v_message_id)
      returning id into v_approval_id;
    end if;
  end if;

  if v_final = 'confirm_booking' then
    v_slot := leads.try_timestamptz(p_decision->>'slot');
    update leads.slots set booked_lead_id = p_lead_id, booked_at = now()
    where starts_at = v_slot and booked_lead_id is null;
    if not found then
      raise exception 'slot % was just taken by someone else', v_slot;
    end if;
  end if;

  update leads.leads set
    facts = p_facts,
    summary = coalesce(p_facts->>'summary', summary),
    zip = coalesce(zip, p_facts->>'zip'),
    status = case v_final
      when 'close' then 'closed'
      when 'decline' then 'closed'
      when 'hand_off' then 'handed_off'
      when 'escalate_emergency' then 'handed_off'
      when 'confirm_booking' then 'booked'
      when 'draft_price' then 'waiting_approval'
      else 'active' end,
    end_state = v_check->>'end_state',
    -- Follow-ups only chase questions and offers the lead hasn't answered.
    awaiting_reply_since = case
      when v_status in ('sent', 'scheduled') and v_final in ('ask_question', 'offer_booking', 'answer_question')
      then coalesce(v_send_after, now()) end,
    follow_ups_sent = follow_ups_sent
      + case when p_trigger = 'follow_up' and v_message_id is not null then 1 else 0 end,
    updated_at = now()
  where id = p_lead_id
  returning public_token into v_public_token;

  return jsonb_build_object(
    'decision_id', v_decision_id,
    'final_action', v_final,
    'reply', v_reply,
    'message_id', v_message_id,
    'message_status', v_status,
    'channel', v_channel,
    'send_after', v_send_after,
    'approval_id', v_approval_id,
    'violations', v_check->'violations',
    'owner_note', nullif(p_decision->>'owner_note', ''),
    'public_token', v_public_token);
end $$;

-- ---------- Access ----------
-- Only the service role (n8n, server code) may run these.
revoke execute on function
  leads.iso_local(timestamptz),
  leads.try_timestamptz(text),
  leads.refresh_slots(int),
  leads.open_slots(int),
  leads.receive_message(text, text, text, text, text, text, text, text, text, uuid, boolean, text),
  leads.get_agent_context(uuid),
  leads.check_decision(uuid, text, jsonb, timestamptz),
  leads.apply_decision(uuid, text, jsonb, jsonb, text)
from public, anon, authenticated;

-- Fill the first week of slots.
select leads.refresh_slots();
