# Lead Capture

## Overview
A portfolio and demo project built by Exequiel to show prospective clients. The goal is an agentic workflow that captures new leads and follows up with them automatically, so no lead goes cold because nobody replied in time.

**Why this project:** research done on 2026-11-17 found lead capture and follow-up is one of the two automations businesses ask for most (the other is invoice and payment handling, already covered by `Real Work Systems/`). Sources are summarized in [docs/research.md](docs/research.md) once that file exists.

**How it must differ from existing work:** Exequiel's portfolio (workwithbori.cloud, workwithzeki.vercel.app) already shows lead routing and CRM sync as n8n/Make/Zapier workflows. This project should not repeat that. The new part is the *agentic follow-up*: the system reads each lead, decides what to do next, writes the message, and keeps following up over days until the lead replies, books, or is closed out.

## Status
Planning done, nothing built yet. Full plan in [docs/PLAN.md](docs/PLAN.md).

| Phase | State |
|---|---|
| 1. Setup | Done 2026-11-17: repo, docs, `.env`, Supabase `leads` schema (verified via API), Slack app "Lead Assistant" with `#lead-approvals` and `#lead-alerts` (test messages posted), Gmail label `lead-demo`. |
| 2. Sample data | Done 2026-11-18: company "Copperline Plumbing & Air" (migration + `supabase/seed.sql`, verified via API: 1 profile, 10 FAQ, 16 prices, public key blocked), 22 labelled leads and 7 conversations in `sample-leads/`. |
| 3. Agent brain + eval | Done 2026-11-18: prompts and schemas in `agent/`, `scripts/eval_agent.py`. gpt-5.4-mini, 29/29 right actions in two runs, ~$0.003 and ~4.7s per lead turn (docs/agent-eval.md). |
| 4. Guardrails + conversation loop | Not started |
| 5. Intake | Not started |
| 6. Slack | Not started |
| 7. Follow-ups | Not started |
| 8. Dashboard | Not started |
| 9. Polish | Not started |

## Decisions
- **Demo client: a home services business** (decided 2026-11-17). Fictional company, fake leads. Fits because these businesses win or lose jobs on how fast they answer, owners are usually on a job site and can't reply, and leads arrive from many places at once.
- **Trade: plumbing + HVAC** (decided 2026-11-17). Mixes emergencies (burst pipe, no heat) with planned jobs (new water heater, AC install), so the agent has real urgency decisions to make.
- **Lead sources for v1: website form and email** (decided 2026-11-17). The form lives on a fake company site so visitors can try it live. Email intake can follow the pattern of workflow 4 in `Real Work Systems/` (scheduled Gmail search on a dedicated label, never Gmail Trigger). Missed-call text-back and lead marketplaces are possible later additions.
- **Two Gmail accounts: one is the company, one plays the customer** (decided 2026-11-17). The intake inbox (`GMAIL_INTAKE_ADDRESS`) is the same Gmail account the invoice demo's email intake uses, so the existing n8n Gmail credential is reused (Exequiel is moving his everyday mail off it, so it becomes demo-only). The agent reads from and sends as it. The two demos never see each other's mail because each only touches its own label (`invoice-demo` / `lead-demo`). Test leads are sent from Exequiel's other address, the only one on `OUTBOUND_EMAIL_ALLOWLIST`. Keeping them separate means a lead's reply and the agent's own message never share a sender. Intake should still skip anything sent from the intake address itself, as a guard against the agent answering itself.
- **Approval: automatic first reply and booking, owner approves anything with a price** (decided 2026-11-17). Quotes and price estimates go to the owner in Slack before they are sent.
- **Agent design: the AI reads and writes, picks the next step from a fixed menu, and rules check every step before it sends** (decided 2026-11-17). Not rules-only (that is just routing again) and not free-form (can't be tested or promised to a client). Full flow, menu, guardrails and end states in [docs/agent-flow.md](docs/agent-flow.md). The menu is tested with a labelled set of sample leads and a score, like `eval_extraction.py` in `Real Work Systems/`.
- **Reply channel for v1: email** (decided 2026-11-17). SMS later; in the US it needs a Twilio number and 10DLC carrier registration.
- **The live demo is a conversation thread on the dashboard** (decided 2026-11-17). A visitor submits the form, then plays the customer: they see the agent's replies in the thread and can type their own. Real emails go only to Exequiel's test inbox, never to visitors.
- **Booking uses fake slots stored in the database** (decided 2026-11-17), reset by an hourly cleanup like workflow 3 in `Real Work Systems/`. The README notes that a real client would connect Google Calendar or Cal.com.
- **Prices come from an invented sample price sheet** (decided 2026-11-17), about 10 common plumbing and HVAC jobs with ranges, clearly labelled as sample prices.
- **Follow-up timing has a demo clock** (decided 2026-11-17). One setting sets the speed: demo mode runs 1 day as 1 minute, so a visitor sees the 1, 3 and 7 day follow-ups within about 10 minutes; client mode uses real days. Same code for both.
- **Visitor privacy** (decided 2026-11-17). Each visitor sees only their own thread via a private, unguessable link. The public owner view shows seeded sample leads and overall metrics only. The form tells visitors to use fake details.
- **Supabase: shares the invoice demo's project, in its own `leads` schema** (decided 2026-11-17). The free plan allows two active projects and both are in use; a second account to get around that was ruled out (likely against Supabase's terms, and a risk for a client-facing demo). Never create tables, functions or policies in `public`, which belongs to the invoice demo. Clients set the schema explicitly (supabase-js: `db: { schema: 'leads' }`; REST: `Accept-Profile` / `Content-Profile: leads` headers). New tables are private to the public key until a migration grants specific columns: every table migration runs `revoke all on leads.<table> from anon, authenticated;` right after creating it, then grants only the columns the dashboard needs (don't rely on the Data API's "Automatically expose new tables" setting being off); every function migration revokes execute from `public, anon, authenticated`.
- **Public demo limits** (decided 2026-11-17). 3 leads per visitor per day (by IP), about 10 visitor messages per thread, a daily cap on total AI calls, and visitor leads deleted after 24 hours.

