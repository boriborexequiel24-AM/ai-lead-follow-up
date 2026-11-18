import type { Metadata } from "next";
import { LegalPage, Section } from "@/components/LegalPage";

export const metadata: Metadata = {
  title: "Privacy | Copperline lead follow-up demo",
  description: "What happens to what you type into this demo, what is stored, and how long it is kept.",
};

export default function Privacy() {
  return (
    <LegalPage
      title="Privacy"
      updated="18 November 2026"
      intro="This is a public demo of an AI agent for a made-up company, not a real business. Everything below describes what the system actually does with what you type."
    >
      <Section title="If you send a request">
        <ul>
          <li>
            Your name, email, phone, zip and messages are stored in a database so the agent can keep the conversation
            going.
          </li>
          <li>The conversation is sent to the OpenAI API, which reads it and writes the replies.</li>
          <li>
            You see it through a private link with a long random code. It is never listed anywhere public, and the owner
            view shows only sample leads that were made up for the demo.
          </li>
          <li>
            Emergencies, price drafts and anything handed to a person are posted to a private Slack channel that only the
            demo&apos;s builder can see. Those posts include the details you typed.
          </li>
          <li>
            Nothing is ever emailed to the address you enter. The agent only emails a test inbox its builder controls.
          </li>
          <li>Within 24 hours an automatic job deletes the conversation and everything stored with it.</li>
        </ul>
        <p className="font-medium text-stone-900">
          So please use made-up details. A fake name and an address like you@example.com work exactly the same.
        </p>
      </Section>

      <Section title="What else is stored">
        <ul>
          <li>
            A salted SHA-256 hash of your IP address, used only to count the 3 requests a day each visitor gets. Your
            actual IP address is never written down, and the hash cannot be turned back into it. It is deleted with the
            conversation.
          </li>
          <li>
            Links to your own recent conversations, kept in your browser&apos;s local storage so you can find them again.
            They never leave your device.
          </li>
          <li>No account, no sign-in, no cookies, and no analytics or tracking scripts.</li>
        </ul>
      </Section>

      <Section title="Who else sees it">
        <p>The demo is built out of ordinary services, and a conversation passes through these:</p>
        <ul>
          <li><strong>OpenAI</strong> reads each message and writes the reply.</li>
          <li><strong>Supabase</strong> holds the database, until the conversation is deleted.</li>
          <li><strong>Vercel</strong> hosts this site and keeps the usual server request logs.</li>
          <li><strong>n8n</strong>, self-hosted, runs the steps in between.</li>
          <li><strong>Slack</strong> receives the owner alerts described above, in a private channel.</li>
        </ul>
        <p>Each handles the data under its own terms. Nothing is sold, shared or used for advertising.</p>
      </Section>

      <Section title="Getting something removed">
        <p>
          Your conversation disappears on its own within 24 hours. If you want it gone sooner, or you have a question
          about any of this, get in touch through{" "}
          <a className="underline" href="https://workwithzeki.vercel.app" target="_blank" rel="noreferrer">
            workwithzeki.vercel.app
          </a>
          .
        </p>
      </Section>
    </LegalPage>
  );
}
