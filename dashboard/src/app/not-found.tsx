import Link from "next/link";
import { Container } from "@/components/Brand";

export default function NotFound() {
  return (
    <section className="bg-navy-900 text-white">
      <Container className="py-20 text-center sm:py-28">
        <p className="text-[13px] font-semibold uppercase tracking-[2px] text-copper-300">Page not found</p>
        <h1 className="mt-3 font-display text-4xl font-black leading-tight sm:text-5xl">Nothing here</h1>
        <p className="mx-auto mt-4 max-w-md text-navy-200">
          This page doesn&apos;t exist, or the conversation was deleted. Demo conversations are removed after 24 hours.
        </p>
        <Link
          href="/#request"
          className="mt-8 inline-block rounded-lg bg-copper-600 px-[18px] py-3 text-sm font-semibold text-white transition hover:bg-copper-700"
        >
          Start a new request
        </Link>
      </Container>
    </section>
  );
}
