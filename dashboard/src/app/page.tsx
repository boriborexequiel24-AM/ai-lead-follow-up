import Link from "next/link";
import { HowItWorks } from "@/components/HowItWorks";
import { QuoteForm } from "@/components/QuoteForm";
import { RecentThreads } from "@/components/RecentThreads";
import { COMPANY } from "@/lib/company";

export default function Home() {
  return (
    <div className="space-y-14">
      <section className="grid items-start gap-8 lg:grid-cols-[1fr_28rem]">
        <div className="space-y-6">
          <div className="rounded-xl border border-copper-200 bg-copper-50 p-4 text-sm text-copper-900">
            <p className="font-semibold">You&apos;re the customer.</p>
            <p className="mt-1">
              Send a request with the form, or pick a scenario. An AI agent reads it, picks the next step and replies in
              seconds. Then keep chatting: pick a time, ask for a price, or go quiet and watch it follow up.
            </p>
          </div>

          <div>
            <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">
              Plumbing, heating and cooling for central and south Denver.
            </h1>
            <p className="mt-3 max-w-xl text-stone-600">
              Licensed, insured, background-checked technicians. Send us a message any time and you&apos;ll hear back in
              about a minute, not tomorrow.
            </p>
          </div>

          <dl className="grid max-w-xl gap-4 text-sm sm:grid-cols-3">
            <div>
              <dt className="text-stone-500">Call us</dt>
              <dd className="font-semibold">{COMPANY.phone}</dd>
            </div>
            <div>
              <dt className="text-stone-500">Emergencies, 24/7</dt>
              <dd className="font-semibold">{COMPANY.emergencyPhone}</dd>
            </div>
            <div>
              <dt className="text-stone-500">Hours</dt>
              <dd className="font-semibold">{COMPANY.hours}</dd>
            </div>
          </dl>

          <div>
            <h2 className="text-sm font-semibold text-stone-700">What we do</h2>
            <ul className="mt-2 grid max-w-xl gap-x-6 gap-y-1 text-sm text-stone-600 sm:grid-cols-2">
              {COMPANY.services.map((s) => (
                <li key={s} className="flex gap-2">
                  <span className="text-copper-500">&#10003;</span>
                  {s}
                </li>
              ))}
            </ul>
          </div>

          <RecentThreads />
        </div>

        <QuoteForm />
      </section>

      <HowItWorks />

      <section className="flex flex-col items-start justify-between gap-4 rounded-2xl bg-stone-900 p-6 text-stone-100 sm:flex-row sm:items-center">
        <div>
          <h2 className="text-lg font-semibold">See it from the owner&apos;s side</h2>
          <p className="mt-1 text-sm text-stone-300">
            Response times, bookings and hand-offs, plus every decision the agent made on sample leads and why.
          </p>
        </div>
        <Link
          href="/owner"
          className="shrink-0 rounded-lg bg-white px-4 py-2 text-sm font-semibold text-stone-900 hover:bg-copper-50"
        >
          Open the owner view
        </Link>
      </section>
    </div>
  );
}
