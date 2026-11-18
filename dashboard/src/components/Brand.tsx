// Shared Copperline brand pieces: the logo mark, the page width, and the
// navy band that opens every page.

export function LogoMark({ size = 40 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 40 40" aria-hidden="true" className="shrink-0">
      <rect width="40" height="40" rx="10" fill="#C9682F" />
      <path
        d="M20 8c4 6 8 10 8 15a8 8 0 0 1-16 0c0-5 4-9 8-15z"
        fill="none"
        stroke="#fff"
        strokeWidth="2.6"
        strokeLinejoin="round"
      />
    </svg>
  );
}

/** The 1200px column every section sits in, with a 16px gutter on phones. */
export function Container({ className = "", children }: { className?: string; children: React.ReactNode }) {
  return <div className={`mx-auto w-full max-w-[1200px] px-4 sm:px-6 ${className}`}>{children}</div>;
}

/** The navy band under the header on inner pages: a copper eyebrow, a big title and an intro. */
export function PageHero({
  eyebrow,
  title,
  compact = false,
  actions,
  children,
}: {
  eyebrow: string;
  title: React.ReactNode;
  /** A shorter band, for pages where the content should start near the top. */
  compact?: boolean;
  /** Links or buttons on the right of the band. */
  actions?: React.ReactNode;
  children?: React.ReactNode;
}) {
  return (
    <section className="bg-navy-900 text-white">
      <Container
        className={`flex flex-wrap items-end justify-between gap-x-8 gap-y-4 ${compact ? "pb-8 pt-7" : "pb-12 pt-10 sm:pb-14 sm:pt-12"}`}
      >
        <div className="min-w-0 max-w-3xl">
          <p className="text-[13px] font-semibold uppercase tracking-[2px] text-copper-300">{eyebrow}</p>
          <h1
            className={`mt-3 font-display font-black leading-[1.02] tracking-tight ${
              compact ? "text-[28px] sm:text-4xl" : "text-4xl sm:text-5xl"
            }`}
          >
            {title}
          </h1>
          {children && (
            <div className={`mt-3 max-w-2xl leading-relaxed text-navy-200 ${compact ? "text-sm sm:text-base" : "text-base sm:text-lg"}`}>
              {children}
            </div>
          )}
        </div>
        {actions && <div className="flex flex-wrap gap-3">{actions}</div>}
      </Container>
    </section>
  );
}

/** A light outline button for the navy band. */
export const navyButton =
  "inline-flex rounded-lg border border-navy-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:border-copper-300 hover:text-copper-300";

/** A white card with the warm border used across the site. */
export const card = "rounded-2xl border border-sand-200 bg-white";
