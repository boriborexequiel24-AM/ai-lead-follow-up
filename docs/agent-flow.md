# Agent decision flow (v1)

Status: **agreed on 2026-11-17.** Decisions are also listed in CLAUDE.md.

The company: a fictional plumbing + HVAC business. Leads arrive by website form or email. Replies go out by email in v1.

## The big idea
**The AI reads and writes. It chooses the next step from a fixed menu. Rules check every choice before anything goes out.**

That split is what makes it safe to show a client: the agent is flexible about understanding messy messages and writing natural replies, but it can't invent a new action, quote a price on its own, or message someone at 2am.

```
 Form / Email
      |
      v
 1. Intake ----> 2. Read the lead (AI) ----> 3. Pick next step (AI)
                                                    |
                                                    v
                                           4. Guardrail check (rules)
                                                    |
                        +---------------------------+------------------+
                        v                           v                  v
                  Send reply now           Owner approves in Slack   Close lead
                        |                           |
                        v                           v
                 5. Wait for reply  <---------------+
                   |          |
             reply arrives   no reply
                   |          |
             back to step 2   6. Follow-up schedule
```

## 1. Intake (no AI)
- Form and email both turn into one lead record: name, email, phone, address or zip, message, source, time received.
- **Duplicate check:** same email or phone in the last 30 days attaches to the existing lead instead of starting a new one. A customer who emails after filling in the form shouldn't get two welcome messages.

## 2. Read the lead (AI, structured output)
The model returns fixed fields, never free text:

| Field | Values |
|---|---|
| `is_real_lead` | true / false (spam, job seekers, vendors pitching) |
| `trade` | plumbing / hvac / both / unclear |
| `job_type` | repair / install / maintenance / other |
| `urgency` | emergency / this_week / flexible |
| `wants_price` | true / false |
| `missing_info` | list, e.g. `["address", "what is broken"]` |
| `zip` | zip code found in the message, or null (emails don't have a zip field) |
| `summary` | one line for the owner, e.g. "No hot water, 15 yr old tank, wants replacement quote" |

**Emergency** means things like: active leak or flooding, no heat in freezing weather, gas smell, sewage backup, no cooling in extreme heat with a vulnerable person (elderly, infant, medical condition). A gas smell always gets "leave the house and call the gas company" first, no matter what else the agent decides.

**Service area is a rule, not AI:** the zip is checked against a fixed list.

## 3. Pick the next step (AI, from a fixed menu)
The agent sees the lead, the conversation so far, and the available time slots, then picks **one** action and gives a short reason (shown on the dashboard):

| Action | When it fits |
|---|---|
| `ask_question` | Key info is missing. Ask one question, not a form. |
| `offer_booking` | Normal repair, install or maintenance. Offer 2-3 open estimate slots from the slots table. |
| `confirm_booking` | Lead picked one of the offered slots. Book it and confirm. (Added in phase 2: without it, "Wednesday at 3 is perfect" had nowhere to go.) |
| `escalate_emergency` | Emergency. Reply instantly with the emergency line, alert the owner in Slack to call now. No booking attempt. |
| `draft_price` | Lead asked for a price. Draft a range from the sample price sheet, send to Slack for approval. |
| `answer_question` | Lead asked something the knowledge base covers (hours, brands serviced, warranty, financing). |
| `hand_off` | Anything it isn't sure about, complaints, existing-customer issues. Owner takes over. |
| `decline` | Outside the service area or a job they don't do. Polite reply, close. |
| `close` | Not a real lead, or lead said no. No reply for spam. |

When more than one action fits, the order in [sample-leads/README.md](../sample-leads/README.md#labelling-rules) decides (not a lead, emergency, decline, hand off, ask, confirm, price, answer, book).

## 4. Guardrails (rules, checked before anything sends)
- No price or dollar amount in a message unless the owner approved it.
- No promised arrival times. Only offer slots that exist on the calendar.
- Quiet hours: nothing sent 8pm to 8am, except the emergency acknowledgement.
- Max 4 messages without a reply, then stop.
- Stop immediately on "stop", "unsubscribe", "not interested" or similar.
- Every message, decision and reason is logged and visible on the dashboard.
- Demo only: outbound mail goes to inboxes Exequiel controls. Never a real person.

If a check fails, the action becomes `hand_off` instead of being sent.

**Testing the menu:** a labelled set of about 20 sample leads, each with the action it should get, scored the same way `eval_extraction.py` scores invoices in `Real Work Systems/`. Includes tricky ones: a gas smell, an out-of-area zip, a vendor pitch, a price request hidden in a long message.

## 5. When the lead replies
The reply goes back through step 2 with the full conversation, so the agent can handle things like "Tuesday works", "how much roughly?", or "actually we already found someone".

## 6. Follow-up schedule (no reply)
| When | What |
|---|---|
| +1 day | Short nudge, written for this lead (not a template) |
| +3 days | Different angle, e.g. mention same-week availability or financing |
| +7 days | Last message, easy "reply 1 to book, 2 to close" style ending |
| +7 days, no reply | Close as `no_response` |

Emergencies skip this. If an emergency lead doesn't answer, the owner already got the Slack alert to call.

**Demo clock:** one setting controls the speed. In demo mode 1 day passes as 1 minute, so the whole sequence plays out in about 10 minutes. Client mode uses real days. Quiet hours follow the same clock.

## What a demo visitor sees
1. Fills in the quote form on the fake company site.
2. Gets the agent's first reply in a conversation thread on the dashboard within seconds, along with the agent's reason for choosing that action.
3. Types replies as the customer ("Tuesday works", "how much roughly?") and watches the agent respond.
4. If they ask for a price, the draft shows as "waiting for owner approval" while it sits in Slack.
5. If they stop replying, follow-ups arrive on the demo clock.

Real emails go only to Exequiel's test inbox, never to visitors. Booking slots are fake, stored in the database, and reset hourly. A real client would connect Google Calendar or Cal.com.

## End states
`booked` · `handed_off` · `declined` · `not_interested` · `no_response` · `unsubscribed` · `spam`

These feed the dashboard numbers: speed to first reply, % booked, % that needed a human.

## Decided on 2026-11-17
- **How agentic:** AI picks from the fixed menu (the middle option). Rules-only would just be routing again; free-form can't be tested.
- **Channel:** email only for v1. SMS later (Twilio number plus US 10DLC registration).
- **Booking:** fake slots in the database for the demo.
- **Prices:** invented sample price sheet of about 10 jobs with ranges, e.g. water heater replacement $1,400 to $2,200.
- **Timing:** 1 / 3 / 7 days, with the demo clock above.
