-- Fix found while testing the demo site: follow-ups 2 and 3 came late.
--
-- claim_follow_ups holds each lead for 5 minutes so two scheduler runs can
-- never follow up the same lead twice. The hold was never released after a
-- follow-up went out, so on the demo clock (gaps of 1 to 4 minutes) the next
-- follow-up waited for the hold to run out: day 3 arrived at about minute 6.
--
-- Now a hold only counts while it is newer than the lead's latest agent
-- message. A follow-up that went out moves awaiting_reply_since past the
-- hold, which releases it; one that failed leaves it, so it is retried after
-- 5 minutes as before.
--
-- Safe to run more than once.

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
      and (l.follow_up_claimed_at is null
           or l.follow_up_claimed_at < l.awaiting_reply_since
           or l.follow_up_claimed_at < now() - interval '5 minutes')
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

revoke execute on function leads.claim_follow_ups(int) from public, anon, authenticated;
