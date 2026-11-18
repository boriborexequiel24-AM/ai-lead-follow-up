import { Container } from "@/components/Brand";
import { HowItWorks } from "@/components/HowItWorks";
import { QuoteForm } from "@/components/QuoteForm";
import { RecentThreads } from "@/components/RecentThreads";
import { COMPANY } from "@/lib/company";

const CHIPS = ["First reply in about 8 seconds", "Prices checked by the owner", "Follow-ups on day 1, 3 and 7"];

export default function Home() {
  return (
    <>
      <section className="bg-navy-900 text-white">
        <Container className="flex flex-wrap items-center gap-12 pb-[72px] pt-12 sm:pt-16">
          <div className="min-w-0 flex-[1_1_520px]">
            <p className="mb-4 text-[13px] font-semibold tracking-[2px] text-copper-300">CENTRAL AND SOUTH DENVER</p>
            <h1 className="font-display text-[44px] font-black leading-[0.98] tracking-[-1px] sm:text-[56px] lg:text-[68px]">
              Leak at 2am?
              <br />
              <span className="text-copper-300">Someone answers.</span>
            </h1>
            <p className="mt-6 max-w-[520px] text-[17px] leading-[1.55] text-navy-200 sm:text-[19px]">
              Every message gets a real reply in seconds, day or night. Pick a time, ask a question, or tell us it&apos;s
              an emergency, and we&apos;ll take it from there.
            </p>
            <ul className="mt-7 flex flex-wrap gap-2.5">
              {CHIPS.map((chip) => (
                <li key={chip} className="rounded-full border border-navy-600 px-3.5 py-2 text-sm">
                  {chip}
                </li>
              ))}
            </ul>
            <RecentThreads />
          </div>

          <PhoneMockup />
        </Container>
      </section>

      <QuoteForm aside={<HowItWorks />} />
    </>
  );
}

/** A picture of the burst pipe conversation, as it looks on a phone. */
function PhoneMockup() {
  return (
    <div className="mx-auto w-full max-w-[340px] flex-[0_1_340px]" aria-hidden="true">
      <div className="rounded-[40px] border border-navy-700 bg-navy-950 p-3">
        <div className="flex h-[520px] flex-col gap-3 rounded-[30px] bg-white px-4 py-5 text-navy-900">
          <div className="flex items-center gap-2.5 border-b border-sand-100 pb-3">
            <div className="grid size-[34px] place-items-center rounded-full bg-copper-500 text-sm font-bold text-white">C</div>
            <div>
              <div className="text-sm font-semibold">Copperline</div>
              <div className="text-xs text-[#2F7D4F]">Replies in seconds</div>
            </div>
          </div>
          <div className="max-w-[82%] self-end rounded-[16px_16px_4px_16px] bg-copper-600 px-3 py-2.5 text-sm text-white">
            Water is spraying under the kitchen sink and I can&apos;t find the shutoff!
          </div>
          <div className="self-end text-xs text-ink-500">2:04 am</div>
          <div className="max-w-[86%] rounded-[16px_16px_16px_4px] bg-navy-50 px-3 py-2.5 text-sm leading-[1.45]">
            Turn the main water valve clockwise, usually where the line enters the house. Then call our 24/7 line at{" "}
            {COMPANY.emergencyPhone}. A tech is being alerted now.
          </div>
          <div className="flex items-center gap-1.5">
            <span className="rounded-full bg-[#FCE8E4] px-2 py-0.5 text-xs font-semibold text-[#9B2C1C]">
              Emergency: owner alerted
            </span>
            <span className="text-xs text-ink-500">7s later</span>
          </div>
          <div className="mt-auto rounded-full border border-[#DCD5CA] px-3.5 py-2.5 text-sm text-ink-400">
            Write back as the customer...
          </div>
        </div>
      </div>
    </div>
  );
}
