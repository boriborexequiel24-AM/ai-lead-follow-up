"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { recentThreads, type RecentThread } from "@/lib/recent";

/** Links back to the visitor's own conversations from the last 24 hours, if any. */
export function RecentThreads() {
  const [threads, setThreads] = useState<RecentThread[]>([]);
  useEffect(() => setThreads(recentThreads()), []);
  if (!threads.length) return null;
  return (
    <div className="rounded-xl border border-stone-200 bg-white p-4 text-sm">
      <p className="font-medium">Your conversations</p>
      <ul className="mt-2 space-y-1">
        {threads.map((t) => (
          <li key={t.token}>
            <Link href={`/t/${t.token}`} className="text-copper-700 hover:underline">
              &ldquo;{t.preview}
              {t.preview.length >= 80 ? "..." : ""}&rdquo;
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
