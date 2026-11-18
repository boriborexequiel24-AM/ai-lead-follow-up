"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import type { ThreadData } from "@/lib/types";
import { Conversation } from "./Conversation";
import { LeadFacts } from "./LeadFacts";

// The visitor's private conversation with the agent. Polls for new messages
// (follow-ups arrive on their own), lets the visitor write back as the
// customer, and lets them play the owner when a price needs approval.

const POLL_MS = 4000;

export function ThreadView({ token, initial, maxMessages }: { token: string; initial: ThreadData; maxMessages: number }) {
  const [thread, setThread] = useState(initial);
  const [draft, setDraft] = useState("");
  // The message being sent, and how many lead messages the thread had then,
  // so it stops showing as soon as a refresh brings back the saved copy.
  const [pending, setPending] = useState<{ text: string; before: number } | null>(null);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState("");
  // Set in the browser only, so the server and browser render the same HTML.
  const [now, setNow] = useState<number | null>(null);
  const bottom = useRef<HTMLDivElement>(null);
  const count = thread.events.length;
  const leadMessages = thread.events.filter((e) => e.kind === "lead").length;

  const refresh = useCallback(async () => {
    try {
      const res = await fetch(`/api/thread/${token}`, { cache: "no-store" });
      if (res.ok) setThread(await res.json());
    } catch {
      // Try again on the next tick.
    }
  }, [token]);

  useEffect(() => {
    const poll = setInterval(() => {
      if (!document.hidden) refresh();
    }, POLL_MS);
    setNow(Date.now());
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => {
      clearInterval(poll);
      clearInterval(tick);
    };
  }, [refresh]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [count, pending, working]);

  async function post(path: string, body: unknown) {
    setWorking(true);
    setError("");
    try {
      const res = await fetch(`/api/thread/${token}/${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) setError(data.message || "Something went wrong. Please try again.");
      return res.ok;
    } catch {
      setError("Couldn't reach the server. Check your connection and try again.");
      return false;
    } finally {
      await refresh();
      setWorking(false);
    }
  }

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const message = draft.trim();
    if (!message || working) return;
    setPending({ text: message, before: leadMessages });
    setDraft("");
    const ok = await post("reply", { message });
    if (!ok) setDraft(message);
    setPending(null);
  }

  const { lead, pending_approval: approval } = thread;
  const left = Math.max(0, maxMessages - thread.visitor_messages);
  const agentReplies = lead.status !== "handed_off" && lead.end_state !== "unsubscribed" && lead.end_state !== "spam";
  const nextIn = lead.next_follow_up_at && now !== null ? Math.max(0, Math.round((new Date(lead.next_follow_up_at).getTime() - now) / 1000)) : null;
  const demoClock = thread.clock.mode === "demo";

  return (
    <div className="grid items-start gap-6 lg:grid-cols-[1fr_20rem]">
      <section className="rounded-2xl border border-stone-200 bg-stone-100/60 p-4 sm:p-6">
        <div className="mb-5 flex flex-wrap items-center justify-between gap-2 border-b border-stone-200 pb-4">
          <div>
            <h1 className="text-lg font-semibold">Your conversation with Copperline</h1>
            <p className="text-xs text-stone-500">Private link, only you can see this. Deleted after 24 hours.</p>
          </div>
          <Link href="/" className="text-sm text-copper-700 hover:underline">
            Try another scenario
          </Link>
        </div>

        <Conversation events={thread.events} mode="customer" />

        {pending && leadMessages === pending.before && (
          <div className="mt-4 flex justify-end">
            <div className="max-w-[85%] whitespace-pre-wrap rounded-2xl rounded-br-sm bg-copper-600/80 px-4 py-2.5 text-sm text-white">
              {pending.text}
            </div>
          </div>
        )}
        {working && (
          <div className="mt-4 inline-flex items-center gap-1 rounded-2xl rounded-bl-sm border border-stone-200 bg-white px-4 py-3" aria-label="The agent is replying">
            <span className="typing-dot size-1.5 rounded-full bg-stone-400" />
            <span className="typing-dot size-1.5 rounded-full bg-stone-400" />
            <span className="typing-dot size-1.5 rounded-full bg-stone-400" />
          </div>
        )}

        {approval && (
          <div className="mt-6 rounded-xl border-2 border-dashed border-amber-300 bg-amber-50 p-4">
            <p className="text-xs font-semibold uppercase tracking-wide text-amber-700">You&apos;re the owner now</p>
            <p className="mt-1 text-sm text-amber-900">
              The agent drafted a reply with a price from the sample price sheet. Prices never go out without the
              owner&apos;s OK, so this would normally wait in Slack for a click. Approve it to send it to the customer
              (you), or reject it and the lead is handed to a person.
            </p>
            <blockquote className="mt-3 whitespace-pre-wrap rounded-lg border-l-4 border-amber-400 bg-white px-3 py-2 text-sm text-stone-800">
              {approval.reply}
            </blockquote>
            <div className="mt-3 flex flex-wrap gap-2">
              <button
                onClick={() => post("approval", { approved: true })}
                disabled={working}
                className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
              >
                Approve and send
              </button>
              <button
                onClick={() => post("approval", { approved: false })}
                disabled={working}
                className="rounded-lg border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-700 hover:border-red-400 hover:text-red-700 disabled:opacity-60"
              >
                Reject
              </button>
            </div>
          </div>
        )}

        <div ref={bottom} />

        {error && <p className="mt-4 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

        <form onSubmit={send} className="mt-6 border-t border-stone-200 pt-4">
          <label htmlFor="reply" className="sr-only">Your reply</label>
          <div className="flex gap-2">
            <textarea
              id="reply"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  e.currentTarget.form?.requestSubmit();
                }
              }}
              disabled={working || left === 0}
              maxLength={2000}
              rows={2}
              placeholder={left === 0 ? "This demo thread is full." : "Write back as the customer..."}
              className="min-h-11 flex-1 resize-y rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm outline-none focus:border-copper-500 focus:ring-2 focus:ring-copper-100 disabled:bg-stone-100"
            />
            <button
              type="submit"
              disabled={working || !draft.trim() || left === 0}
              className="self-end rounded-lg bg-copper-600 px-4 py-2 text-sm font-semibold text-white hover:bg-copper-700 disabled:opacity-50"
            >
              Send
            </button>
          </div>
          <p className="mt-2 text-xs text-stone-400">
            {left} of {maxMessages} demo messages left.
            {!agentReplies && " A person has this conversation now, so the agent won't reply."}
          </p>
        </form>
      </section>

      <aside className="space-y-4 lg:sticky lg:top-6">
        <LeadFacts lead={lead}>
          {nextIn !== null && (
            <div className="mt-4 rounded-lg bg-sky-50 p-3 text-xs text-sky-800">
              <p className="font-semibold">
                {nextIn > 0 ? `Next follow-up in about ${nextIn}s` : "Follow-up going out now..."}
              </p>
              <p className="mt-1">
                {lead.follow_ups_sent < 3
                  ? `Follow-up ${lead.follow_ups_sent + 1} of 3 if you don't reply.`
                  : "No reply to 3 follow-ups, so the lead will be closed."}
                {demoClock && ` Demo clock: 1 day = ${thread.clock.minutes_per_day} min.`}
              </p>
            </div>
          )}
        </LeadFacts>
        <Tips status={lead.status} endState={lead.end_state} />
      </aside>
    </div>
  );
}

