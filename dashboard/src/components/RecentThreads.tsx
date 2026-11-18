"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { recentThreads, type RecentThread } from "@/lib/recent";

/** Links back to the visitor's own conversations from the last 24 hours, if any. Sits on the navy hero. */
export function RecentThreads() {
  const [threads, setThreads] = useState<RecentThread[]>([]);
  useEffect(() => setThreads(recentThreads()), []);
  if (!threads.length) return null;
  return (
    <div className="mt-8 max-w-[520px] rounded-xl border border-navy-700 bg-navy-950/40 p-4 text-sm">
      <p className="font-semibold text-white">Pick up where you left off</p>
      <ul className="mt-2 space-y-1.5">
        {threads.map((t) => (
          <li key={t.token} className="truncate">
            <Link href={`/t/${t.token}`} className="text-copper-300 hover:text-white hover:underline">
              &ldquo;{t.preview}
              {t.preview.length >= 80 ? "..." : ""}&rdquo;
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
