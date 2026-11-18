# Case study copy for workwithzeki.vercel.app

Draft wording for adding this project to the portfolio site. Edit it to sound like you.

Every number here comes from the project's own measurements (docs/agent-eval.md, the owner view and the test scripts). The one outside claim is the general point that home services leads go cold fast when nobody answers. That is a well-known industry pattern, not something measured here, so keep it general rather than quoting a percentage as if it were a client result.

---

## For the project card

**Title:** AI Lead Follow-Up Agent (Home Services)

**Category:** AI Agent · Sales and Customer Service

**Tools:** n8n · OpenAI · Supabase · Slack · Gmail · Next.js

**Description (short):**
Every new lead gets a reply in seconds, day or night. An AI agent reads the request, picks the next step from a fixed menu, and books a visit, asks a question or escalates an emergency. Rules check every message, the owner approves any price in Slack, and quiet leads get followed up on day 1, 3 and 7. Live demo you can chat with.

**Metric to show:** `First reply in about 8 seconds, at roughly a third of a cent in AI cost`

**Links:** Live demo · Code on GitHub

---

## For the full case study page

### The problem
A plumber or HVAC owner is usually on a job when a new lead comes in. The customer with a leaking water heater sends the same request to three companies, and the first one to answer usually gets the job. By the time the owner checks messages that evening, the lead has booked someone else. The leads that don't book right away need two or three follow-ups, which nobody has time to write.

### What I built
An agent that answers every lead within seconds and keeps the conversation going until it's settled, while leaving the decisions that matter to the owner.

1. **The lead comes in** from the website form or by email. Email replies go back in the customer's own Gmail thread.
2. **AI reads it:** what the job is, how urgent, where, whether they want a price, and what's missing.
3. **A rule checks the service area.** The zip is on the list or it isn't. No AI guessing.
4. **The agent picks one next step** from a fixed menu: offer visit times, book, ask a question, answer from the FAQ, draft a price, escalate an emergency, decline, hand off or close. It writes the reply and records why.
5. **Rules check the step before it is sent.** Only real open times, no unapproved prices, the emergency line in every emergency, an instant stop on "stop emailing me". Anything that breaks a rule goes to a person instead, with the reason.
6. **The owner approves prices** in Slack with one click. Emergencies and hand-offs get an alert.
7. **Quiet leads get followed up** on day 1, 3 and 7, each message written for that lead, then the lead is closed on day 10.

Every decision is stored with its reason, so the owner can open any lead and see exactly what the agent did and why.

### Why it can be trusted
This is the part worth talking about with clients. An AI that writes to customers on its own is only useful if you can say what it will and won't do.

- **It can't go off script.** The agent chooses from nine actions. It can't invent a new kind of reply, and every choice passes through rules in the database before anything is sent.
- **It never quotes a price on its own.** A drafted price waits for the owner's approval, and must sit inside the sample price sheet. When a test lead tried to talk the agent into a $100 water heater, it drafted the real price range for approval and never mentioned $100.
- **The accuracy was measured, not assumed.** I wrote 35 test cases with the right answer for each: a gas smell, a burst pipe at night, an out-of-area zip, a vendor sales pitch, a price question buried in a long email, a reply in Spanish, a customer who found someone else, and a vague "need help asap". The chosen model gets all 35 right.
- **Testing found real bugs before customers would.** The first run made up a visit time that wasn't open. A Spanish follow-up named the wrong weekday for a date. A customer who picked a second time ended up with two bookings. Each one was fixed, and each became a permanent test.
- **Failures stay visible.** If the AI call fails, the message is kept and the owner gets an alert. If an email can't be sent, the owner hears about it. Nothing fails silently.

### Results
| | |
|---|---|
| Right next step on the test set | 35 of 35 cases |
| Time to first reply | About 8 seconds (median on the live demo) |
| AI cost per reply | About $0.003, so roughly $3 per 1,000 replies |
| Follow-ups | Day 1, 3 and 7, then closed, with no one writing them |
| Human steps | Approve prices, take over emergencies and hand-offs |

### Built with
n8n for the workflows, the OpenAI API for reading leads and writing replies, Supabase for the database and the guardrail rules, a Slack app for approvals and alerts, Gmail for email leads, and a Next.js site on Vercel for the live demo.

### Try it
The demo is public. You play a customer of a made-up plumbing company: send a request or pick a scenario, chat with the agent, approve a price as the owner, or go quiet and watch the follow-ups arrive. On the demo a day lasts a minute, so the whole sequence takes about 10 minutes. Conversations are private to you and deleted after 24 hours.
