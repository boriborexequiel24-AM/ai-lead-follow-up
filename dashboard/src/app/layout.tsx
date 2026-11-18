import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Link from "next/link";
import { COMPANY } from "@/lib/company";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Lead Follow-Up Agent | AI demo for a home services company",
  description:
    "Send a quote request to a made-up plumbing company and watch an AI agent reply in seconds, book a visit, ask the owner before quoting a price, and follow up when you go quiet. A portfolio demo by Exequiel Boribor.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className={`${geistSans.variable} ${geistMono.variable} min-h-screen font-sans`}>
        <div className="bg-stone-900 text-stone-200">
          <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-x-6 gap-y-1 px-4 py-2 text-xs sm:px-6">
            <p>
              <span className="mr-2 rounded bg-copper-500 px-1.5 py-0.5 font-semibold text-white">Live demo</span>
              An AI agent answering leads for a made-up plumbing company.
            </p>
            <nav className="flex gap-4">
              <Link href="/owner" className="hover:text-white">Owner view</Link>
              <Link href="/#how-it-works" className="hover:text-white">How it works</Link>
              <a href="https://workwithzeki.vercel.app" target="_blank" rel="noreferrer" className="hover:text-white">
                Built by Exequiel Boribor
              </a>
            </nav>
          </div>
        </div>

        <header className="border-b border-stone-200 bg-white">
          <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3 sm:px-6">
            <Link href="/" className="flex items-center gap-3">
              <span className="grid size-9 place-items-center rounded-lg bg-copper-600 text-sm font-bold text-white">C</span>
              <span>
                <span className="block text-sm font-semibold leading-tight">{COMPANY.name}</span>
                <span className="block text-xs text-stone-500">{COMPANY.area}</span>
              </span>
            </Link>
            <div className="hidden text-right text-xs sm:block">
              <p className="font-semibold text-stone-800">{COMPANY.phone}</p>
              <p className="text-stone-500">Emergencies 24/7: {COMPANY.emergencyPhone}</p>
            </div>
          </div>
        </header>

        <main className="mx-auto max-w-6xl px-4 py-8 sm:px-6">{children}</main>

        <footer className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-4 gap-y-2 px-4 pb-10 text-xs text-stone-500 sm:px-6">
          <span>
            {COMPANY.name} is fictional. Its phone numbers, prices and visit times are made up, and no one will come to
            your house.
          </span>
          <span className="flex gap-4">
            <Link href="/privacy" className="hover:text-copper-600">Privacy</Link>
            <Link href="/terms" className="hover:text-copper-600">Terms</Link>
          </span>
        </footer>
      </body>
    </html>
  );
}
