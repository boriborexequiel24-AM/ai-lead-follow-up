"""n8n workflow 4: "Follow-ups".

Every minute:
  1. Releases follow-ups that waited for quiet hours (real clock only) and
     emails the ones for email leads.
  2. Claims leads whose next follow-up is due (leads.claim_follow_ups, which
     reads the demo or real clock from leads.settings). For each one:
       - after 3 unanswered follow-ups: closes the lead as no_response
         (no AI call)
       - otherwise: writes a follow-up with agent/follow_up_prompt.md (the
         same file scripts/eval_agent.py tests), runs it through the
         guardrails in leads.apply_decision, and emails it to email leads.
         A follow-up the lead overtook by replying is dropped; one the rules
         block goes to the owner in Slack.
Web leads see their follow-ups in the thread on the dashboard.

Built and deployed by scripts/build_n8n_workflows.py.
"""

from __future__ import annotations

import json

from build_n8n_workflows import (
    AGENT, BUILD_EMAIL_CODE, DECIDE_SCHEMA, IS_TRUE, OUTPUT_TEXT_JS, PREFIX, ROOT, SLACK_BLOCKS_JS,
    agent_config_code, branch, code, gmail_request, if_node, link, node, openai_request, rpc, slack_post,
)

OUTPUT = ROOT / "n8n" / "workflows" / "lead-follow-ups.json"
WORKFLOW_NAME = f"{PREFIX} 4. Follow-ups"
FOLLOW_UP_PROMPT = (AGENT / "follow_up_prompt.md").read_text(encoding="utf-8").strip()
MAX_PER_RUN = 10

CLOSE_DECISION = {
    "action": "close", "reason": "No reply after 3 follow-ups.", "reply": "", "price_code": None,
    "offered_slots": [], "slot": None, "end_state": "no_response", "owner_note": "",
}


PLAN_SCHEDULED_EMAIL_CODE = """// A follow-up released after quiet hours: email it if it's for an email lead.
const config = $('Config').first().json;
const r = $json;
const to = String(r.email || '').toLowerCase();
if (r.channel === 'email' && config.allowlist.includes(to)) {
  return { json: { kind: 'email', to, subject: r.subject, reply: r.reply, thread_id: r.thread_id, in_reply_to: null } };
}
return { json: { kind: 'none' } };"""


def build_follow_up_code() -> str:
    return f"""// Write a follow-up. The prompt comes from agent/follow_up_prompt.md, tested by scripts/eval_agent.py.
const config = $('Config').first().json;
const due = $('Claim follow-ups').item.json;
const ctx = $json;

const facts = {{ ...(due.facts || {{}}) }};
facts.in_service_area = facts.zip ? ctx.service_area_zips.includes(facts.zip) : null;

const PROMPT = {json.dumps(FOLLOW_UP_PROMPT)};
const SCHEMA = {json.dumps(DECIDE_SCHEMA)};

const payload = {{
  follow_up_number: due.follow_up_number,
  company: ctx.company,
  faq: ctx.faq,
  price_sheet: ctx.price_sheet,
  now: ctx.now,
  today: ctx.today,
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
return {{ json: {{ body, facts }} }};"""


PARSE_FOLLOW_UP_CODE = OUTPUT_TEXT_JS + """
return { json: { decision: outputText($json), facts: $('Build follow-up request').item.json.facts } };"""


PLAN_FOLLOW_UP_EMAIL_CODE = SLACK_BLOCKS_JS + r"""
// Email the follow-up if it went out and the lead came in by email. If the
// rules blocked it, the lead is the owner's now, so tell them. A follow-up the
// lead overtook by replying (stale) needs nothing.
const config = $('Config').first().json;
const due = $('Claim follow-ups').item.json;
const a = $json;
if (a.final_action === 'hand_off') {
  const lead = $('Get agent context').item.json.lead;
  return { json: { kind: 'slack', channel: config.alerts_channel,
    text: `:raising_hand: *Lead needs you.* ${whoLine(lead)}\nA follow-up was blocked: ${slackText((a.violations || []).join('; '))}. Nothing was sent.` } };
}
const to = String(due.email || '').toLowerCase();
if (a.message_status === 'sent' && a.channel === 'email' && config.allowlist.includes(to)) {
  return { json: { kind: 'email', to, subject: due.subject, reply: a.reply, thread_id: due.thread_id, in_reply_to: null } };
}
return { json: { kind: 'none' } };"""


