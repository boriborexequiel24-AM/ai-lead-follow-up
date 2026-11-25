-- Fixes from the code review on 2026-11-25.
--
--   receive_message    an email whose AI call failed can be tried again (up to 3
--                      times, 5 minutes apart) instead of counting as handled;
--                      a reply cancels a follow-up held for quiet hours
--   email_states       tells email intake which messages are done, busy or due
--                      another try
--   check_decision     emergencies must include the emergency line; prices are
--                      caught without a dollar sign too; the stop rule reads
--                      phone apostrophes and leaves mixed messages alone; a
--                      follow-up can only offer times, ask, or close
--   apply_decision     a booked lead stays booked when they ask something; a
--                      cancelled visit frees its time; a follow-up is dropped if
--                      the lead replied while it was being written; a price
--                      still waiting is withdrawn when the conversation moves on
--   resolve_approval   never sends a price into a conversation that has ended,
--                      and never takes a booked lead away from their booking
--
-- Safe to run more than once.

-- ---------- Columns and allowed values ----------

alter table leads.messages add column if not exists agent_attempts int not null default 0;
alter table leads.messages add column if not exists agent_attempted_at timestamptz;

-- withdrawn: written but never sent, because the conversation moved on.
alter table leads.messages drop constraint if exists messages_status_check;
alter table leads.messages add constraint messages_status_check
  check (status in ('received', 'sent', 'scheduled', 'pending_approval', 'rejected', 'withdrawn'));
alter table leads.approvals drop constraint if exists approvals_status_check;
alter table leads.approvals add constraint approvals_status_check
  check (status in ('pending', 'approved', 'rejected', 'withdrawn'));

-- ---------- Receiving a message ----------

-- Where an incoming email stands:
--   done   answered, doesn't need an answer, or given up after 3 tries
--   busy   the agent started on it less than 5 minutes ago
--   retry  the agent failed on it and it's time to try again
create or replace function leads.email_state(p_message leads.messages)
returns text language sql stable set search_path = '' as $$
  select case
    when l.status = 'handed_off' or coalesce(l.end_state, '') in ('unsubscribed', 'spam') then 'done'
    when exists (select 1 from leads.decisions d
                 where d.lead_id = l.id and d.trigger = 'message'
                   and d.created_at >= p_message.created_at) then 'done'
    when coalesce(p_message.agent_attempted_at, p_message.created_at) > now() - interval '5 minutes' then 'busy'
    when p_message.agent_attempts < 3 then 'retry'
    else 'done'
  end
  from leads.leads l where l.id = p_message.lead_id
$$;

-- The state of each email message already stored. Ones not listed are new.
create or replace function leads.email_states(p_ids text[])
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('external_id', m.external_id, 'state', leads.email_state(m))), '[]'::jsonb)
  from leads.messages m
  where m.external_id = any (p_ids)
$$;

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
  v_lead     leads.leads;
  v_message  leads.messages;
  v_is_new   boolean := false;
begin
  -- The same email is never processed twice, unless the agent failed on it
  -- the last time and it's due another try.
  if p_external_id is not null then
    select * into v_message from leads.messages where external_id = p_external_id for update;
    if found then
      if leads.email_state(v_message) <> 'retry' then
        return jsonb_build_object('duplicate', true);
      end if;
      update leads.messages set agent_attempts = agent_attempts + 1, agent_attempted_at = now()
      where id = v_message.id
      returning * into v_message;
      select * into v_lead from leads.leads where id = v_message.lead_id;
      return jsonb_build_object(
        'duplicate', false, 'lead_id', v_lead.id, 'public_token', v_lead.public_token,
        'is_new', false, 'agent_should_reply', true, 'attempts', v_message.agent_attempts);
    end if;
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
    -- A follow-up waiting for quiet hours to end is out of date now.
    update leads.messages set status = 'withdrawn'
    where lead_id = v_lead.id and status = 'scheduled';
  end if;

  insert into leads.messages (lead_id, direction, channel, subject, body, status, external_id,
                              agent_attempts, agent_attempted_at)
  values (v_lead.id, 'in', p_channel, p_subject, p_body, 'received', p_external_id, 1, now());

  return jsonb_build_object(
    'duplicate', false,
    'lead_id', v_lead.id,
    'public_token', v_lead.public_token,
    'is_new', v_is_new,
    'attempts', 1,
    -- After a hand-off a person is in charge, and unsubscribed or spam leads get nothing.
    'agent_should_reply', v_lead.status <> 'handed_off'
                          and coalesce(v_lead.end_state, '') not in ('unsubscribed', 'spam')
  );
end $$;

-- ---------- Finding prices in a reply ----------

