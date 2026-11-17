"""Build the n8n workflows and deploy them.

1. Agent turn: one webhook for every incoming message (the website form, the
   web thread, and email via workflow 2). Stores the message, runs the read
   and decide prompts from agent/ (the same files scripts/eval_agent.py tests),
   applies the guardrails in the database, replies, and alerts Slack.
2. Email intake: every minute, sends new lead-demo emails and replies in known
   lead threads to workflow 1 (scripts/email_intake_workflow.py).

Output is saved to n8n/workflows/ (with private values replaced) so it is
versioned in git.

Usage (from the project root):
    python scripts/build_n8n_workflows.py              # build the JSON only
    python scripts/build_n8n_workflows.py --deploy     # also create/update them in n8n
    python scripts/build_n8n_workflows.py --deploy --activate

Credentials: Supabase, OpenAI and Gmail are shared with the invoice demo and
copied from its workflows. The Slack bot token and the webhook secret are
this project's own; if no workflow has them yet, they're created in n8n from
.env. Nothing else is ever created or changed outside this project's workflows.
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent"
WORKFLOW_DIR = ROOT / "n8n" / "workflows"

READ_PROMPT = (AGENT / "read_prompt.md").read_text(encoding="utf-8").strip()
READ_SCHEMA = json.loads((AGENT / "read_schema.json").read_text(encoding="utf-8"))
DECIDE_PROMPT = (AGENT / "decide_prompt.md").read_text(encoding="utf-8").strip()
DECIDE_SCHEMA = json.loads((AGENT / "decide_schema.json").read_text(encoding="utf-8"))

PREFIX = "Lead Follow-Up |"
AGENT_WORKFLOW_NAME = f"{PREFIX} 1. Agent turn"
AGENT_WEBHOOK_PATH = "lead-message"
AGENT_OUTPUT = WORKFLOW_DIR / "lead-agent-turn.json"

# Chosen in docs/agent-eval.md. USD per 1M tokens (input, cached input, output).
REASONING_EFFORT = "low"
MODEL_PRICES = {"gpt-5.4-mini": (0.75, 0.075, 4.50), "gpt-5.4-nano": (0.20, 0.02, 1.25)}

COMPANY_NAME = "Copperline Plumbing & Air"
EMAIL_FOOTER = ("--\nAutomated demo reply from a fictional company (Copperline Plumbing & Air). "
                "No real service is offered.")


def load_env() -> dict[str, str]:
    values = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
        match = re.match(r"^\s*([A-Z0-9_]+)=(.*)$", line)
        if match:
            values[match.group(1)] = match.group(2).strip().strip('"').strip("'")
    return values


# ---------- Node helpers ----------

def node_id(name: str) -> str:
    """Stable IDs so re-deploying doesn't reshuffle the workflow."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"lead-follow-up/{name}"))


def node(name: str, type_: str, version: float, position, parameters: dict, **extra) -> dict:
    return {"id": node_id(name), "name": name, "type": type_, "typeVersion": version,
            "position": list(position), "parameters": parameters, **extra}


def code(name: str, position, js: str, per_item: bool = False, **extra) -> dict:
    params = {"jsCode": js}
    if per_item:
        params["mode"] = "runOnceForEachItem"
    return node(name, "n8n-nodes-base.code", 2, position, params, **extra)


def supabase_request(name: str, position, method: str, path: str, body: str | None = None,
                     prefer: str | None = None, **extra) -> dict:
    """HTTP Request node for Supabase, always in this project's leads schema."""
    headers = [{"name": "Accept-Profile", "value": "leads"}, {"name": "Content-Profile", "value": "leads"}]
    if prefer:
        headers.append({"name": "Prefer", "value": prefer})
    params = {
        "method": method,
        "url": "={{ $('Config').first().json.supabase_url }}" + path,
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "supabaseApi",
        "sendHeaders": True,
        "headerParameters": {"parameters": headers},
        "options": {},
    }
    if body is not None:
        params.update({"sendBody": True, "specifyBody": "json", "jsonBody": body})
    return node(name, "n8n-nodes-base.httpRequest", 4.2, position, params, **extra)


def rpc(name: str, position, function: str, body: str, **extra) -> dict:
    return supabase_request(name, position, "POST", f"/rest/v1/rpc/{function}", body=body, **extra)


