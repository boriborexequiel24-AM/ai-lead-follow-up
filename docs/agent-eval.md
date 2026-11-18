# Agent accuracy test

Run on 2026-11-18 17:35 with `scripts/eval_agent.py` (reasoning effort: low).
Each case runs the full agent turn: read the lead, check the service area, pick the next step.
The answer key is in `sample-leads/` (leads.json, conversations.json, follow_ups.json).

| Model | Right action | All checks | Perfect cases | Avg time | Cost per lead turn | Errors |
|---|---|---|---|---|---|---|
| gpt-5.4-mini | 35 / 35 | 100.0% | 35 / 35 | 5.2s | $0.0031 | 0 |

## Misses

None. Every model passed every check.

## How the model was chosen

**First run (gpt-5.4-mini only):** 28 of 29 actions right. The eval caught three real problems, all fixed in the prompts:
- **It made up a visit time.** Asked about Saturdays, it offered Saturday at 1pm, which isn't an open slot. The prompt now says to copy slots exactly from the open list and never invent one. The phase 4 guardrails will also reject any slot that isn't in the slots table.
- **Em dashes in 13 of 29 replies.** The prompt now forbids them, and the eval checks every reply. Zero since.
- **Price questions were marked "flexible".** "How much to look at my short-cycling furnace?" is a broken furnace, so it should be "this_week". The read prompt now says asking about price doesn't change urgency.

One label was loosened: L22 ("Are you open Saturdays? I work weekdays") now also accepts offering Saturday slots, which is a better answer than just quoting the hours.

**Two runs on both models after the fixes:**
- **gpt-5.4-mini:** 29 of 29 actions right both times. The only miss in either run was calling a plumbing-only email "both" trades, which didn't change the action.
- **gpt-5.4-nano:** 27 of 29 actions right, with misses that matter: it failed to find a zip written in the email text (so it asked for it again), treated the "confirm $100" trick message as spam instead of a real customer, and once escalated a vague "need help asap" as an emergency.

**Decision:** use **gpt-5.4-mini** at low reasoning effort. About $0.003 and 4.7 seconds per lead turn (both AI steps), so 1,000 agent replies cost around $3. nano is about 4 times cheaper but its misses are the kind a client would notice.

**What it handles well:** every emergency type with the right safety step first (gas: leave the house, call from outside), the injection attempt (it drafted the real $1,400 to $2,200 range for owner approval and never mentioned $100), replying in Spanish, declining out-of-area and commercial jobs, and handing off a tax credit question instead of guessing.

**After the first real email test (2026-11-18):** a lead answered "Wednesday morning works for me" when 8am and 10am were both offered, and the agent booked 10am without asking. The decide prompt now says to ask when a reply fits more than one offered slot, and that picking a different slot after booking is a reschedule. Two conversations were added for this (C08 ambiguous pick, C09 reschedule). gpt-5.4-mini: 31 of 31 right, every check passed.

**Follow-ups and weekdays (phase 7, 2026-11-18):** four follow-up cases were added (`sample-leads/follow_ups.json`: a nudge, re-asking for a zip, a last message after an approved price, and one in Spanish). The first run wrote "martes 7 de octubre" for a Wednesday: the model was working out weekdays from raw dates. Open slots now come with a label made by the database ("Wednesday Oct 7 at 8am") plus today's date, the prompts say to use the label and never work out a weekday, and the eval checks that every weekday named in a reply matches an offered slot. gpt-5.4-mini: 35 of 35 right, every check passed.
