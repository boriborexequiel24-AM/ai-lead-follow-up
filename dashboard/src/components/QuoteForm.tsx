"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { SCENARIOS, type Scenario } from "@/lib/company";
import { rememberThread } from "@/lib/recent";
import { Container } from "./Brand";

// The "Try a real situation" tiles and the quote request form. A tile fills
// the form with a ready-made lead. Sending it waits for the agent's first
// reply (a few seconds), then opens the visitor's private thread. `aside`
// sits next to the form (the timeline).

const STEPS = [
  "Reading your request",
  "Checking the service area",
  "Choosing the next step",
  "Checking the reply against the rules",
  "Writing back",
];

const empty = { name: "", email: "", phone: "", zip: "", message: "" };

const icon = { width: 26, height: 26, viewBox: "0 0 24 24", fill: "none", stroke: "#B85A22", strokeWidth: 1.8, "aria-hidden": true };

const ICONS: Record<string, React.ReactNode> = {
  "burst-pipe": (
    <svg {...icon}><path d="M12 3c3 4.5 6 7.5 6 11a6 6 0 0 1-12 0c0-3.5 3-6.5 6-11z" /></svg>
  ),
  "tune-up": (
    <svg {...icon}><rect x="4" y="5" width="16" height="15" rx="2" /><path d="M4 10h16M9 3v4M15 3v4" /></svg>
  ),
  price: (
    <svg {...icon}><path d="M12 3v18M16 7.5c0-1.9-1.8-3-4-3s-4 1.1-4 3 1.8 2.6 4 3 4 1.3 4 3.2-1.8 3-4 3-4-1.1-4-3" /></svg>
  ),
  "out-of-area": (
    <svg {...icon}><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z" /><circle cx="12" cy="9.5" r="2.5" /></svg>
  ),
  vague: (
    <svg {...icon}><circle cx="12" cy="12" r="9" /><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6M12 17h.01" /></svg>
  ),
};

export function QuoteForm({ aside }: { aside?: React.ReactNode }) {
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
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
    // Bring the filled form into view when it's off screen (always the case on phones).
    const top = formRef.current?.getBoundingClientRect().top;
    if (top !== undefined && (top < 0 || top > window.innerHeight * 0.5)) {
      formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
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
    "w-full rounded-[10px] border border-sand-300 bg-white p-3 text-base text-navy-900 outline-none transition placeholder:text-ink-400 focus:border-copper-600 focus:ring-2 focus:ring-copper-100";
  const field = "flex flex-col gap-1.5 text-sm text-ink-600";

  return (
    <>
      <section>
        <Container className="pt-14">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <h2 className="font-display text-[28px] font-extrabold leading-tight sm:text-[34px]">Try a real situation</h2>
            <p className="text-[15px] text-ink-600">Each one tests a different decision the agent has to make.</p>
          </div>
          <div className="mt-[22px] grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-3.5">
            {SCENARIOS.map((s) => {
              const on = picked?.id === s.id;
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => pickScenario(s)}
                  disabled={sending}
                  aria-pressed={on}
                  className={`flex flex-col items-start rounded-[14px] border bg-white p-5 text-left transition hover:-translate-y-0.5 hover:border-copper-600 hover:shadow-md disabled:opacity-60 ${
                    on ? "border-copper-600 ring-2 ring-copper-600" : "border-sand-200"
                  }`}
                >
                  {ICONS[s.id]}
                  <span className="mt-3 block text-[17px] font-bold">{s.label}</span>
                  <span className="mt-1 block text-sm leading-[1.45] text-ink-600">{s.shows}</span>
                </button>
              );
            })}
          </div>
        </Container>
      </section>

      <section id="request" className="scroll-mt-4">
        <Container className="flex flex-wrap items-start gap-8 pb-16 pt-12">
          <form
            ref={formRef}
            onSubmit={submit}
            className="flex min-w-0 flex-[1_1_460px] scroll-mt-4 flex-col gap-3.5 rounded-[18px] border border-sand-200 bg-white p-5 sm:p-7"
          >
            <h2 className="font-display text-[26px] font-extrabold leading-tight">Tell us what&apos;s going on</h2>
            {picked && (
              <p className="rounded-[10px] border border-copper-200 bg-copper-50 px-3 py-2.5 text-sm text-copper-900">
                <span className="font-semibold">{picked.label}.</span> What to watch: {picked.shows}
              </p>
            )}
            <div className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-3">
              <label className={field}>
                Name
                <input className={input} value={form.name} onChange={set("name")} maxLength={100} placeholder="Sam Ortega"
                  autoComplete="off" />
              </label>
              <label className={field}>
                Email
                <input className={input} type="email" required value={form.email} onChange={set("email")} maxLength={200}
                  placeholder="you@example.com" autoComplete="off" />
              </label>
              <label className={field}>
                Zip code
                <input className={input} value={form.zip} onChange={set("zip")} inputMode="numeric" pattern="[0-9]{5}"
                  maxLength={5} placeholder="80210" autoComplete="off" />
              </label>
              <label className={field}>
                Phone (optional)
                <input className={input} value={form.phone} onChange={set("phone")} maxLength={30} autoComplete="off" />
              </label>
            </div>
            <label className={field}>
              What do you need help with?
              <textarea className={`${input} min-h-[110px]`} required value={form.message} onChange={set("message")}
                maxLength={2000} placeholder="Our water heater is leaking from the bottom..." />
            </label>

            <p className="rounded-[10px] bg-[#FBF1DA] px-3 py-2.5 text-[13px] text-[#7A5A12]">
              Demo only: use made-up details. Nothing is emailed to you, and the chat is deleted after 24 hours.
            </p>

            {error && <p className="rounded-[10px] bg-red-50 px-3 py-2.5 text-sm text-red-700">{error}</p>}

            <button
              type="submit"
              disabled={sending}
              className="rounded-[10px] bg-copper-600 p-[15px] text-base font-bold text-white transition hover:bg-copper-700 disabled:opacity-75"
            >
              {sending ? `${STEPS[step]}...` : "Send and watch it reply"}
            </button>
          </form>

          {aside}
        </Container>
      </section>
    </>
  );
}