def openai_request(name: str, position, **extra) -> dict:
    # Deliberately no retryOnFail: n8n runs a node maxTries times even when the
    # call succeeds, which tripled every AI call in the invoice project. A real
    # failure goes to the error branch instead.
    return node(name, "n8n-nodes-base.httpRequest", 4.2, position, {
        "method": "POST",
        "url": "https://api.openai.com/v1/responses",
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "openAiApi",
        "sendBody": True,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify($json.body) }}",
        "options": {"timeout": 90000},
    }, onError="continueErrorOutput", **extra)


def slack_post(name: str, position, body: str, **extra) -> dict:
    """chat.postMessage with this project's Slack bot. A Slack problem never stops the workflow."""
    return node(name, "n8n-nodes-base.httpRequest", 4.2, position, {
        "method": "POST",
        "url": "https://slack.com/api/chat.postMessage",
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "slackApi",
        "sendBody": True,
        "specifyBody": "json",
        "jsonBody": body,
        "options": {},
    }, onError="continueRegularOutput", **extra)


def gmail_request(name: str, position, method: str, url: str, body: str | None = None, **extra) -> dict:
    params = {
        "method": method,
        "url": url,
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "gmailOAuth2",
        "options": {"timeout": 30000},
    }
    if body is not None:
        params.update({"sendBody": True, "specifyBody": "json", "jsonBody": body})
    return node(name, "n8n-nodes-base.httpRequest", 4.2, position, params, **extra)


def respond(name: str, position, code_: str | int, body: str) -> dict:
    return node(name, "n8n-nodes-base.respondToWebhook", 1.1, position, {
        "respondWith": "json", "responseBody": body, "options": {"responseCode": code_},
    })


def if_node(name: str, position, left: str, operator: dict) -> dict:
    return node(name, "n8n-nodes-base.if", 2.2, position, {
        "conditions": {
            "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "loose", "version": 2},
            "conditions": [{"id": node_id(name + "/cond"), "leftValue": left, "rightValue": "", "operator": operator}],
            "combinator": "and",
        },
        "options": {},
    })


IS_TRUE = {"type": "boolean", "operation": "true", "singleValue": True}


def link(*names: str) -> dict:
    return {"main": [[{"node": n, "type": "main", "index": 0} for n in names]]}


def branch(*outputs: list[str]) -> dict:
    return {"main": [[{"node": n, "type": "main", "index": 0} for n in out] for out in outputs]}


# ---------- Workflow 1: agent turn ----------

def agent_config_code(env: dict) -> str:
    model = env.get("OPENAI_MODEL") or "gpt-5.4-mini"
    settings = {
        "supabase_url": env["SUPABASE_URL"].rstrip("/"),
        "model": model,
        "reasoning_effort": REASONING_EFFORT,
        "price_per_million": dict(zip(("input", "cached", "output"), MODEL_PRICES.get(model, (0, 0, 0)))),
        "approvals_channel": env["SLACK_APPROVALS_CHANNEL_ID"],
        "alerts_channel": env["SLACK_ALERTS_CHANNEL_ID"],
        "intake_address": env["GMAIL_INTAKE_ADDRESS"].lower(),
        "allowlist": [a.strip().lower() for a in env.get("OUTBOUND_EMAIL_ALLOWLIST", "").split(",") if a.strip()],
        "company_name": COMPANY_NAME,
        "email_footer": EMAIL_FOOTER,
    }
    return ("// Settings for this workflow. Generated by scripts/build_n8n_workflows.py.\n"
            f"return [{{ json: {json.dumps(settings, indent=2)} }}];")