def build_follow_up_workflow(env: dict) -> dict:
    y, row_close, row_sched = 300, 520, 80
    x = lambda col: col * 220  # noqa: E731
    lead_id = "$('Claim follow-ups').item.json.lead_id"
    error_text = "String($json.error?.message ?? $json.error ?? 'unknown error').slice(0, 300)"

    nodes = [
        node("Every minute", "n8n-nodes-base.scheduleTrigger", 1.2, (x(0), y), {
            "rule": {"interval": [{"field": "minutes", "minutesInterval": 1}]},
        }),
        code("Config", (x(1), y), agent_config_code(env)),
        # Branch 1: follow-ups that waited for quiet hours.
        rpc("Release scheduled", (x(2), row_sched), "release_scheduled", "={{ JSON.stringify({}) }}"),
        code("Plan scheduled email", (x(3), row_sched), PLAN_SCHEDULED_EMAIL_CODE, per_item=True),
        # Branch 2: leads whose next follow-up is due.
        rpc("Claim follow-ups", (x(2), y), "claim_follow_ups", f"={{{{ JSON.stringify({{ p_limit: {MAX_PER_RUN} }}) }}}}"),
        if_node("Out of follow-ups?", (x(3), y), "={{ $json.follow_up_number > 3 }}", IS_TRUE),
        rpc("Close as no response", (x(4), row_close), "apply_decision",
            "={{ JSON.stringify({ p_lead_id: $json.lead_id, p_trigger: 'follow_up', p_facts: $json.facts || {}, "
            f"p_decision: {json.dumps(CLOSE_DECISION)}, p_model: null }}) }}}}"),
        rpc("Get agent context", (x(4), y), "get_agent_context", "={{ JSON.stringify({ p_lead_id: $json.lead_id }) }}"),
        code("Build follow-up request", (x(5), y), build_follow_up_code(), per_item=True),
        openai_request("Write follow-up", (x(6), y)),
        code("Parse follow-up", (x(7), y), PARSE_FOLLOW_UP_CODE, per_item=True, onError="continueErrorOutput"),
        rpc("Apply follow-up", (x(8), y), "apply_decision",
            "={{ JSON.stringify({ p_lead_id: " + lead_id + ", p_trigger: 'follow_up', p_facts: $json.facts, "
            "p_decision: $json.decision, p_model: $('Config').first().json.model }) }}",
            onError="continueErrorOutput"),
        code("Plan follow-up email", (x(9), y), PLAN_FOLLOW_UP_EMAIL_CODE, per_item=True),
        # Both branches meet here.
        if_node("Email it?", (x(10), y), "={{ $json.kind === 'email' }}", IS_TRUE),
        code("Build email", (x(11), y), BUILD_EMAIL_CODE, per_item=True),
        if_node("Tell owner?", (x(11), row_close), "={{ $json.kind === 'slack' }}", IS_TRUE),
        slack_post("Post hand-off", (x(12), row_close), "={{ JSON.stringify({ channel: $json.channel, text: $json.text }) }}"),
        gmail_request("Send email", (x(12), y), "POST",
                      "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
                      body="={{ JSON.stringify($json.send) }}", onError="continueErrorOutput"),
        slack_post("Alert email failed", (x(13), y + 160),
                   "={{ JSON.stringify({ channel: $('Config').first().json.alerts_channel, "
                   "text: ':warning: A follow-up was written but the email could not be sent: ' + " + error_text + " }) }}"),
        slack_post("Alert follow-up failed", (x(8), row_close),
                   "={{ JSON.stringify({ channel: $('Config').first().json.alerts_channel, "
                   "text: ':warning: A follow-up could not be written. It will be retried in 5 minutes. Error: ' + "
                   + error_text + " }) }}"),
    ]

    connections = {
        "Every minute": link("Config"),
        "Config": link("Release scheduled", "Claim follow-ups"),
        "Release scheduled": link("Plan scheduled email"),
        "Plan scheduled email": link("Email it?"),
        "Claim follow-ups": link("Out of follow-ups?"),
        "Out of follow-ups?": branch(["Close as no response"], ["Get agent context"]),
        "Get agent context": link("Build follow-up request"),
        "Build follow-up request": link("Write follow-up"),
        "Write follow-up": branch(["Parse follow-up"], ["Alert follow-up failed"]),
        "Parse follow-up": branch(["Apply follow-up"], ["Alert follow-up failed"]),
        "Apply follow-up": branch(["Plan follow-up email"], ["Alert follow-up failed"]),
        "Plan follow-up email": link("Email it?"),
        "Email it?": branch(["Build email"], ["Tell owner?"]),
        "Tell owner?": branch(["Post hand-off"], []),
        "Build email": link("Send email"),
        "Send email": branch([], ["Alert email failed"]),
    }
    return {
        "name": WORKFLOW_NAME,
        "nodes": nodes,
        "connections": connections,
        # Runs every minute and usually finds nothing, so only failures are kept.
        "settings": {"executionOrder": "v1", "saveDataSuccessExecution": "none", "saveDataErrorExecution": "all"},
    }