## Open questions
Listed under "Open decisions" in [docs/PLAN.md](docs/PLAN.md): outbound email service, Gmail label, and the project name.

## How the agent works
- One agent turn is two AI calls plus a rule: **read** (`agent/read_prompt.md` + `read_schema.json`) turns the conversation into fixed facts, a code step checks the zip against the service area, then **decide** (`agent/decide_prompt.md` + `decide_schema.json`) picks one action and writes the reply. Both use the OpenAI Responses API with a strict JSON schema, reasoning effort low.
- The files in `agent/` are the source of truth. n8n must run exactly these (generated from them, like the invoice project's extraction step), so the eval always tests what runs in production.
- Inputs are plain JSON objects (company, faq, price_sheet, now, facts, open_slots, conversation) so n8n can build the identical payload.
- Test with `python scripts/eval_agent.py --models gpt-5.4-mini` (standard library only, no venv needed; reads company data live from Supabase). Run it after any prompt change. Raw results go to `scripts/eval-results/` (gitignored).

## Tech Stack
Not decided. Likely reuses what worked in `Real Work Systems/`: n8n (self-hosted) for orchestration, OpenAI for the AI steps (existing credits; keep the provider swappable), Supabase for data, Next.js + Tailwind on Vercel for the dashboard, Slack for alerts and approvals.

## Conventions
- Favor clarity and maintainability over clever code. The codebase is part of the portfolio.
- Never commit secrets. Use environment variables and a `.env.example` file.
- Only fake sample leads. Never send real messages to real people from the demo; outbound messages go to test inboxes or numbers Exequiel controls.
- Write a short README section for any feature a client might see.
- Document decisions in `docs/` so the project is easy to walk through in a client conversation.
- Never use em dashes in anything written for this project.
- Don't touch Exequiel's other n8n workflows (client work).
- Never set `retryOnFail` on a node that calls a paid API (lesson from `Real Work Systems/`: it multiplied OpenAI calls and cost).

## Working Notes
- Environment: Windows 11, PowerShell and Git Bash available.
- Git repo on `main`, with git name/email set for this repo only. No remote yet; push only when Exequiel asks.
- Account setup steps are in [docs/SETUP.md](docs/SETUP.md).