VALIDATE_CODE = r"""// Check and tidy the incoming message. Callers: the dashboard (form and web
// thread) and workflow 2 (email).
const b = $('Lead message').first().json.body || {};
const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

const source = b.source === 'email' ? 'email' : 'form';
const leadId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(b.lead_id || '') ? b.lead_id : null;
const channel = source === 'email' ? 'email' : (leadId ? 'web' : 'form');
const message = str(b.message, 4000);
const email = str(b.email, 200).toLowerCase();
const zip = str(b.zip, 10);

const errors = [];
if (!message) errors.push('message is required');
if (!leadId && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) errors.push('a valid email is required');
if (zip && !/^\d{5}$/.test(zip)) errors.push('zip must be 5 digits');

return [{
  json: {
    valid: errors.length === 0,
    error: errors.join('; '),
    params: {
      p_source: source,
      p_channel: channel,
      p_body: message,
      p_name: str(b.name, 100) || null,
      p_email: email || null,
      p_phone: str(b.phone, 30) || null,
      p_zip: zip || null,
      p_subject: str(b.subject, 200) || null,
      p_external_id: str(b.external_id, 200) || null,
      p_lead_id: leadId,
      p_is_visitor: b.is_visitor === true,
      p_ip_hash: /^[a-f0-9]{64}$/.test(b.ip_hash || '') ? b.ip_hash : null,
    },
    // Email only: so the reply lands in the same Gmail thread.
    email_thread_id: str(b.thread_id, 100) || null,
    in_reply_to: str(b.message_id_header, 300) || null,
  },
}];"""


def build_read_code() -> str:
    return f"""// Step 1 of the agent: read the lead. The prompt and schema come from agent/
// in the repo, the same files scripts/eval_agent.py tests.
const config = $('Config').first().json;
const ctx = $('Get agent context').first().json;

const PROMPT = {json.dumps(READ_PROMPT)};
const SCHEMA = {json.dumps(READ_SCHEMA)};

const body = {{
  model: config.model,
  instructions: PROMPT,
  input: [{{ role: 'user', content: [{{ type: 'input_text', text: JSON.stringify({{ lead: ctx.lead, conversation: ctx.conversation }}) }}] }}],
  text: {{ format: {{ type: 'json_schema', name: 'lead_facts', schema: SCHEMA, strict: true }} }},
  reasoning: {{ effort: config.reasoning_effort }},
}};
return [{{ json: {{ body, started_at: Date.now() }} }}];"""


OUTPUT_TEXT_JS = """const outputText = response => {
  const message = (response.output || []).find(o => o.type === 'message');
  const text = message?.content?.find(c => c.type === 'output_text')?.text;
  if (!text) throw new Error('AI response had no text output');
  return JSON.parse(text);
};"""


def build_decide_code() -> str:
    return f"""// The zip rule (code, not AI), then step 2 of the agent: pick the next step.
{OUTPUT_TEXT_JS}
const config = $('Config').first().json;
const ctx = $('Get agent context').first().json;
const read = $input.first().json;

const facts = outputText(read);
facts.in_service_area = facts.zip ? ctx.service_area_zips.includes(facts.zip) : null;

const PROMPT = {json.dumps(DECIDE_PROMPT)};
const SCHEMA = {json.dumps(DECIDE_SCHEMA)};

const payload = {{
  company: ctx.company,
  faq: ctx.faq,
  price_sheet: ctx.price_sheet,
  now: ctx.now,
  facts,
  open_slots: ctx.open_slots,
  conversation: ctx.conversation,
}};
const body = {{
  model: config.model,
  instructions: PROMPT,
  input: [{{ role: 'user', content: [{{ type: 'input_text', text: JSON.stringify(payload) }}] }}],
  text: {{ format: {{ type: 'json_schema', name: 'next_step', schema: SCHEMA, strict: true }} }},
  reasoning: {{ effort: config.reasoning_effort }},
}};
return [{{ json: {{ body, facts, read_usage: read.usage || {{}} }} }}];"""


PARSE_DECISION_CODE = OUTPUT_TEXT_JS + """
// Parse the decision and work out what the two AI calls cost.
const config = $('Config').first().json;
const prev = $('Build decide request').first().json;
const response = $input.first().json;
const decision = outputText(response);

const price = config.price_per_million;
const cost = usage => {
  const cached = usage.input_tokens_details?.cached_tokens || 0;
  return ((usage.input_tokens - cached) * price.input + cached * price.cached + usage.output_tokens * price.output) / 1e6;
};
const startedAt = $('Build read request').first().json.started_at;

return [{
  json: {
    decision,
    facts: prev.facts,
    seconds: Math.round((Date.now() - startedAt) / 100) / 10,
    cost_usd: Math.round((cost(prev.read_usage) + cost(response.usage || {})) * 1e6) / 1e6,
  },
}];"""


