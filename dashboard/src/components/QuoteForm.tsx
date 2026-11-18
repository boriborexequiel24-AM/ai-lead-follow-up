"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { SCENARIOS, type Scenario } from "@/lib/company";
import { rememberThread } from "@/lib/recent";

// The quote request form, with buttons that fill it with a ready-made lead.
// Sending it waits for the agent's first reply (a few seconds), then opens
// the visitor's private thread.

const STEPS = [
  "Reading your request",
  "Checking the service area",
  "Choosing the next step",
  "Checking the reply against the rules",
  "Writing back",
];

const empty = { name: "", email: "", phone: "", zip: "", message: "" };

export function QuoteForm() {
  const router = useRouter();
  const [form, setForm] = useState(empty);
  const [picked, setPicked] = useState<Scenario | null>(null);
  const [sending, setSending] = useState(false);
  const [step, setStep] = useState(0);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!sending) return;
    setStep(0);
    const timer = setInterval(() => setStep((s) => Math.min(s + 1, STEPS.length - 1)), 1400);
    return () => clearInterval(timer);
  }, [sending]);

  const set = (field: keyof typeof empty) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    setForm({ ...form, [field]: e.target.value });
    setPicked(null);
  };

  function pickScenario(s: Scenario) {
    setForm({ name: s.name, email: s.email, phone: "", zip: s.zip, message: s.message });
    setPicked(s);
    setError("");
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSending(true);
    setError("");
    try {
      const res = await fetch("/api/lead", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(form),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || !data.token) {
        setError(data.message || "Something went wrong. Please try again.");
        setSending(false);
        return;
      }
      rememberThread(data.token, form.message);
      router.push(`/t/${data.token}`);
    } catch {
      setError("Couldn't reach the server. Check your connection and try again.");
      setSending(false);
    }
  }

  const input =
    "w-full rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm outline-none focus:border-copper-500 focus:ring-2 focus:ring-copper-100";

  return (
    <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6">
      <h2 className="text-lg font-semibold">Request a quote or a visit</h2>
      <p className="mt-1 text-sm text-stone-500">We usually reply within a minute, day or night.</p>

      <div className="mt-4">
        <p className="text-xs font-medium uppercase tracking-wide text-stone-500">Try a scenario</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {SCENARIOS.map((s) => (
            <button
              key={s.id}
              type="button"
              onClick={() => pickScenario(s)}
              disabled={sending}
              className={`rounded-full border px-3 py-1 text-xs font-medium transition ${
                picked?.id === s.id
                  ? "border-copper-500 bg-copper-50 text-copper-700"
                  : "border-stone-300 text-stone-700 hover:border-copper-500 hover:text-copper-700"
              }`}
            >
              {s.label}
            </button>
          ))}
        </div>
        {picked && <p className="mt-2 text-xs text-copper-700">What to watch: {picked.shows}</p>}
      </div>

      <form onSubmit={submit} className="mt-5 space-y-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block text-sm">
            <span className="mb-1 block text-stone-600">Name</span>
            <input className={input} value={form.name} onChange={set("name")} maxLength={100} autoComplete="off" />
          </label>
          <label className="block text-sm">
            <span className="mb-1 block text-stone-600">Email</span>
            <input className={input} type="email" required value={form.email} onChange={set("email")} maxLength={200}
              placeholder="you@example.com" autoComplete="off" />
          </label>
          <label className="block text-sm">
            <span className="mb-1 block text-stone-600">
              Phone <span className="text-stone-400">(optional)</span>
            </span>
            <input className={input} value={form.phone} onChange={set("phone")} maxLength={30} autoComplete="off" />
          </label>
          <label className="block text-sm">
            <span className="mb-1 block text-stone-600">Zip code</span>
            <input className={input} value={form.zip} onChange={set("zip")} inputMode="numeric" pattern="[0-9]{5}"
              maxLength={5} placeholder="80210" autoComplete="off" />
          </label>
        </div>
        <label className="block text-sm">
          <span className="mb-1 block text-stone-600">What do you need help with?</span>
          <textarea className={`${input} min-h-28`} required value={form.message} onChange={set("message")}
            maxLength={2000} placeholder="Our water heater is leaking from the bottom..." />
        </label>

        <p className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
          This is a demo, so please use made-up details. Nothing is emailed to the address you enter, and the
          conversation is deleted after 24 hours.
        </p>

        {error && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

        <button
          type="submit"
          disabled={sending}
          className="w-full rounded-lg bg-copper-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-copper-700 disabled:opacity-70"
        >
          {sending ? `${STEPS[step]}...` : "Send request"}
        </button>
      </form>
    </div>
  );
}
