"""End-to-end test of price approvals (workflow 3).

Creates price leads through the live agent webhook, then sends signed fake
Slack button clicks to the approval webhook, exactly as Slack would, and
checks the database. The real Slack messages in #lead-approvals get updated
with the outcome. Makes real AI calls. Every test lead is deleted at the end.

Uses only the Python standard library. Usage (from the project root):
    python scripts/test_approval.py
"""

from __future__ import annotations

import hashlib
import hmac
import json
import time
import urllib.error
import urllib.parse
import urllib.request

from test_guardrails import ENV, TEST_NAME, request, rpc, table
from test_n8n_agent import form_lead

WEBHOOK = ENV["N8N_BASE_URL"].rstrip("/") + "/webhook/lead-slack-actions"


def click(approval_id: int, approve: bool, slack_ts: str | None, secret: str | None = None) -> int:
    """Send a Slack block_actions payload signed with the app's signing secret."""
    payload = {
        "type": "block_actions",
        "user": {"id": "UTEST", "name": "approval-test"},
        "channel": {"id": ENV["SLACK_APPROVALS_CHANNEL_ID"]},
        "message": {"ts": slack_ts},
        "actions": [{"action_id": "approve_price" if approve else "reject_price", "value": str(approval_id)}],
    }
    body = urllib.parse.urlencode({"payload": json.dumps(payload)})
    timestamp = str(int(time.time()))
    signature = "v0=" + hmac.new((secret or ENV["SLACK_SIGNING_SECRET"]).encode(),
                                 f"v0:{timestamp}:{body}".encode(), hashlib.sha256).hexdigest()
    req = urllib.request.Request(WEBHOOK, data=body.encode(), method="POST", headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "X-Slack-Request-Timestamp": timestamp,
        "X-Slack-Signature": signature,
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def price_lead() -> tuple[str | None, dict | None]:
    status, body = form_lead("How much would a new 50 gallon gas water heater cost, installed?")
    if status != 200 or body.get("final_action") != "draft_price":
        return None, None
    lead_id = body["lead_id"]
    for _ in range(10):  # the Slack post happens just after the webhook answers
        approval = table("approvals", f"lead_id=eq.{lead_id}&select=id,status,slack_ts,message_id")[0]
        if approval["slack_ts"]:
            break
        time.sleep(1)
    return lead_id, approval


def wait_for(check, seconds: int = 15):
    for _ in range(seconds):
        result = check()
        if result:
            return result
        time.sleep(1)
    return check()


def run_tests() -> list[tuple[str, bool, str]]:
    results = []

    def test(name: str, ok: bool, detail=""):
        results.append((name, bool(ok), str(detail)[:400]))

    # Approve
    lead_id, approval = price_lead()
    test("a price question creates a pending approval posted to Slack",
         approval and approval["status"] == "pending" and approval["slack_ts"], approval)
    if approval:
        code = click(approval["id"], True, approval["slack_ts"], secret="not-the-secret")
        time.sleep(3)
        still = table("approvals", f"id=eq.{approval['id']}&select=status")[0]["status"]
        test("a click with a bad signature changes nothing", still == "pending", (code, still))

        code = click(approval["id"], True, approval["slack_ts"])
        done = wait_for(lambda: table("approvals", f"id=eq.{approval['id']}&select=status,decided_by")[0]
                        if table("approvals", f"id=eq.{approval['id']}&select=status")[0]["status"] != "pending" else None)
        test("Approve records the decision", done and done["status"] == "approved" and done["decided_by"] == "approval-test",
             (code, done))
        message = table("messages", f"id=eq.{approval['message_id']}&select=status")[0]
        lead = table("leads", f"id=eq.{lead_id}&select=status,awaiting_reply_since")[0]
        test("the approved price is sent to the web thread and the follow-up clock starts",
             message["status"] == "sent" and lead["status"] == "active" and lead["awaiting_reply_since"], (message, lead))
        context = rpc("get_agent_context", p_lead_id=lead_id)
        test("the approved price is in the conversation the agent sees, marked approved",
             any(t.get("approved") for t in context["conversation"]), context["conversation"])

        click(approval["id"], False, approval["slack_ts"])
        time.sleep(4)
        again = table("approvals", f"id=eq.{approval['id']}&select=status")[0]["status"]
        test("a second click (Reject after Approve) changes nothing", again == "approved", again)

    # Reject
    lead_id, approval = price_lead()
    if approval:
        click(approval["id"], False, approval["slack_ts"])
        done = wait_for(lambda: table("approvals", f"id=eq.{approval['id']}&select=status")[0]["status"] != "pending")
        message = table("messages", f"id=eq.{approval['message_id']}&select=status")[0]
        lead = table("leads", f"id=eq.{lead_id}&select=status,end_state")[0]
        test("Reject sends nothing and hands the lead to the owner",
             done and message["status"] == "rejected" and lead["status"] == "handed_off", (message, lead))
    else:
        test("a second price question creates an approval", False, "no approval")
    return results


def main() -> None:
    try:
        results = run_tests()
    finally:
        request("DELETE", f"leads?name=eq.{urllib.parse.quote(TEST_NAME)}")
    passed = sum(ok for _, ok, _ in results)
    for name, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name}" + ("" if ok else f"\n      {detail}"))
    print(f"\n{passed} / {len(results)} passed. Test leads deleted.")
    raise SystemExit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
