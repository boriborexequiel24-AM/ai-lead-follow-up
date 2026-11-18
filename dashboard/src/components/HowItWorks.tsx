import Link from "next/link";

// "What happens next, to the second": the steps behind every reply, with the
// real timings from the live demo (about 8 seconds to the first reply) and
// the follow-up schedule.

const STEPS = [
  { at: "0s", title: "Message in.", body: "From the form or by email." },
  {
    at: "~5s",
    title: "Read and decide.",
    body: "Two AI steps: the job, how urgent, the zip and whether you want a price, then one next step from a fixed menu.",
  },
  {
    at: "~8s",
    title: "Check and reply.",
    body: "Rules first: real times only, no price the owner hasn't approved. Prices and emergencies also go to the owner in Slack.",
  },
  { at: "Day 1·3·7", title: "Follow up.", body: "If you go quiet. On this demo a day lasts a minute." },
  { at: "Day 10", title: "Close.", body: "Still no reply, so the lead is closed and nobody gets chased forever." },
];

export function HowItWorks() {
  return (
    <div id="how-it-works" className="min-w-0 flex-[1_1_420px] scroll-mt-6">
      <h2 className="font-display text-[26px] font-extrabold leading-tight">What happens next, to the second</h2>
      <p className="mt-1.5 text-[15px] text-ink-600">
        The agent picks from a fixed menu, and rules check it before anything goes out.
      </p>
      <ol className="mt-5">
        {STEPS.map((step) => (
          <li key={step.at} className="flex gap-4 border-t border-sand-200 py-3.5 last:border-b">
            <span className="min-w-[76px] font-display font-extrabold text-copper-600">{step.at}</span>
            <span>
              <strong>{step.title}</strong> <span className="text-ink-600">{step.body}</span>
            </span>
          </li>
        ))}
      </ol>
      <p className="mt-5 text-[15px] text-ink-600">
        Run a business like this?{" "}
        <Link href="/owner" className="font-semibold text-copper-600 hover:text-copper-700 hover:underline">
          See it from the owner&apos;s side
        </Link>
        : response times, bookings, and every decision the agent made and why.
      </p>
    </div>
  );
}
