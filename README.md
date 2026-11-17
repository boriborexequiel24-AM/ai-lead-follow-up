# Lead Follow-Up Agent

An AI agent for a home services business (plumbing + HVAC) that answers every new lead within seconds and keeps following up until the lead books, says no, or goes quiet. The owner only steps in for prices, emergencies, and anything the agent isn't sure about.

**Status:** in development. A live demo link will go here.

## How it works
1. A lead comes in from the website form or by email.
2. The AI reads it: what the job is, how urgent, whether they want a price, what's missing.
3. The agent picks one next step from a fixed menu (ask a question, offer booking slots, flag an emergency, draft a price, hand off to the owner, and so on) and writes the message.
4. Rules check the step before anything is sent: no prices without the owner's approval, no messages at night, a limit on unanswered messages, an instant stop on "unsubscribe".
5. If the lead goes quiet, it follows up after 1, 3 and 7 days, each message written for that lead.

More detail in [docs/PLAN.md](docs/PLAN.md) and [docs/agent-flow.md](docs/agent-flow.md).

## Built with
n8n, OpenAI, Supabase, Next.js + Tailwind on Vercel, Slack, Gmail.

All company details, leads and prices are fictional.
