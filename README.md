# Lead Follow-Up Agent

An AI agent for a home services business (plumbing + HVAC) that answers every new lead within seconds and keeps following up until the lead books, says no, or goes quiet. The owner only steps in for prices, emergencies, and anything the agent isn't sure about.

**Status:** working end to end; the demo site is built and about to go live. A live demo link will go here.

## Try the demo
On the demo site you play the customer of Copperline Plumbing & Air, a made-up company:
- Send a request with the form, or pick a scenario (book a tune-up, burst pipe, price shopper, out of the area, vague message).
- The agent replies in a few seconds. Each reply shows what it chose to do and why.
- Keep chatting: pick a time, ask for a price, or say you found someone else.
- Ask for a price and you get to play the owner too: approve or reject the draft, just like the Slack buttons the real owner uses.
- Stop replying and watch the follow-ups arrive (on the demo clock a day lasts a minute).

The owner view shows response times, bookings and hand-offs, and the full decision history of sample leads. Visitor conversations are private to the person who started them and deleted after 24 hours.

## How it works
1. A lead comes in from the website form or by email.
2. The AI reads it: what the job is, how urgent, whether they want a price, what's missing.
3. The agent picks one next step from a fixed menu (ask a question, offer booking slots, flag an emergency, draft a price, hand off to the owner, and so on) and writes the message.
4. Rules check the step before anything is sent: no prices without the owner's approval, only real open visit times, no follow-ups at night (on the real clock), a limit on unanswered messages, an instant stop on "unsubscribe".
5. If the lead goes quiet, it follows up after 1, 3 and 7 days, each message written for that lead, and closes the lead after day 10.

More detail in [docs/PLAN.md](docs/PLAN.md) and [docs/agent-flow.md](docs/agent-flow.md).

## Built with
n8n, OpenAI, Supabase, Next.js + Tailwind on Vercel, Slack, Gmail.

All company details, leads and prices are fictional.
