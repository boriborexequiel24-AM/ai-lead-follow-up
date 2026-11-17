# Setup

Every value below goes in `.env` (copy it from `.env.example`). Never commit `.env`.

Later sections (running migrations, deploying workflows, the dashboard) get added as each phase is built.

## 1. Supabase
This demo shares the invoice project's Supabase project (the free plan allows two active projects). Everything lives in its own schema, `leads`, so the two demos never touch each other's tables.

- [ ] Open the **invoice project** at supabase.com.
- [ ] Go to **SQL Editor**, click **New query**, paste all of `supabase/migrations/20261117000000_create_leads_schema.sql`, and click **Run**. It should say "Success. No rows returned".
- [ ] Go to **Project Settings > Data API**. In **Exposed schemas**, add `leads` next to `public` (keep `public`, the invoice demo needs it) and click **Save**. Without this, the dashboard and n8n get a "schema must be one of the following" error.
- [ ] On the same page, turn **off** "Automatically expose new tables" and click **Save**. Supabase recommends this, and it stops new tables from being readable with the public key before we decide what's public. Existing invoice tables keep their access. Migrations here also revoke public access on each new table, so this is a second lock, not the only one.
- [ ] Check it worked: in SQL Editor, run `select schema_name from information_schema.schemata where schema_name = 'leads';`. It should return one row.
- [ ] Copy `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` from the invoice project's `.env`. They're the same keys.

Later migrations in `supabase/migrations/` are run the same way, in name order.

## 2. OpenAI
- [ ] Reuse your existing API key, or create a separate one for this project at platform.openai.com so its cost shows separately. Put it in `OPENAI_API_KEY`.
- [ ] Check the monthly budget limit under Settings > Limits covers both public demos. Visitors chatting with this one means more AI calls than the invoice demo.
- [ ] Leave `OPENAI_MODEL` empty for now. It's picked in phase 3 from the eval.

## 3. n8n (self-hosted)
- [ ] Copy `N8N_BASE_URL` and `N8N_API_KEY` from the invoice project's `.env`.
- [ ] Generate a new long random string for `N8N_WEBHOOK_SECRET`. Don't reuse the invoice one, so each demo can only call its own webhooks.

## 4. Slack
This needs its own Slack app: a Slack app has only one interactivity URL, and the invoice app's already points at the invoice workflow.

- [ ] Use the same demo workspace as the invoice project.
- [ ] At api.slack.com/apps, click **Create New App**, then **Paste a manifest**, and use:
  ```json
  {
    "display_information": { "name": "Lead Assistant" },
    "features": { "bot_user": { "display_name": "Lead Assistant", "always_online": true } },
    "oauth_config": { "scopes": { "bot": ["chat:write", "chat:write.public", "channels:manage", "channels:read"] } },
    "settings": { "org_deploy_enabled": false, "socket_mode_enabled": false, "token_rotation_enabled": false }
  }
  ```
- [ ] **Install to Workspace**, then copy the bot token (`xoxb-...`) into `SLACK_BOT_TOKEN` and the **Signing Secret** (Basic Information) into `SLACK_SIGNING_SECRET`.
- [ ] Create `#lead-approvals` (price approvals) and `#lead-alerts` (emergencies and errors), and copy their channel IDs into `.env`. With the `channels:manage` and `channels:read` scopes, Claude can do this step with the bot token (done this way on 2026-11-17).
- [ ] Interactivity gets turned on in phase 6, once the approval workflow exists.

## 5. Gmail
**Anything this label picks up becomes a lead the agent replies to.** Treat applying it as "send this to the agent".

The intake inbox is the same Gmail account the invoice demo uses, so its n8n Gmail credential is reused. The two demos stay apart because each only reads its own label.

- [ ] In that account, create a label named `lead-demo`. Like `invoice-demo`, it's a name no existing filter would ever apply.
- [ ] Do **not** add a filter that applies it automatically. Apply it by hand.
- [ ] Put the account's address in `GMAIL_INTAKE_ADDRESS`.
- [ ] Send test leads from a different address of yours, and put only that address in `OUTBOUND_EMAIL_ALLOWLIST`. Separate senders mean the agent's own emails never look like a lead's reply.
- [ ] In phase 5, check the invoice demo's Gmail credential in n8n is signed in to this account before reusing it.