-- Does the text mention an amount of money, however it's written?
-- "$89", "89 dollars", "USD 1400", "1400 dólares", or a bare "1,400".
create or replace function leads.mentions_money(p text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p ~* ('[$€£]\s*[0-9]|[0-9]\s*[$€£]'
    || '|\m(usd|dollars?|bucks|d[oó]lares?)\M'
    || '|\m[0-9]{1,3}(,[0-9]{3})+\M(?!\s*(sq|square|feet|foot|ft|btu|gal|mile|hour))'), false)
$$;

-- Every amount in a price reply, including the second half of a range that
-- leaves its dollar sign out ("$1,400 to 2,200").
create or replace function leads.price_amounts(p text)
returns setof numeric language sql immutable set search_path = '' as $$
  select replace(t.m[1], ',', '')::numeric
  from unnest(array[
    '[$€£]\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    '\musd\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    '([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:usd|dollars?|bucks|d[oó]lares?)\M',
    '\m([0-9]{1,3}(?:,[0-9]{3})+)\M(?!\s*(?:sq|square|feet|foot|ft|btu|gal|mile|hour))',
    '[$€£]\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?\s*(?:to|through|a|hasta|-|–)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)(?![-0-9,A-Za-z])',
    '(?:between|entre)\s+[$€£]\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?\s+(?:and|y)\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)(?![-0-9,A-Za-z])'
  ]) as pat
  cross join lateral regexp_matches(p, pat, 'gi') as t(m)
  where t.m[1] is not null
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
  -- requests only, so "the water won't stop" doesn't count. Phones type a
  -- curly apostrophe, so make it a straight one first.
  if p_trigger = 'message' then
    select translate(body, chr(8217) || chr(8216), '''''') into v_last_in from leads.messages
    where lead_id = p_lead_id and direction = 'in' order by created_at desc, id desc limit 1;

    -- The whole message is a stop request.
    if v_last_in ~* '^\W*(please\W+)?(stop|unsubscribe|opt me out|opt out)(\W+(please|now|thanks|thank you))*\W*$' then
      if v_action <> 'close' then
        v_violations := v_violations || 'lead asked to stop but the agent did not close'::text;
      end if;
      return jsonb_build_object('final_action', 'close', 'end_state', 'unsubscribed', 'reply', '',
        'needs_approval', false, 'send_after', null, 'violations', to_jsonb(v_violations));
    end if;

    -- A stop request inside a longer message. An emergency is still an
    -- emergency, and "don't text me, call me" is for a person to handle.
    if v_action <> 'escalate_emergency' and v_last_in ~* (
         '\munsubscribe'
      || '|\mstop (emailing|contacting|messaging|texting|writing)\M'
      || '|\mstop sending (me|us|these|this|emails?|messages?|texts?|mail)\M'
      || '|\mremove me from\M'
      || '|\m(don''?t|do not) (email|contact|message|text|write) (me|us)\M') then
      if v_last_in ~* '\m(call|phone|ring) (me|us)\M'
         and v_last_in !~* '\m(don''?t|do not|never|or|nor|not|stop)\s+(ever\s+)?(call|phone|ring)' then
        return jsonb_build_object('final_action', 'hand_off', 'end_state', 'handed_off', 'reply', '',
          'needs_approval', false, 'send_after', null,
          'violations', jsonb_build_array('lead wants a phone call, not written messages'));
      end if;
      if v_action <> 'close' then
        v_violations := v_violations || 'lead asked to stop but the agent did not close'::text;
      end if;
      return jsonb_build_object('final_action', 'close', 'end_state', 'unsubscribed', 'reply', '',
        'needs_approval', false, 'send_after', null, 'violations', to_jsonb(v_violations));
    end if;
  end if;

  -- At most 4 unanswered messages: the first reply plus 3 follow-ups.
  if p_trigger = 'follow_up' and v_lead.follow_ups_sent >= 3 then
    return jsonb_build_object('final_action', 'close', 'end_state', 'no_response', 'reply', '',
      'needs_approval', false, 'send_after', null, 'violations', '[]'::jsonb);
  end if;

  -- A follow-up nobody asked for can't quote, book, decline or escalate.
  if p_trigger = 'follow_up' and v_action not in ('offer_booking', 'ask_question', 'close') then
    v_violations := v_violations || ('a follow-up cannot use ' || v_action)::text;
  end if;

  -- The reply itself.
  if v_action <> 'close' and v_reply = '' then
    v_violations := v_violations || 'empty reply'::text;
  end if;
  if length(v_reply) > 1500 then
    v_violations := v_violations || 'reply too long'::text;
  end if;
  if v_action <> 'draft_price' and leads.mentions_money(v_reply) then
    v_violations := v_violations || 'dollar amount without owner approval'::text;
  end if;

  -- An emergency reply must give the emergency line (however it's punctuated).
  if v_action = 'escalate_emergency'
     and position(regexp_replace(v_company.emergency_phone, '\D', '', 'g') in regexp_replace(v_reply, '\D', '', 'g')) = 0 then
    v_violations := v_violations || 'emergency reply without the emergency line'::text;
  end if;

  -- Prices must come from the sheet, inside its range.
  if v_action = 'draft_price' then
    select * into v_price from leads.price_items where code = p_decision->>'price_code';
    if not found then
      v_violations := v_violations || 'price_code is not on the price sheet'::text;
    else
      for v_amount in select distinct a from leads.price_amounts(v_reply) a loop
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
               || '. If you smell gas or anyone is in danger, leave the building first and call 911 from outside.'
               || ' The owner has been alerted and will call you right away.' || chr(10) || chr(10) || v_company.name
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

-- ---------- Applying a decision ----------

-- Run the guardrails, then store everything in one transaction: the decision,
-- the outgoing message (sent, scheduled, or waiting for approval), the
-- booking, and the lead's new status. Returns what n8n needs to send the
-- email and post to Slack. A follow-up the lead has overtaken by replying is
-- dropped: nothing is stored or sent, and 'stale' is true.
create or replace function leads.apply_decision(
  p_lead_id   uuid,
  p_trigger   text,
  p_facts     jsonb,
  p_decision  jsonb,
  p_model     text default null
) returns jsonb language plpgsql set search_path = '' as $$
declare
  v_lead         leads.leads;
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
  v_booked_at    timestamptz;
  v_lead_status  text;
  v_public_token uuid;
begin
  -- One decision at a time per lead.
  select * into v_lead from leads.leads where id = p_lead_id for update;

  -- The scheduler claimed this lead a few seconds ago. If they wrote back
  -- since (or were answered, booked or closed), the follow-up is out of date.
  if p_trigger = 'follow_up' and (
       v_lead.status <> 'active' or v_lead.end_state is not null or v_lead.awaiting_reply_since is null
       or v_lead.awaiting_reply_since > v_lead.follow_up_claimed_at) then
    return jsonb_build_object('stale', true, 'final_action', null, 'reply', '', 'message_status', null,
                              'violations', '[]'::jsonb, 'public_token', v_lead.public_token);
  end if;

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
    -- One booking per lead: picking another time moves the booking.
    update leads.slots set booked_lead_id = null, booked_at = null
    where booked_lead_id = p_lead_id and starts_at <> v_slot;
    update leads.slots set booked_lead_id = p_lead_id, booked_at = now()
    where starts_at = v_slot and (booked_lead_id is null or booked_lead_id = p_lead_id);
    if not found then
      raise exception 'slot % was just taken by someone else', v_slot;
    end if;
  elsif v_final = 'close' and coalesce(v_check->>'end_state', '') <> 'unsubscribed' then
    -- They don't need the visit any more, so someone else can have the time.
    -- An opt-out from messages isn't a cancellation: that visit stays, and
    -- n8n tells the owner about it.
    update leads.slots set booked_lead_id = null, booked_at = null
    where booked_lead_id = p_lead_id and starts_at > now();
  end if;

  select min(starts_at) into v_booked_at from leads.slots
  where booked_lead_id = p_lead_id and starts_at > now();

  -- A lead with a visit booked stays booked while they ask about other things.
  v_lead_status := case
    when v_final = 'close' then 'closed'
    when v_final in ('hand_off', 'escalate_emergency') then 'handed_off'
    when v_booked_at is not null then 'booked'
    when v_final = 'decline' then 'closed'
    when v_final = 'draft_price' then 'waiting_approval'
    else 'active' end;

  -- A price still waiting for the owner is out of date once the conversation
  -- ends, a person takes over, or a newer price replaces it.
  if v_lead_status in ('closed', 'handed_off') or v_approval_id is not null then
    with withdrawn as (
      update leads.approvals set status = 'withdrawn', decided_by = 'the conversation moved on', decided_at = now()
      where lead_id = p_lead_id and status = 'pending' and id is distinct from v_approval_id
      returning message_id
    )
    update leads.messages m set status = 'withdrawn' from withdrawn w where m.id = w.message_id;
  elsif v_lead_status = 'active'
        and exists (select 1 from leads.approvals a where a.lead_id = p_lead_id and a.status = 'pending') then
    -- Still waiting for the owner, so don't chase the lead meanwhile.
    v_lead_status := 'waiting_approval';
  end if;

  update leads.leads set
    facts = p_facts,
    summary = coalesce(p_facts->>'summary', summary),
    zip = coalesce(zip, p_facts->>'zip'),
    status = v_lead_status,
    end_state = case
      when v_lead_status = 'booked' then 'booked'
      when v_lead_status in ('closed', 'handed_off') then v_check->>'end_state' end,
    -- Follow-ups only chase questions and offers the lead hasn't answered.
    awaiting_reply_since = case
      when v_lead_status = 'active' and v_status in ('sent', 'scheduled')
           and v_final in ('ask_question', 'offer_booking', 'answer_question')
      then coalesce(v_send_after, now()) end,
    follow_ups_sent = follow_ups_sent
      + case when p_trigger = 'follow_up' and v_message_id is not null then 1 else 0 end,
    updated_at = now()
  where id = p_lead_id
  returning public_token into v_public_token;

  return jsonb_build_object(
    'stale', false,
    'decision_id', v_decision_id,
    'final_action', v_final,
    'end_state', v_check->>'end_state',
    'reply', v_reply,
    'message_id', v_message_id,
    'message_status', v_status,
    'channel', v_channel,
    'send_after', v_send_after,
    'approval_id', v_approval_id,
    'violations', v_check->'violations',
    'owner_note', nullif(p_decision->>'owner_note', ''),
    'booked_slot', leads.slot_label(v_booked_at),
    'public_token', v_public_token);
end $$;

-- ---------- The owner's answer on a price ----------

-- Only a pending approval changes, so a double click or two people clicking
-- is harmless.
--   approve: the waiting reply becomes 'sent', unless the conversation has
--            ended or a person took over, in which case it's withdrawn.
--   reject:  the reply is never sent and the owner takes over the lead, unless
--            they have a visit booked, which stays.
create or replace function leads.resolve_approval(
  p_approval_id  bigint,
  p_approved     boolean,
  p_decided_by   text
) returns jsonb language plpgsql set search_path = '' as $$
declare
  v_approval  leads.approvals;
  v_lead      leads.leads;
  v_message   leads.messages;
  v_open      boolean;
  v_send      boolean;
  v_status    text;
  v_subject   text;
begin
  -- Lock the lead first, in the same order as apply_decision.
  perform 1 from leads.leads l
  where l.id = (select a.lead_id from leads.approvals a where a.id = p_approval_id) for update;
  select * into v_approval from leads.approvals where id = p_approval_id for update;
  if not found then
    raise exception 'approval % not found', p_approval_id;
  end if;
  select * into v_lead from leads.leads where id = v_approval.lead_id;
  select * into v_message from leads.messages where id = v_approval.message_id;

  if v_approval.status <> 'pending' then
    return jsonb_build_object(
      'changed', false, 'status', v_approval.status, 'decided_by', v_approval.decided_by,
      'lead', jsonb_build_object('name', v_lead.name, 'email', v_lead.email, 'phone', v_lead.phone,
                                 'zip', v_lead.zip, 'summary', v_lead.summary),
      'reply', v_message.body);
  end if;

  v_open := v_lead.status in ('waiting_approval', 'active', 'booked');
  v_send := p_approved and v_open;
  v_status := case when v_send then 'approved' when p_approved then 'withdrawn' else 'rejected' end;

  update leads.approvals set status = v_status, decided_by = p_decided_by, decided_at = now()
  where id = p_approval_id;

  -- An approved reply counts as sent now, so it sits in the right place in the thread.
  update leads.messages set
    status = case when v_send then 'sent' else v_status end,
    created_at = case when v_send then now() else created_at end
  where id = v_approval.message_id;

  if v_send then
    update leads.leads set
      status = case when status = 'waiting_approval' then 'active' else status end,
      awaiting_reply_since = case when status in ('waiting_approval', 'active') then now() else awaiting_reply_since end,
      updated_at = now()
    where id = v_lead.id;
  elsif not p_approved then
    update leads.leads set
      status = 'handed_off', end_state = 'handed_off', awaiting_reply_since = null, updated_at = now()
    where id = v_lead.id and status in ('waiting_approval', 'active');
  end if;

  select m.subject into v_subject from leads.messages m
  where m.lead_id = v_lead.id and m.direction = 'in' order by m.created_at, m.id limit 1;

  return jsonb_build_object(
    'changed', true,
    'status', v_status,
    'send', v_send,
    'unsubscribed', p_approved and not v_send and coalesce(v_lead.end_state, '') = 'unsubscribed',
    'lead_id', v_lead.id,
    'channel', v_message.channel,
    'reply', v_message.body,
    'subject', v_subject,
    'thread_id', v_lead.email_thread_id,
    'lead', jsonb_build_object('name', v_lead.name, 'email', v_lead.email, 'phone', v_lead.phone,
                               'zip', v_lead.zip, 'summary', v_lead.summary));
end $$;

revoke execute on function
  leads.email_state(leads.messages),
  leads.email_states(text[]),
  leads.receive_message(text, text, text, text, text, text, text, text, text, uuid, boolean, text),
  leads.mentions_money(text),
  leads.price_amounts(text),
  leads.check_decision(uuid, text, jsonb, timestamptz),
  leads.apply_decision(uuid, text, jsonb, jsonb, text),
  leads.resolve_approval(bigint, boolean, text)
from public, anon, authenticated;