PLAN_EFFECTS_CODE = r"""// After the reply is stored: the email to send and the Slack posts to make.
// One item per side effect; none means nothing else to do.
const config = $('Config').first().json;
const input = $('Validate input').first().json;
const ctx = $('Get agent context').first().json;
const parsed = $('Parse decision').first().json;
const applied = $('Apply decision').first().json;
const lead = ctx.lead;
const facts = parsed.facts;

const out = [];
const who = `${lead.name || 'Unknown'} (${lead.email || lead.phone || 'no contact'}${lead.phone && lead.email ? ', ' + lead.phone : ''}, zip ${lead.zip || facts.zip || 'unknown'})`;
const quote = text => String(text || '').split('\n').map(l => '> ' + l).join('\n');

// Email leads get their reply by email, but only at an address on the allow-list.
if (applied.message_status === 'sent' && applied.channel === 'email') {
  const to = String(lead.email || '').toLowerCase();
  if (config.allowlist.includes(to)) {
    out.push({ json: { kind: 'email', to, subject: lead.subject, reply: applied.reply,
                       thread_id: input.email_thread_id, in_reply_to: input.in_reply_to } });
  } else {
    out.push({ json: { kind: 'slack', channel: config.alerts_channel,
      text: `:no_entry: Reply to ${to} was not emailed: the address isn't on OUTBOUND_EMAIL_ALLOWLIST.` } });
  }
}

if (applied.final_action === 'escalate_emergency') {
  out.push({ json: { kind: 'slack', channel: config.alerts_channel,
    text: `:rotating_light: *Emergency lead: call now.* ${who}\n${facts.summary}\n${applied.owner_note || ''}` } });
}
if (applied.final_action === 'hand_off') {
  const why = (applied.violations || []).length
    ? `The agent's reply was blocked: ${applied.violations.join('; ')}.`
    : (applied.owner_note || parsed.decision.reason);
  out.push({ json: { kind: 'slack', channel: config.alerts_channel,
    text: `:raising_hand: *Lead needs you.* ${who}\n${facts.summary}\n${why}` } });
}
if (applied.approval_id) {
  out.push({ json: { kind: 'slack', channel: config.approvals_channel,
    text: `:moneybag: *Price waiting for approval.* ${who}\n${facts.summary}\nDraft reply:\n${quote(applied.reply)}` } });
}
return out;"""


BUILD_EMAIL_CODE = r"""// Build the Gmail message: plain text, UTF-8, in the lead's thread.
const config = $('Config').first().json;
const item = $json;
const b64 = s => Buffer.from(s, 'utf8').toString('base64');

const base = item.subject || 'Your request';
const subject = /^re:/i.test(base) ? base : 'Re: ' + base;
const headers = [
  `From: =?UTF-8?B?${b64(config.company_name + ' (demo)')}?= <${config.intake_address}>`,
  `To: ${item.to}`,
  `Subject: =?UTF-8?B?${b64(subject)}?=`,
  'MIME-Version: 1.0',
  'Content-Type: text/plain; charset=UTF-8',
  'Content-Transfer-Encoding: base64',
];
if (item.in_reply_to) headers.push(`In-Reply-To: ${item.in_reply_to}`, `References: ${item.in_reply_to}`);

const text = `${item.reply}\n\n${config.email_footer}`;
const mime = headers.join('\r\n') + '\r\n\r\n' + b64(text).replace(/(.{76})/g, '$1\r\n');
const raw = Buffer.from(mime, 'utf8').toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

return { json: { send: item.thread_id ? { raw, threadId: item.thread_id } : { raw } } };"""


