import Link from "next/link";
import { Container, PageHero } from "./Brand";

// Shared shell for the privacy and terms pages: the navy band, then a
// readable column with plain headings.

export function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3">
      <h2 className="font-display text-xl font-extrabold text-navy-900">{title}</h2>
      {children}
    </section>
  );
}

export function LegalPage({
  title,
  updated,
  intro,
  children,
}: {
  title: string;
  updated: string;
  intro: string;
  children: React.ReactNode;
}) {
  return (
    <>
      <PageHero eyebrow={`Last updated ${updated}`} title={title}>
        {intro}
      </PageHero>
      <Container className="py-10 sm:py-12">
        <article className="max-w-2xl space-y-8 leading-relaxed [&_a]:text-copper-600 [&_a:hover]:text-copper-700 [&_li]:text-ink-600 [&_p]:text-ink-600 [&_strong]:text-navy-900 [&_ul]:list-disc [&_ul]:space-y-2 [&_ul]:pl-5 [&_ul]:marker:text-copper-600">
          {children}

          <footer className="border-t border-sand-200 pt-6 text-sm">
            <Link href="/" className="font-semibold hover:underline">
              Back to the demo
            </Link>
          </footer>
        </article>
      </Container>
    </>
  );
}
