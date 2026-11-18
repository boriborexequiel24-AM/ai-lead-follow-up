import type { Metadata } from "next";
import Link from "next/link";
import { LegalPage, Section } from "@/components/LegalPage";

export const metadata: Metadata = {
  title: "Terms | Copperline lead follow-up demo",
  description: "The terms for using this public demo: what it is, the limits, and what not to type.",
};

export default function Terms() {
  return (
    <LegalPage
      title="Terms of use"
      updated="18 November 2026"
      intro="This site is a free portfolio demo built by Exequiel Boribor. Using it means you are happy with the following."
    >
      <Section title="What this is">
        <p>
          A working demonstration of an AI agent that answers and follows up on leads for a home services company.
          Copperline Plumbing &amp; Air does not exist. Its phone numbers, prices and visit times are invented, a
          &ldquo;booking&rdquo; reserves nothing, and no one will come to your house. Nothing the agent says is advice or
          a real quote.
        </p>
      </Section>

      <Section title="What not to type">
        <p>
          Do not enter real personal details, anything confidential, or another person&apos;s information. Use a made-up
          name and email. Do not use the demo for anything unlawful, abusive or misleading.
        </p>
      </Section>

      <Section title="The limits">
        <ul>
          <li>3 new requests per visitor per day.</li>
          <li>About 10 messages per conversation.</li>
          <li>A cap on the total number of AI replies per day across the whole demo.</li>
          <li>Every conversation is deleted automatically within 24 hours.</li>
        </ul>
        <p>
          These exist to keep a public demo affordable to run. Please do not work around them or send automated traffic.
        </p>
      </Section>

      <Section title="No guarantees">
        <p>
          The demo is offered as it is. It may be slow, unavailable, or changed without notice, and the AI can get things
          wrong. To the extent the law allows, no liability is accepted for any loss arising from using it. See the{" "}
          <Link className="underline" href="/privacy">
            privacy page
          </Link>{" "}
          for what happens to what you type.
        </p>
      </Section>

      <Section title="Changes">
        <p>These terms may change as the demo does. The date at the top says when they last did.</p>
      </Section>
    </LegalPage>
  );
}