def build_agent_workflow(env: dict) -> dict:
    y, row2, row3 = 300, 520, 740
    x = lambda col: col * 230  # noqa: E731
    lead_id = "$('Receive message').first().json.lead_id"

    nodes = [
        node("Lead message", "n8n-nodes-base.webhook", 2, (x(0), y), {
            "httpMethod": "POST", "path": AGENT_WEBHOOK_PATH, "authentication": "headerAuth",
            "responseMode": "responseNode", "options": {},
        }, webhookId=node_id("webhook")),
        code("Config", (x(1), y), agent_config_code(env)),
        code("Validate input", (x(2), y), VALIDATE_CODE),
        if_node("Valid?", (x(3), y), "={{ $json.valid }}", IS_TRUE),
        respond("Reply invalid", (x(4), row2), 400, "={{ { error: $json.error } }}"),
        rpc("Receive message", (x(4), y), "receive_message", "={{ JSON.stringify($json.params) }}"),
        if_node("Duplicate?", (x(5), y), "={{ $json.duplicate }}", IS_TRUE),
        respond("Reply duplicate", (x(6), row2), 200, "={{ { duplicate: true } }}"),
        # Remember the Gmail thread of an email lead. A no-op for everyone else.
        supabase_request(
            "Save email thread", (x(6), y), "PATCH",
            "/rest/v1/leads?id=eq.{{ $json.lead_id }}&email_thread_id=is.null",
            body="={{ JSON.stringify({ email_thread_id: $('Validate input').first().json.email_thread_id }) }}",
            prefer="return=minimal", alwaysOutputData=True, onError="continueRegularOutput",
        ),
        if_node("Agent should reply?", (x(7), y), "={{ $('Receive message').first().json.agent_should_reply }}", IS_TRUE),
        respond("Reply no agent", (x(8), row2), 200,
                "={{ { lead_id: " + lead_id + ", public_token: $('Receive message').first().json.public_token, "
                "final_action: null, reply: null } }}"),
        slack_post("Tell owner they wrote", (x(9), row2),
                   "={{ JSON.stringify({ channel: $('Config').first().json.alerts_channel, "
                   "text: ':speech_balloon: A lead you took over wrote again (' + "
                   "($('Validate input').first().json.params.p_email || 'web thread') + '):\\n> ' + "
                   "$('Validate input').first().json.params.p_body.slice(0, 500) }) }}"),
        rpc("Get agent context", (x(8), y), "get_agent_context",
            "={{ JSON.stringify({ p_lead_id: " + lead_id + " }) }}"),
        code("Build read request", (x(9), y), build_read_code()),
        openai_request("Read lead", (x(10), y)),
        code("Build decide request", (x(11), y), build_decide_code(), onError="continueErrorOutput"),
        openai_request("Decide next step", (x(12), y)),
        code("Parse decision", (x(13), y), PARSE_DECISION_CODE, onError="continueErrorOutput"),
        # The guardrails run inside apply_decision (supabase/migrations/*_agent_functions.sql).
        rpc("Apply decision", (x(14), y), "apply_decision",
            "={{ JSON.stringify({ p_lead_id: " + lead_id + ", p_trigger: 'message', "
            "p_facts: $json.facts, p_decision: $json.decision, p_model: $('Config').first().json.model }) }}",
            onError="continueErrorOutput"),
        respond("Reply done", (x(15), y), 200,
                "={{ { lead_id: " + lead_id + ", public_token: $json.public_token, "
                "final_action: $json.final_action, reply_status: $json.message_status, "
                "reply: $json.message_status === 'sent' ? $json.reply : null, "
                "seconds: $('Parse decision').first().json.seconds } }}"),
        code("Plan side effects", (x(16), y), PLAN_EFFECTS_CODE),
        node("Email or Slack?", "n8n-nodes-base.switch", 3.2, (x(17), y), {
            "rules": {"values": [
                {"conditions": {
                    "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict", "version": 2},
                    "conditions": [{"id": node_id("switch/email"), "leftValue": "={{ $json.kind }}",
                                    "rightValue": "email", "operator": {"type": "string", "operation": "equals"}}],
                    "combinator": "and"},
                 "renameOutput": True, "outputKey": "email"},
                {"conditions": {
                    "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict", "version": 2},
                    "conditions": [{"id": node_id("switch/slack"), "leftValue": "={{ $json.kind }}",
                                    "rightValue": "slack", "operator": {"type": "string", "operation": "equals"}}],
                    "combinator": "and"},
                 "renameOutput": True, "outputKey": "slack"},
            ]},
            "options": {},
        }),
        code("Build email", (x(18), y), BUILD_EMAIL_CODE, per_item=True),
        gmail_request("Send email", (x(19), y), "POST",
                      "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
                      body="={{ JSON.stringify($json.send) }}", onError="continueErrorOutput"),
        slack_post("Alert email failed", (x(20), y + 160),
                   "={{ JSON.stringify({ channel: $('Config').first().json.alerts_channel, "
                   "text: ':warning: The agent replied but the email could not be sent: ' + "
                   "String($json.error?.message ?? $json.error ?? 'unknown error').slice(0, 300) }) }}"),
        slack_post("Post to Slack", (x(18), row2), "={{ JSON.stringify({ channel: $json.channel, text: $json.text }) }}"),
        # Error branch: the message is stored, but the agent couldn't answer.
        slack_post("Alert agent failed", (x(13), row3),
                   "={{ JSON.stringify({ channel: $('Config').first().json.alerts_channel, "
                   "text: ':warning: The agent could not answer a lead (' + "
                   "($('Validate input').first().json.params.p_email || 'web thread') + '). The message is saved; "
                   "nothing was sent. Error: ' + String($json.error?.message ?? $json.error ?? 'unknown error').slice(0, 300) }) }}"),
        respond("Reply failed", (x(14), row3), 502,
                "={{ { error: 'agent_failed', lead_id: " + lead_id + " } }}"),
    ]

    connections = {
        "Lead message": link("Config"),
        "Config": link("Validate input"),
        "Validate input": link("Valid?"),
        "Valid?": branch(["Receive message"], ["Reply invalid"]),
        "Receive message": link("Duplicate?"),
        "Duplicate?": branch(["Reply duplicate"], ["Save email thread"]),
        "Save email thread": link("Agent should reply?"),
        "Agent should reply?": branch(["Get agent context"], ["Reply no agent"]),
        "Reply no agent": link("Tell owner they wrote"),
        "Get agent context": link("Build read request"),
        "Build read request": link("Read lead"),
        "Read lead": branch(["Build decide request"], ["Alert agent failed"]),
        "Build decide request": branch(["Decide next step"], ["Alert agent failed"]),
        "Decide next step": branch(["Parse decision"], ["Alert agent failed"]),
        "Parse decision": branch(["Apply decision"], ["Alert agent failed"]),
        "Apply decision": branch(["Reply done"], ["Alert agent failed"]),
        "Reply done": link("Plan side effects"),
        "Plan side effects": link("Email or Slack?"),
        "Email or Slack?": branch(["Build email"], ["Post to Slack"]),
        "Build email": link("Send email"),
        "Send email": branch([], ["Alert email failed"]),
        "Alert agent failed": link("Reply failed"),
    }
    return {"name": AGENT_WORKFLOW_NAME, "nodes": nodes, "connections": connections,
            "settings": {"executionOrder": "v1"}}


