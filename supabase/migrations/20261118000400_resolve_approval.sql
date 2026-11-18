-- Phase 6: the owner approves or rejects a price from Slack.
--
-- resolve_approval records the click and updates everything in one go:
--   approve: the waiting reply becomes 'sent' (visible in the web thread, and
--            returned so n8n can email it), and the follow-up clock starts.
--   reject:  the reply is never sent and the owner takes over the lead.
-- Only a pending approval changes, so a double click or two people clicking
-- is harmless. If the lead unsubscribed while the price was waiting, an
-- approval sends nothing.
--
-- Safe to run more than once.

create or replace function leads.resolve_approval(
  p_approval_id  bigint,
  p_approved     boolean,
  p_decided_by   text
) returns jsonb language plpgsql set search_path = '' as $$
declare
  v_approval  leads.approvals;
  v_lead      leads.leads;
  v_message   leads.messages;
  v_send      boolean;
  v_subject   text;
begin
  select * into v_approval from leads.approvals where id = p_approval_id for update;
  if not found then
    raise exception 'approval % not found', p_approval_id;
  end if;
  select * into v_lead from leads.leads where id = v_approval.lead_id for update;
  select * into v_message from leads.messages where id = v_approval.message_id;

  if v_approval.status <> 'pending' then
    return jsonb_build_object(
      'changed', false, 'status', v_approval.status, 'decided_by', v_approval.decided_by,
      'lead', jsonb_build_object('name', v_lead.name, 'email', v_lead.email, 'phone', v_lead.phone,
                                 'zip', v_lead.zip, 'summary', v_lead.summary),
      'reply', v_message.body);
  end if;

  v_send := p_approved and coalesce(v_lead.end_state, '') <> 'unsubscribed';

  update leads.approvals set
    status = case when p_approved then 'approved' else 'rejected' end,
    decided_by = p_decided_by,
    decided_at = now()
  where id = p_approval_id;

  -- An approved reply counts as sent now, so it sits in the right place in the thread.
  update leads.messages set
    status = case when v_send then 'sent' else 'rejected' end,
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
    where id = v_lead.id and coalesce(end_state, '') <> 'unsubscribed';
  end if;

  select m.subject into v_subject from leads.messages m
  where m.lead_id = v_lead.id and m.direction = 'in' order by m.created_at, m.id limit 1;

  return jsonb_build_object(
    'changed', true,
    'status', case when p_approved then 'approved' else 'rejected' end,
    'send', v_send,
    'unsubscribed', p_approved and not v_send,
    'lead_id', v_lead.id,
    'channel', v_message.channel,
    'reply', v_message.body,
    'subject', v_subject,
    'thread_id', v_lead.email_thread_id,
    'lead', jsonb_build_object('name', v_lead.name, 'email', v_lead.email, 'phone', v_lead.phone,
                               'zip', v_lead.zip, 'summary', v_lead.summary));
end $$;

revoke execute on function leads.resolve_approval(bigint, boolean, text) from public, anon, authenticated;
