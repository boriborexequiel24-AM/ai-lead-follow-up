import "server-only";

// Server-side settings. Nothing here is ever sent to the browser.

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing environment variable ${name}. See dashboard/.env.example.`);
  }
  return value;
}

function number(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export const env = {
  supabaseUrl: () => required("SUPABASE_URL").replace(/\/$/, ""),
  supabaseServiceKey: () => required("SUPABASE_SERVICE_ROLE_KEY"),
  n8nBaseUrl: () => required("N8N_BASE_URL").replace(/\/$/, ""),
  n8nWebhookSecret: () => required("N8N_WEBHOOK_SECRET"),
  ipHashSalt: () => required("IP_HASH_SALT"),
  leadsPerIpPerDay: () => number("DEMO_LEADS_PER_IP_PER_DAY", 3),
  messagesPerThread: () => number("DEMO_MESSAGES_PER_THREAD", 10),
  dailyAiCallCap: () => number("DEMO_DAILY_AI_CALL_CAP", 300),
};
