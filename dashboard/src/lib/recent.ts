// The visitor's own recent threads, kept only in their browser so they can
// find their way back. Storage can be blocked, so every access is guarded.

const KEY = "copperline-threads";
export type RecentThread = { token: string; preview: string; at: number };

export function recentThreads(): RecentThread[] {
  try {
    const list = JSON.parse(localStorage.getItem(KEY) || "[]");
    const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
    return Array.isArray(list) ? list.filter((t) => t && typeof t.token === "string" && t.at > dayAgo) : [];
  } catch {
    return [];
  }
}

export function rememberThread(token: string, message: string) {
  try {
    const list = [{ token, preview: message.slice(0, 80), at: Date.now() }, ...recentThreads().filter((t) => t.token !== token)];
    localStorage.setItem(KEY, JSON.stringify(list.slice(0, 5)));
  } catch {
    // Storage is blocked: the thread still works through its link.
  }
}