# ---------- n8n API ----------

def n8n_api(env: dict, method: str, path: str, body: dict | None = None) -> dict:
    request = urllib.request.Request(
        env["N8N_BASE_URL"].rstrip("/") + "/api/v1" + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"X-N8N-API-KEY": env["N8N_API_KEY"], "Content-Type": "application/json", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        raise SystemExit(f"n8n API {method} {path} failed: HTTP {error.code} {error.read().decode()[:500]}") from None


# Credentials this project shares with the invoice demo (same Supabase project,
# same OpenAI key, same Gmail account). Looked up in its workflows, never changed.
SHARED_TYPES = {"supabaseApi", "openAiApi", "gmailOAuth2"}
SHARED_FROM_PREFIX = "Invoice Processing |"


def needed_credential(node_: dict) -> str | None:
    params = node_["parameters"]
    if params.get("authentication") == "predefinedCredentialType":
        return params.get("nodeCredentialType")
    if params.get("authentication") == "headerAuth":
        return "httpHeaderAuth"
    return None


def own_credential_data(env: dict, cred_type: str) -> tuple[str, dict] | None:
    """This project's own credentials, created from .env when no workflow has them yet."""
    if cred_type == "slackApi":
        return "Lead Follow-Up Slack bot", {"accessToken": env["SLACK_BOT_TOKEN"]}
    if cred_type == "httpHeaderAuth":
        return "Lead Follow-Up webhook secret", {"name": "x-webhook-secret", "value": env["N8N_WEBHOOK_SECRET"]}
    return None


def collect_credentials(env: dict, workflows: list[dict]) -> dict[str, dict]:
    by_type: dict[str, dict] = {}
    for summary in workflows:
        for n in n8n_api(env, "GET", f"/workflows/{summary['id']}")["nodes"]:
            for cred_type, cred in (n.get("credentials") or {}).items():
                by_type.setdefault(cred_type, cred)
    return by_type


def deploy(env: dict, workflows: list[dict], activate: bool) -> None:
    existing = n8n_api(env, "GET", "/workflows?limit=250")["data"]
    ours = [w for w in existing if w["name"].startswith(PREFIX)]
    shared_source = [w for w in existing if w["name"].startswith(SHARED_FROM_PREFIX)]

    by_type = collect_credentials(env, ours)
    shared = {t: c for t, c in collect_credentials(env, shared_source).items() if t in SHARED_TYPES}
    for cred_type, cred in shared.items():
        by_type.setdefault(cred_type, cred)

    needed = {needed_credential(n) for w in workflows for n in w["nodes"]} - {None}
    for cred_type in sorted(needed - set(by_type)):
        own = own_credential_data(env, cred_type)
        if own:
            name, data = own
            created = n8n_api(env, "POST", "/credentials", {"name": name, "type": cred_type, "data": data})
            by_type[cred_type] = {"id": created["id"], "name": created["name"]}
            print(f"Created credential '{name}' ({cred_type}).")

    for workflow in workflows:
        missing = set()
        for n in workflow["nodes"]:
            cred_type = needed_credential(n)
            if cred_type and cred_type in by_type:
                n["credentials"] = {cred_type: by_type[cred_type]}
            elif cred_type:
                missing.add(cred_type)

        match = next((w for w in ours if w["name"] == workflow["name"]), None)
        if match:
            n8n_api(env, "PUT", f"/workflows/{match['id']}", workflow)
            workflow_id = match["id"]
            print(f"Updated '{workflow['name']}' (id {workflow_id}).")
        else:
            workflow_id = n8n_api(env, "POST", "/workflows", workflow)["id"]
            print(f"Created '{workflow['name']}' (id {workflow_id}).")
        if missing:
            print(f"  Still needs credentials of type: {', '.join(sorted(missing))}")
        elif activate:
            n8n_api(env, "POST", f"/workflows/{workflow_id}/activate")
            print("  Active.")


def write_public_copy(env: dict, workflow: dict, path: Path) -> None:
    """Save the workflow to the repo with private values replaced by placeholders."""
    text = json.dumps(workflow, indent=2, ensure_ascii=False)
    placeholders = {
        "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
        "N8N_BASE_URL": "https://YOUR-N8N-DOMAIN",
        "N8N_WEBHOOK_SECRET": "YOUR-N8N-WEBHOOK-SECRET",
        "SLACK_APPROVALS_CHANNEL_ID": "YOUR-APPROVALS-CHANNEL-ID",
        "SLACK_ALERTS_CHANNEL_ID": "YOUR-ALERTS-CHANNEL-ID",
        "GMAIL_INTAKE_ADDRESS": "intake@example.com",
    }
    for key, placeholder in placeholders.items():
        value = env.get(key, "").rstrip("/")
        if value:
            text = re.sub(re.escape(value), placeholder, text, flags=re.IGNORECASE)
    for address in env.get("OUTBOUND_EMAIL_ALLOWLIST", "").split(","):
        if address.strip():
            text = re.sub(re.escape(address.strip()), "customer@example.com", text, flags=re.IGNORECASE)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text + "\n", encoding="utf-8")
    print(f"Wrote {path.relative_to(ROOT)} ({len(workflow['nodes'])} nodes)")


def main() -> None:
    from email_intake_workflow import OUTPUT as EMAIL_OUTPUT, build_email_intake_workflow

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--deploy", action="store_true", help="create or update the workflows in n8n")
    parser.add_argument("--activate", action="store_true", help="also switch them on (needs --deploy)")
    args = parser.parse_args()

    env = load_env()
    agent = build_agent_workflow(env)
    email = build_email_intake_workflow(env)
    write_public_copy(env, agent, AGENT_OUTPUT)
    write_public_copy(env, email, EMAIL_OUTPUT)
    if args.deploy:
        deploy(env, [agent, email], args.activate)


if __name__ == "__main__":
    main()
