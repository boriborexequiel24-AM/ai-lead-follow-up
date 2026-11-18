-- Fix found in the first real email test (2026-11-18): a lead who booked one
-- slot and then picked another ended up holding both. Booking a slot now
-- releases any other slot the same lead held, so changing the time moves the
-- booking, and confirming the slot the lead already holds is fine (it used to
-- be rejected as "no longer open"). Nothing else in check_decision or
-- apply_decision changes.
--
-- Safe to run more than once.

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
    -- One booking per lead: picking another time moves the booking.
    update leads.slots set booked_lead_id = null, booked_at = null
    where booked_lead_id = p_lead_id and starts_at <> v_slot;
    update leads.slots set booked_lead_id = p_lead_id, booked_at = now()
    where starts_at = v_slot and (booked_lead_id is null or booked_lead_id = p_lead_id);
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

revoke execute on function
  leads.check_decision(uuid, text, jsonb, timestamptz),
  leads.apply_decision(uuid, text, jsonb, jsonb, text)
from public, anon, authenticated;
