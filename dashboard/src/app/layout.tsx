import type { Metadata } from "next";
import { Archivo, Inter } from "next/font/google";
import Link from "next/link";
import { Container, LogoMark } from "@/components/Brand";
import { COMPANY } from "@/lib/company";
import "./globals.css";

const inter = Inter({ variable: "--font-inter", subsets: ["latin"] });
const archivo = Archivo({ variable: "--font-archivo", subsets: ["latin"], weight: ["700", "800", "900"] });

export const metadata: Metadata = {
  title: "Lead Follow-Up Agent | AI demo for a home services company",
  description:
    "Send a quote request to a made-up plumbing company and watch an AI agent reply in seconds, book a visit, ask the owner before quoting a price, and follow up when you go quiet. A portfolio demo by Exequiel Boribor.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    // The font variables go on <html> because the theme in globals.css reads them at the root.
    <html lang="en" className={`${inter.variable} ${archivo.variable}`}>
      <body className="flex min-h-screen flex-col font-sans">
        <div className="bg-navy-950 text-[13px] text-navy-200">
          <Container className="flex flex-wrap items-center justify-between gap-x-6 gap-y-2 py-2">
            <p>
              <span className="mr-2 rounded bg-copper-300 px-2 py-0.5 font-semibold text-navy-950">Live demo</span>
              You&apos;re the customer of a made-up company. An AI agent answers.
            </p>
            <nav className="flex flex-wrap gap-x-5 gap-y-1">
              <Link href="/owner" className="hover:text-white">Owner view</Link>
              <Link href="/#how-it-works" className="hover:text-white">How it works</Link>
              <a href="https://workwithzeki.vercel.app" target="_blank" rel="noreferrer" className="hover:text-white">
                Built by Exequiel Boribor
              </a>
            </nav>
          </Container>
        </div>

        <header className="border-b border-navy-800 bg-navy-900 text-white">
          <Container className="flex flex-wrap items-center justify-between gap-4 py-4 sm:py-[18px]">
            <Link href="/" className="flex items-center gap-3" aria-label={`${COMPANY.name}, home`}>
              <LogoMark />
              <span>
                <span className="block font-display text-xl font-extrabold leading-tight tracking-[0.2px]">COPPERLINE</span>
                <span className="block text-xs tracking-[1.5px] text-navy-300">PLUMBING &amp; AIR &middot; DENVER</span>
              </span>
            </Link>
            <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
              <span className="text-sm text-navy-300">
                Emergencies 24/7 <strong className="whitespace-nowrap text-white">{COMPANY.emergencyPhone}</strong>
              </span>
              <Link
                href="/#request"
                className="rounded-lg bg-copper-600 px-[18px] py-3 text-sm font-semibold text-white transition hover:bg-copper-700"
              >
                Request a visit
              </Link>
            </div>
          </Container>
        </header>

        <main className="flex-1">{children}</main>

        <footer className="bg-navy-950 text-[13px] text-navy-300">
          <Container className="flex flex-wrap justify-between gap-4 py-6">
            <span>
              {COMPANY.name} is fictional. Its numbers, prices and visit times are made up, and no one will come to your
              house.
            </span>
            <span className="flex gap-4">
              <Link href="/privacy" className="hover:text-white">Privacy</Link>
              <Link href="/terms" className="hover:text-white">Terms</Link>
            </span>
          </Container>
        </footer>
      </body>
    </html>
  );
}
