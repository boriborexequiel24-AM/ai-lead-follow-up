import Link from "next/link";

// Shared shell for the privacy and terms pages: a readable column with plain headings.

export function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3">
      <h2 className="text-base font-semibold text-stone-900">{title}</h2>
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
    <article className="max-w-2xl space-y-8 [&_a]:text-copper-700 [&_li]:text-stone-600 [&_p]:text-stone-600 [&_ul]:list-disc [&_ul]:space-y-2 [&_ul]:pl-5">
      <header className="space-y-3">
        <h1 className="text-3xl font-semibold tracking-tight">{title}</h1>
        <p className="text-sm text-stone-500">Last updated {updated}</p>
        <p>{intro}</p>
      </header>

      {children}

      <footer className="border-t border-stone-200 pt-6 text-sm">
        <Link href="/" className="text-copper-700 hover:underline">
          Back to the demo
        </Link>
      </footer>
    </article>
  );
}
