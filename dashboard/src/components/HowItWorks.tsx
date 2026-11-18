// The five steps behind every reply, for visitors and prospective clients.

const STEPS = [
  {
    title: "Reads the request",
    body: "AI turns the message into plain facts: what's wrong, how urgent, where, and whether they want a price.",
  },
  {
    title: "Picks one next step",
    body: "From a fixed menu: offer times, book, ask a question, answer, draft a price, escalate, decline or hand off.",
  },
  {
    title: "Rules check the reply",
    body: "Only real open times, no price the owner hasn't approved, the emergency line for emergencies, and opt-outs respected. Anything off goes to a person.",
  },
  {
    title: "The owner approves prices",
    body: "Quotes go to the owner in Slack with Approve and Reject buttons. On this demo, you get to play the owner.",
  },
  {
    title: "Follows up until it's settled",
    body: "No reply? A fresh follow-up on day 1, 3 and 7, then the lead is closed. On the demo clock a day lasts a minute.",
  },
];

export function HowItWorks() {
  return (
    <section id="how-it-works" className="scroll-mt-8">
      <h2 className="text-xl font-semibold tracking-tight">What happens after you hit send</h2>
      <p className="mt-1 max-w-2xl text-sm text-stone-600">
        The agent replies on its own, but only inside clear limits. Every step is stored, so the owner can see what it
        did and why.
      </p>
      <ol className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        {STEPS.map((step, i) => (
          <li key={step.title} className="rounded-xl border border-stone-200 bg-white p-4">
            <span className="grid size-7 place-items-center rounded-full bg-copper-100 text-xs font-semibold text-copper-700">
              {i + 1}
            </span>
            <h3 className="mt-3 text-sm font-semibold">{step.title}</h3>
            <p className="mt-1 text-sm text-stone-600">{step.body}</p>
          </li>
        ))}
      </ol>
    </section>
  );
}