function Tips({ status, endState }: { status: string; endState: string | null }) {
  let tips: string[];
  if (status === "booked") {
    tips = ["Ask to move the visit to another time.", "Ask about the warranty or financing.", "Say you no longer need it."];
  } else if (status === "waiting_approval") {
    tips = [
      "Approve the price above as the owner, and it goes to the customer (you).",
      "Or reject it: nothing is sent and the lead is handed to a person.",
      "You can also keep chatting while it waits.",
    ];
  } else if (status === "handed_off") {
    tips = ["A person has taken over and the owner was alerted in Slack. The agent stays quiet from here.", "Try another scenario from the home page."];
  } else if (status === "closed") {
    tips =
      endState === "unsubscribed"
        ? ["You asked not to be contacted, so the agent won't write again."]
        : ["The conversation is closed. Write again and the agent picks it back up."];
  } else {
    tips = [
      "Pick one of the offered times.",
      "Ask how much it will cost.",
      "Ask something else, like whether they do financing.",
      "Say you found someone else, or ask them to stop emailing.",
      "Stop replying and watch the follow-ups arrive.",
    ];
  }
  return (
    <div className="rounded-xl border border-stone-200 bg-white p-4 text-sm">
      <h2 className="font-semibold">Things to try</h2>
      <ul className="mt-2 list-disc space-y-1 pl-5 text-stone-600">
        {tips.map((t) => (
          <li key={t}>{t}</li>
        ))}
      </ul>
    </div>
  );
}
