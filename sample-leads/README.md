# Sample leads

Labelled test cases for the agent. The eval script (phase 3) runs each one through the agent and scores it against `expected`. All names, addresses and emails are fictional (`.example` domains, 555-01xx phone numbers).

- `leads.json`: 22 first messages, one per lead.
- `conversations.json`: 7 multi-turn conversations. Only the agent's response to the **last** lead message is scored.

The company the agent works for (profile, FAQ, price sheet) is in `supabase/seed.sql`.

## What's checked
| Field | How it's scored |
|---|---|
| `action` | Must match, or be one of `also_ok`. The main score. |
| `is_real_lead`, `trade`, `job_type`, `urgency`, `wants_price` | Exact match. |
| `missing_info` | Every listed item must be reported (`location`, `problem_details`). |
| `zip` | For emails: the zip pulled from the text, or `null` if there isn't one. |
| `price_code` | For `draft_price`: which price sheet row it used. |
| `language` | The language the read step detected. |
| `reply_checks` | Regex patterns the reply must contain (or must not, with `must_not`). |
| (every case) | No dollar amount unless drafting a price, no em dashes, and offered slots must be real open slots. |

## Labelling rules
When more than one action could fit, the first rule that applies wins:

1. **Not a real lead** (spam, sales pitches, job seekers) -> `close`
2. **Emergency** (active leak or flooding, gas smell, sewage backup, no heat in freezing weather, no cooling in extreme heat with a vulnerable person) -> `escalate_emergency`. A gas smell always says "leave the house and call the gas company" first.
3. **Outside the service area or a service we don't offer** -> `decline`
4. **Complaints, existing-customer problems, or anything the agent can't answer safely** -> `hand_off`
5. **Missing what's needed to book** (location, or what's wrong) -> `ask_question`
6. **Lead picked one of the offered slots** -> `confirm_booking`
7. **Asked for a price** -> `draft_price`
8. **Asked a question the FAQ covers** -> `answer_question`
9. **Otherwise** -> `offer_booking`

Agent turns marked `follow_up` in `conversations.json` are scheduled follow-ups, not a menu choice.

## Adding a case
Add it to the right file with a unique `id`, then run the eval. If the agent disagrees with a label, check the rule order above before changing either.
